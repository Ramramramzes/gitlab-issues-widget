import Foundation

struct GitLabREST {
    let config: Configuration
    let transport: GitLabTransport

    let token: String?

    func response(from url: URL, method: String = "GET", body: [String: Any]? = nil) async throws -> (Data, HTTPURLResponse) {
        try await transport.response(from: url, config: config, token: token, method: method, body: body)
    }

    func verifyUser(expected username: String, checkIssues: Bool = true) async throws -> GitLabUser {
        let user: GitLabUser
        do { user = try await value(from: config.apiURL("user")) }
        catch { throw GitLabReadFailure(resource: .profile, cause: error) }
        guard user.username.caseInsensitiveCompare(username) == .orderedSame else {
            throw ConnectionError.differentAccount(user.username)
        }
        guard checkIssues else { return user }
        var check = URLComponents(url: config.issuesURL, resolvingAgainstBaseURL: false)!
        check.queryItems = (check.queryItems ?? []) + [URLQueryItem(name: "per_page", value: "1")]
        do { let _: [Issue] = try await value(from: check.url!) }
        catch { throw GitLabReadFailure(resource: .openIssues, cause: error) }
        return user
    }

    private struct TokenScopes: Decodable {
        let scopes: [String]
        let granularScopes: [GranularScope]?
        struct GranularScope: Decodable {}
        enum CodingKeys: String, CodingKey { case scopes; case granularScopes = "granular_scopes" }
    }

    func checkWriteScope() async throws {
        let permissions: TokenScopes? = try? await value(from: config.apiURL("personal_access_tokens/self"))
        try Task.checkCancellation()
        if let permissions, permissions.scopes.contains("read_api"), !permissions.scopes.contains("api"),
           permissions.granularScopes?.isEmpty != false {
            throw GitLabError.readOnlyToken
        }
    }

    func assignedIssues(closedOn day: Date? = nil) async throws -> [Issue] {
        let url = day.map { config.closedIssuesURL(on: $0) } ?? config.issuesURL
        do { return try await pages(from: url) }
        catch { throw GitLabReadFailure(resource: day == nil ? .openIssues : .closedIssues, cause: error) }
    }

    func value<T: Decodable>(from url: URL) async throws -> T {
        try JSONDecoder().decode(T.self, from: try await response(from: url).0)
    }

