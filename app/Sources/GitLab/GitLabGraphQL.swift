import Foundation

struct GitLabGraphQL {
    let config: Configuration
    let transport: GitLabTransport
    let token: String?

    private struct Envelope<T: Decodable>: Decodable {
        let data: T?
        let errors: [Failure]?
        struct Failure: Decodable { let message: String }
    }
    private struct PageInfo: Decodable { let hasNextPage: Bool; let endCursor: String? }
    private struct Labels: Decodable { let nodes: [IssueLabel]; let pageInfo: PageInfo }
    private struct Item: Decodable {
        let title: String?
        let userPermissions: Permissions
        let workItemType: ItemType
        let widgets: [Widget]
        struct Permissions: Decodable { let updateWorkItem: Bool; let deleteWorkItem: Bool? }
        struct ItemType: Decodable { let widgetDefinitions: [Definition] }
        struct Definition: Decodable { let allowedStatuses: [WorkStatus]? }
        struct Widget: Decodable { let status: WorkStatus?; let labels: Labels?; let description: String? }
    }
    private struct ItemData: Decodable { let workItem: Item? }
    private struct ProjectData: Decodable {
        let project: Project?
        struct Project: Decodable { let labels: Labels? }
    }
    private struct UpdateData: Decodable {
        let workItemUpdate: Result?
        struct Result: Decodable { let errors: [String]; let workItem: UpdatedItem? }
        struct UpdatedItem: Decodable { let id: String }
    }
    private struct DeleteData: Decodable {
        let workItemDelete: Result?
        struct Result: Decodable { let errors: [String] }
    }
    private struct CreateContextData: Decodable {
        let currentUser: User?
        let project: Project?
        struct User: Decodable { let id: String }
        struct Project: Decodable {
            let userPermissions: Permissions
            let workItemTypes: Types
        }
        struct Permissions: Decodable { let createIssue: Bool }
        struct Types: Decodable { let nodes: [ItemType] }
        struct ItemType: Decodable { let id: String; let widgetDefinitions: [Definition] }
        struct Definition: Decodable { let allowedStatuses: [WorkStatus]?; let defaultOpenStatus: WorkStatus? }
    }
    private struct CreateData: Decodable {
        let workItemCreate: Result?
        struct Result: Decodable { let errors: [String]; let workItem: Created? }
        struct Created: Decodable { let webUrl: URL }
    }

    private func execute<T: Decodable>(_ query: String, variables: [String: Any]) async throws -> T {
        let url = config.endpoint("api/graphql")
        let (data, _) = try await transport.response(from: url, config: config, token: token,
                                                     method: "POST", body: ["query": query, "variables": variables])
        let envelope = try JSONDecoder().decode(Envelope<T>.self, from: data)
        if let errors = envelope.errors, !errors.isEmpty {
            throw GitLabError.rejection(errors.map(\.message), redacting: token)
        }
        guard let value = envelope.data else { throw GitLabError.rejected }
        return value
    }

    func details(for issue: Issue) async throws -> IssueDetails {
        guard let id = issue.workItemID else { throw GitLabError.unavailable }
        let value: ItemData = try await execute("""
        query WidgetIssue($id: WorkItemID!) {
          workItem(id: $id) {
            title
            userPermissions { updateWorkItem deleteWorkItem }
            workItemType { widgetDefinitions { ... on WorkItemWidgetDefinitionStatus { allowedStatuses { id name color category } } } }
            widgets {
              ... on WorkItemWidgetStatus { status { id name color category } }
              ... on WorkItemWidgetLabels { labels(first: 100) { nodes { id title color } pageInfo { hasNextPage endCursor } } }
              ... on WorkItemWidgetDescription { description }
            }
          }
        }
        """, variables: ["id": id])
        guard let item = value.workItem else { throw GitLabError.unavailable }
        let labels = item.widgets.compactMap(\.labels).first
        guard labels?.pageInfo.hasNextPage != true else { throw GitLabError.labelsIncomplete }
        return IssueDetails(status: item.widgets.compactMap(\.status).first,
                            statuses: item.workItemType.widgetDefinitions.compactMap(\.allowedStatuses).flatMap { $0 },
                            labels: labels?.nodes ?? [], canEdit: item.userPermissions.updateWorkItem,
                            title: item.title, description: item.widgets.compactMap(\.description).first,
                            canDelete: item.userPermissions.deleteWorkItem ?? false)
    }

    func labels(for issue: Issue) async throws -> [IssueLabel] {
        try await labels(projectPath: issue.projectPath)
    }

    func delete(issue: Issue, original: IssueDetails) async throws {
        guard original.canDelete, let id = issue.workItemID, config.allowsAPIURL(issue.url) else { throw GitLabError.forbidden }
        let result: DeleteData = try await execute("""
        mutation WidgetDeleteIssue($input: WorkItemDeleteInput!) {
          workItemDelete(input: $input) { errors }
        }
        """, variables: ["input": ["id": id]])
        guard let result = result.workItemDelete else { throw GitLabError.rejected }
        if !result.errors.isEmpty { throw GitLabError.rejection(result.errors, redacting: token) }
    }

