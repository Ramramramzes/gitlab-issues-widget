import Foundation

struct WorkStatus: Decodable, Identifiable {
    let id: String
    let name: String
    let color: String
    let category: String
    var normalizedCategory: String { category.uppercased() }
    var closesIssue: Bool { ["DONE", "CANCELED"].contains(normalizedCategory) }
}

struct IssueLabel: Decodable, Identifiable {
    let id: String
    let title: String
    let color: String
    var scope: String? { title.contains("::") ? title.components(separatedBy: "::")[0] : nil }
}

struct IssueDetails {
    let status: WorkStatus?
    let statuses: [WorkStatus]
    let labels: [IssueLabel]
    let canEdit: Bool
    var title: String? = nil
    var description: String? = nil
    var canDelete = false
    var usesREST = false
}

struct CreationContext {
    let typeID: String
    let userID: String
    let details: IssueDetails
}
