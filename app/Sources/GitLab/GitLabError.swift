import Foundation

enum GitLabError: LocalizedError, Equatable {
    case rejected, unavailable, labelsIncomplete, forbidden, emptyTitle, gatewayLogin
    case creationUnconfirmed, creationUnassigned
    case readOnlyToken, insufficientScope, invalidStatus
    case serverRejection(status: Int?, reason: String)
    case httpStatus(Int)

    static func rejection(_ messages: [String], status: Int? = nil, redacting token: String?) -> GitLabError {
        var reason = messages.joined(separator: " · ")
        if let token, !token.isEmpty { reason = reason.replacingOccurrences(of: token, with: "[скрыто]") }
        reason = reason.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if reason.isEmpty {
            if status == 403 { return .forbidden }
            return status.map(GitLabError.httpStatus) ?? .rejected
        }
        return .serverRejection(status: status, reason: String(reason.prefix(400)))
    }

    var errorDescription: String? {
        switch self {
        case .rejected: return tr("GitLab не подтвердил изменение. Обнови задачу перед повторной попыткой.")
        case .unavailable: return tr("Не удалось получить данные задачи из GitLab.")
        case .labelsIncomplete: return tr("Слишком много меток задачи. Измени их в браузере.")
        case .forbidden: return tr("GitLab отказал в доступе. Проверь права аккаунта и токена.")
        case .gatewayLogin: return tr("API перенаправляет на страницу входа. Проверь адрес, VPN или доступ через корпоративный шлюз.")
        case .emptyTitle: return tr("Укажи название задачи.")
        case .creationUnconfirmed: return tr("Не удалось подтвердить задачу в GitLab. Открой ссылку или повтори проверку.")
        case .creationUnassigned: return tr("Задача есть в GitLab, но её не назначили тебе. Открой её в браузере, назначь себя и повтори проверку.")
        case .readOnlyToken: return tr("Подключён токен с read_api. Для изменения задач нужен токен с правом api или разрешением обновлять рабочие элементы этого проекта.")
        case .insufficientScope: return tr("GitLab сообщил, что токену не хватает прав для запроса. Проверь разрешения токена для выбранного проекта.")
        case .invalidStatus: return tr("Этот статус больше недоступен. Открой задачу заново, чтобы обновить список статусов.")
        case .serverRejection(let status, let reason):
            let code = status.map { " (HTTP \($0))" } ?? ""
            return tr("GitLab отклонил запрос%@. %@", code, reason.replacingOccurrences(of: "[скрыто]", with: tr("[скрыто]")))
        case .httpStatus(let status): return tr("GitLab вернул HTTP %lld.", status)
        }
    }
}

struct GitLabReadFailure: LocalizedError {
    enum Resource: String {
        case profile = "Профиль"
        case openIssues = "Открытые задачи"
        case closedIssues = "Закрытые сегодня"
    }

    let resource: Resource
    let cause: Error

    var needsLogin: Bool { (cause as? URLError)?.code == .userAuthenticationRequired }

    var errorDescription: String? {
        let reason: String
        if needsLogin {
            reason = tr("HTTP 401. Проверь токен и срок его действия.")
        } else if let error = cause as? GitLabError {
            switch error {
            case .forbidden:
                reason = tr("HTTP 403. Проверь право read_api и ограничения доступа на сервере.")
            case .httpStatus(404):
                reason = tr("API вернул HTTP 404. Укажи адрес самого GitLab, без пути к проекту или задаче.")
            case .httpStatus(429):
                reason = tr("HTTP 429. GitLab ограничил частоту запросов. Попробуй позже.")
            default: reason = error.localizedDescription
            }
        } else if cause is DecodingError {
            reason = tr("Ответ GitLab имеет неожиданный формат.")
        } else {
            reason = tr("Нет ответа от GitLab. Проверь адрес, сеть и VPN.")
        }
        return "\(tr(resource.rawValue)) · \(reason)"
    }
}
