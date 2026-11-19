import Foundation

struct GitLabProject: Decodable, Identifiable {
    let id: Int
    let path: String
    let defaultBranch: String?
    enum CodingKeys: String, CodingKey { case id; case path = "path_with_namespace"; case defaultBranch = "default_branch" }
    var name: String { path.components(separatedBy: "/").last ?? path }
}

struct GitLabBranch: Decodable, Identifiable {
    let name: String
    let commit: Commit
    var id: String { name }
    struct Commit: Decodable { let id: String }
}

struct GitLabDeployment: Decodable {
    let id: Int
    let ref: String
    let sha: String
    let status: String
    let environment: Environment
    let deployable: Job?
    struct Environment: Decodable { let id: Int; let name: String }
    struct Job: Decodable {
        let webURL: URL?
        let pipeline: Pipeline?
        enum CodingKeys: String, CodingKey { case pipeline; case webURL = "web_url" }
        struct Pipeline: Decodable {
            let webURL: URL?
            enum CodingKeys: String, CodingKey { case webURL = "web_url" }
        }
    }
    func caption(head: String) -> String {
        if sha != head { return tr("Другой коммит") }
        switch status {
        case "success": return tr("Развёрнуто")
        case "running": return tr("Идёт деплой")
        case "failed": return tr("Ошибка деплоя")
        case "canceled": return tr("Отменён")
        case "skipped": return tr("Пропущен")
        case "blocked": return tr("Ждёт подтверждения")
        case "created": return tr("В очереди")
        default: return tr("Статус неизвестен")
        }
    }
}