    func pages<T: Decodable>(from url: URL, stopAfter: (([T]) -> Bool)? = nil) async throws -> [T] {
        guard config.allowsAPIURL(url), var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw URLError(.badURL) }
        let filters = (components.queryItems ?? []).filter { !["page", "per_page"].contains($0.name) }
        var values: [T] = []
        var page = 1
        while true {
            components.queryItems = filters + [URLQueryItem(name: "per_page", value: "100"), URLQueryItem(name: "page", value: String(page))]
            let (data, http) = try await response(from: components.url!)
            let batch = try JSONDecoder().decode([T].self, from: data)
            values += batch
            if stopAfter?(batch) == true { return values }
            guard let next = http.value(forHTTPHeaderField: "X-Next-Page"), !next.isEmpty else { return values }
            guard let number = Int(next), number > page else { throw URLError(.badServerResponse) }
            page = number
        }
    }

    func latestDeployment(project: GitLabProject, branch: String) async throws -> GitLabDeployment? {
        let url = config.apiURL("projects/\(project.id)/deployments", query: [URLQueryItem(name: "order_by", value: "id"), URLQueryItem(name: "sort", value: "desc")])
        // The deployments endpoint has no ref filter: scan pages until this branch is found.
        let values: [GitLabDeployment] = try await pages(from: url, stopAfter: { $0.contains { $0.ref == branch } })
        return values.first { $0.ref == branch }
    }

    func branch(project: GitLabProject, name: String) async throws -> GitLabBranch {
        try await value(from: config.apiURL("projects/\(project.id)/repository/branches/\(Configuration.encodeSegment(name))"))
    }

    private struct RESTLabel: Decodable {
        let name: String
        let color: String
        var label: IssueLabel { IssueLabel(id: name, title: name, color: color) }
    }

    func labels(project: String) async throws -> [IssueLabel] {
        let values: [RESTLabel] = try await pages(from: config.apiURL("projects/\(project)/labels"))
        return values.map(\.label)
    }

    func editorData(for issue: Issue) async throws -> (IssueDetails, [IssueLabel]) {
        let path = try issue.issueAPIPath()
        let project = issue.projectID.map(String.init) ?? Configuration.encodeSegment(issue.projectPath)
        let current: Issue = try await value(from: config.apiURL(path))
        let labels = try await labels(project: project)
        let assigned = current.labels.map { name in
            labels.first { $0.title == name } ?? IssueLabel(id: name, title: name, color: "#65717e")
        }
        return (IssueDetails(status: nil, statuses: [], labels: assigned, canEdit: true,
                             title: current.title, description: current.description, usesREST: true), labels)
    }

    func create(projectPath: String, context: CreationContext, title: String, description: String, labelIDs: Set<String>) async throws -> URL {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw GitLabError.emptyTitle }
        guard context.details.canEdit, let userID = Int(context.userID) else { throw GitLabError.forbidden }
        let url = config.apiURL("projects/\(Configuration.encodeSegment(projectPath))/issues")
        let body: [String: Any] = [
            "title": title, "description": description, "assignee_ids": [userID], "labels": labelIDs.sorted().joined(separator: ",")
        ]
        let (data, http) = try await response(from: url, method: "POST", body: body)
        guard http.statusCode == 201 else { throw GitLabError.rejected }
        let created = try JSONDecoder().decode(Issue.self, from: data)
        guard config.allowsAPIURL(created.url) else { throw GitLabError.unavailable }
        return created.url
    }

    func confirmCreation(at url: URL, projectPath: String, assigneeID: Int) async throws {
        let projectURL = config.baseURL.path + "/" + projectPath + "/-/"
        guard config.allowsAPIURL(url), url.path.hasPrefix(projectURL), let iid = Int(url.lastPathComponent), iid > 0 else {
            throw GitLabError.creationUnconfirmed
        }
        let project = Configuration.encodeSegment(projectPath)
        let issue: Issue
        do {
            issue = try await value(from: config.apiURL("projects/\(project)/issues/\(iid)"))
        } catch {
            try Task.checkCancellation()
            if (error as? URLError)?.code == .userAuthenticationRequired { throw error }
            throw GitLabError.creationUnconfirmed
        }
        guard issue.globalID.map({ $0 > 0 }) == true, issue.iid == iid, config.allowsAPIURL(issue.url),
              issue.url.path.hasPrefix(projectURL), issue.url.lastPathComponent == String(iid) else {
            throw GitLabError.creationUnconfirmed
        }
        guard issue.assignees?.contains(where: { $0.id == assigneeID }) == true else {
            throw GitLabError.creationUnassigned
        }
    }

    func update(issue: Issue, original: IssueDetails, labelIDs: Set<String>, closed: Bool,
                title: String?, description: String?) async throws {
        var body: [String: Any] = [:]
        if let title {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw GitLabError.emptyTitle }
            if trimmed != (original.title ?? issue.title) { body["title"] = trimmed }
        }
        if let description, description != (original.description ?? "") { body["description"] = description }
        if closed != (issue.state == "closed") { body["state_event"] = closed ? "close" : "reopen" }
        let originalLabels = Set(original.labels.map(\.id))
        let added = labelIDs.subtracting(originalLabels)
        let removed = originalLabels.subtracting(labelIDs)
        if !added.isEmpty { body["add_labels"] = added.sorted().joined(separator: ",") }
        if !removed.isEmpty { body["remove_labels"] = removed.sorted().joined(separator: ",") }
        if !body.isEmpty {
            _ = try await response(from: config.apiURL(try issue.issueAPIPath()), method: "PUT", body: body)
        }
    }
}
