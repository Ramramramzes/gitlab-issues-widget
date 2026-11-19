import Foundation
import Security

struct Configuration {
    let baseURL: URL
    let username: String
    let refreshSeconds: TimeInterval = 900

    static let initial = Configuration(baseURL: URL(string: "https://gitlab.com")!, username: "")

    static func serverURL(_ input: String) throws -> URL {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = value.contains("://") ? value : "https://" + value
        guard var components = URLComponents(string: candidate),
              components.scheme?.lowercased() == "https", let host = components.host?.lowercased(), !host.isEmpty,
              components.user == nil, components.password == nil, components.query == nil, components.fragment == nil,
              components.port.map({ (1...65535).contains($0) }) ?? true,
              !components.path.contains("\\"),
              !components.path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }) else {
            throw ConnectionError.invalidServer
        }
        components.host = host
        components.scheme = "https"
        if components.port == 443 { components.port = nil }
        let path = components.path.split(separator: "/").joined(separator: "/")
        components.path = path.isEmpty ? "" : "/" + path
        guard let url = components.url else { throw ConnectionError.invalidServer }
        return url
    }

    func endpoint(_ encodedPath: String, query: [URLQueryItem] = []) -> URL {
        var parts = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        parts.percentEncodedPath += "/" + encodedPath
        parts.queryItems = query.isEmpty ? nil : query
        return parts.url!
    }

    func apiURL(_ path: String, query: [URLQueryItem] = []) -> URL { endpoint("api/v4/" + path, query: query) }

    var dashboardURL: URL { endpoint("dashboard/issues", query: [URLQueryItem(name: "scope", value: "assigned_to_me")]) }
    var tokenSettingsURL: URL { endpoint("-/user_settings/personal_access_tokens") }

    var issuesURL: URL {
        apiURL("issues", query: [
            URLQueryItem(name: "scope", value: "assigned_to_me"), URLQueryItem(name: "state", value: "opened"),
            URLQueryItem(name: "order_by", value: "created_at"), URLQueryItem(name: "sort", value: "desc")
        ])
    }

    func closedIssuesURL(on date: Date, timeZone: TimeZone = .autoupdatingCurrent) -> URL {
        var components = URLComponents(url: issuesURL, resolvingAgainstBaseURL: false)!
        components.queryItems = components.queryItems!.filter { !["state", "order_by"].contains($0.name) } + [
            URLQueryItem(name: "state", value: "closed"), URLQueryItem(name: "order_by", value: "updated_at"),
            URLQueryItem(name: "updated_after", value: ISO8601DateFormatter().string(from: IssueDay.interval(on: date, timeZone: timeZone).start))
        ]
        return components.url!
    }

    func allowsAPIURL(_ url: URL) -> Bool {
        guard url.scheme == "https", url.host?.lowercased() == baseURL.host?.lowercased(),
              (url.port ?? 443) == (baseURL.port ?? 443), url.user == nil, url.password == nil else { return false }
        return baseURL.path.isEmpty || url.path == baseURL.path || url.path.hasPrefix(baseURL.path + "/")
    }

    static func encodeSegment(_ name: String) -> String {
        name.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~")))!
    }
}

struct GitLabUser: Decodable {
    let id: Int
    let username: String
}

enum ConnectionError: LocalizedError {
    case invalidServer, missingFields, differentAccount(String), keychain(OSStatus), invalidTokenData
    var errorDescription: String? {
        switch self {
        case .invalidServer: return tr("Укажи HTTPS-адрес GitLab без логина, параметров или якоря.")
        case .missingFields: return tr("Введи ник и персональный токен.")
        case .differentAccount(let username): return tr("GitLab определил владельца токена как @%@. Для входа укажи ник и токен одного аккаунта.", username)
        case .keychain(let status): return tr("Связка ключей недоступна (%d).", status)
        case .invalidTokenData: return tr("Сохранённое подключение не читается. Подключись заново.")
        }
    }
}
