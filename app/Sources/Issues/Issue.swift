import Foundation

struct Issue: Decodable, Identifiable {
    let globalID: Int?
    let projectID: Int?
    let iid: Int?
    let title: String
    let description: String?
    var relativeProjectPath: String? = nil
    let url: URL
    let labels: [String]
    let assignees: [GitLabUser]?
    let state: String?
    let closedAt: String?
    var links: [IssueLink]? = nil
    var details: IssueDetails? = nil
    enum CodingKeys: String, CodingKey {
        case title, labels, assignees, state, iid, description
        case projectID = "project_id"
        case globalID = "id"
        case closedAt = "closed_at"
        case url = "web_url"
    }
    var id: String { url.absoluteString }
    var blockers: [IssueLink] { (links ?? []).filter { $0.state == "opened" && $0.linkType == "is_blocked_by" } }
    var blockedIssues: [IssueLink] { (links ?? []).filter { $0.state == "opened" && $0.linkType == "blocks" } }
    var number: String { "#" + url.lastPathComponent }
    var project: String {
        url.path.components(separatedBy: "/-/").first?
            .split(separator: "/").last.map(String.init) ?? "GitLab"
    }
    var projectPath: String { relativeProjectPath ?? url.path.components(separatedBy: "/-/")[0].trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
    var workItemID: String? { globalID.map { "gid://gitlab/WorkItem/\($0)" } }

    func issueAPIPath() throws -> String {
        guard let iid = iid ?? Int(url.lastPathComponent), iid > 0, projectID != nil || !projectPath.isEmpty else {
            throw GitLabError.unavailable
        }
        let project = projectID.map(String.init) ?? Configuration.encodeSegment(projectPath)
        return "projects/\(project)/issues/\(iid)"
    }
}

struct IssueLink: Codable, Identifiable {
    let title: String
    let url: URL
    let state: String
    let linkType: String
    var id: String { url.absoluteString }
    var number: String { "#" + url.lastPathComponent }
    var project: String {
        url.path.components(separatedBy: "/-/").first?
            .split(separator: "/").last.map(String.init) ?? "GitLab"
    }
    enum CodingKeys: String, CodingKey {
        case title, state
        case url = "web_url"
        case linkType = "link_type"
    }
}