    func labels(projectPath: String) async throws -> [IssueLabel] {
        var cursor: String?
        var labels: [IssueLabel] = []
        repeat {
            let value: ProjectData = try await execute("""
            query WidgetLabels($path: ID!, $after: String) {
              project(fullPath: $path) { labels(first: 100, after: $after, includeAncestorGroups: true) {
                nodes { id title color } pageInfo { hasNextPage endCursor }
              } }
            }
            """, variables: ["path": projectPath, "after": cursor.map { $0 as Any } ?? NSNull()])
            guard let page = value.project?.labels else { throw GitLabError.unavailable }
            labels += page.nodes
            if !page.pageInfo.hasNextPage { return labels }
            guard let next = page.pageInfo.endCursor, next != cursor else { throw GitLabError.unavailable }
            cursor = next
        } while true
    }

    static func updateInput(issue: Issue, original: IssueDetails, statusID: String,
                            labelIDs: Set<String>, closed: Bool, title: String? = nil, description: String? = nil) throws -> [String: Any] {
        guard original.canEdit else { throw GitLabError.forbidden }
        guard let id = issue.workItemID else { throw GitLabError.unavailable }
        var input: [String: Any] = ["id": id]
        if let title, title != (original.title ?? issue.title) {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw GitLabError.emptyTitle }
            input["title"] = trimmed
        }
        if let description, description != (original.description ?? "") {
            input["descriptionWidget"] = ["description": description]
        }
        if statusID != (original.status?.id ?? "") {
            guard original.statuses.contains(where: { $0.id == statusID }) else { throw GitLabError.invalidStatus }
            input["statusWidget"] = ["status": statusID]
        }
        let previous = Set(original.labels.map(\.id))
        if previous != labelIDs {
            input["labelsWidget"] = ["addLabelIds": labelIDs.subtracting(previous).sorted(),
                                      "removeLabelIds": previous.subtracting(labelIDs).sorted()]
        }
        if original.statuses.isEmpty && closed != (issue.state == "closed") {
            input["stateEvent"] = closed ? "CLOSE" : "REOPEN"
        }
        return input
    }

    func update(issue: Issue, original: IssueDetails, statusID: String,
                labelIDs: Set<String>, closed: Bool, title: String? = nil, description: String? = nil) async throws {
        let input = try Self.updateInput(issue: issue, original: original, statusID: statusID, labelIDs: labelIDs, closed: closed, title: title, description: description)
        guard input.count > 1 else { return }
        let result: UpdateData = try await execute("""
        mutation WidgetUpdateIssue($input: WorkItemUpdateInput!) {
          workItemUpdate(input: $input) { errors workItem { id } }
        }
        """, variables: ["input": input])
        guard let result = result.workItemUpdate else { throw GitLabError.rejected }
        if !result.errors.isEmpty { throw GitLabError.rejection(result.errors, redacting: token) }
        guard result.workItem != nil else { throw GitLabError.rejected }
    }

    func creationContext(projectPath: String) async throws -> CreationContext {
        let data: CreateContextData = try await execute("""
        query WidgetCreationContext($path: ID!) {
          currentUser { id }
          project(fullPath: $path) {
            userPermissions { createIssue }
            workItemTypes(name: ISSUE, onlyAvailable: true, first: 1) { nodes {
              id widgetDefinitions { ... on WorkItemWidgetDefinitionStatus {
                allowedStatuses { id name color category } defaultOpenStatus { id name color category }
              } }
            } }
          }
        }
        """, variables: ["path": projectPath])
        guard let user = data.currentUser, let project = data.project,
              let type = project.workItemTypes.nodes.first else { throw GitLabError.unavailable }
        let definition = type.widgetDefinitions.first { $0.allowedStatuses != nil }
        return CreationContext(typeID: type.id, userID: user.id,
                               details: IssueDetails(status: definition?.defaultOpenStatus, statuses: definition?.allowedStatuses ?? [],
                                                     labels: [], canEdit: project.userPermissions.createIssue))
    }

    static func createInput(projectPath: String, context: CreationContext, title: String, description: String,
                            statusID: String, labelIDs: Set<String>) throws -> [String: Any] {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw GitLabError.emptyTitle }
        guard context.details.canEdit, !projectPath.isEmpty else { throw GitLabError.forbidden }
        var input: [String: Any] = ["namespacePath": projectPath, "workItemTypeId": context.typeID, "title": title,
                                    "descriptionWidget": ["description": description],
                                    "assigneesWidget": ["assigneeIds": [context.userID]],
                                    "labelsWidget": ["labelIds": labelIDs.sorted()]]
        if !statusID.isEmpty {
            guard context.details.statuses.contains(where: { $0.id == statusID }) else { throw GitLabError.invalidStatus }
            input["statusWidget"] = ["status": statusID]
        }
        return input
    }

    func create(projectPath: String, context: CreationContext, title: String, description: String,
                statusID: String, labelIDs: Set<String>) async throws -> URL {
        let input = try Self.createInput(projectPath: projectPath, context: context, title: title, description: description, statusID: statusID, labelIDs: labelIDs)
        let data: CreateData = try await execute("""
        mutation WidgetCreateIssue($input: WorkItemCreateInput!) {
          workItemCreate(input: $input) { errors workItem { webUrl } }
        }
        """, variables: ["input": input])
        guard let result = data.workItemCreate else { throw GitLabError.rejected }
        if !result.errors.isEmpty { throw GitLabError.rejection(result.errors, redacting: token) }
        guard let item = result.workItem, config.allowsAPIURL(item.webUrl) else { throw GitLabError.rejected }
        return item.webUrl
    }
}
