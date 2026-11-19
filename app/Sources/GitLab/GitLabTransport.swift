import Foundation

final class GitLabTransport: Sendable {
    private let session: URLSession

    init(_ session: URLSession) {
        self.session = session
    }

    func response(from url: URL, config: Configuration, token: String?,
                  method: String = "GET", body: [String: Any]? = nil) async throws -> (Data, HTTPURLResponse) {
        guard config.allowsAPIURL(url) else { throw URLError(.badURL) }
        guard let token, !token.isEmpty else { throw URLError(.userAuthenticationRequired) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue(token, forHTTPHeaderField: "PRIVATE-TOKEN")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await self.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, let finalURL = http.url, config.allowsAPIURL(finalURL) else {
            throw URLError(.badServerResponse)
        }
        if method != "GET", [400, 401, 403, 409, 422].contains(http.statusCode) {
            let fields = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let challenge = http.value(forHTTPHeaderField: "WWW-Authenticate") ?? ""
            if fields?["error"] as? String == "insufficient_scope" || challenge.contains("insufficient_scope") {
                throw GitLabError.insufficientScope
            }
            if http.statusCode != 401 {
                var messages = ["error_description", "message"].compactMap { fields?[$0] as? String }
                if let validation = fields?["message"] as? [String: [String]] {
                    for key in validation.keys.sorted() {
                        messages += (validation[key] ?? []).map { "\(key) \($0)" }
                    }
                }
                if let errors = fields?["errors"] as? [[String: String]] { messages += errors.compactMap { $0["message"] } }
                throw GitLabError.rejection(messages, status: http.statusCode, redacting: token)
            }
        }
        if http.statusCode == 401 { throw URLError(.userAuthenticationRequired) }
        if http.statusCode == 403 { throw GitLabError.forbidden }
        if (300..<400).contains(http.statusCode) || (http.statusCode == 200 && http.mimeType == "text/html") {
            throw GitLabError.gatewayLogin
        }
        guard [200, 201].contains(http.statusCode) else {
            throw GitLabError.httpStatus(http.statusCode)
        }
        return (data, http)
    }

    private func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try Task.checkCancellation()
        defer { withExtendedLifetime(self) {} }
        return try await session.data(for: request)
    }

    static func makeSession() -> URLSession {
        let settings = URLSessionConfiguration.ephemeral
        settings.urlCache = nil
        settings.urlCredentialStorage = nil
        settings.httpCookieStorage = nil
        settings.httpShouldSetCookies = false
        settings.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: settings, delegate: RedirectGuard(), delegateQueue: nil)
    }

    // Requests retain the transport until they finish, even after an account switch.
    deinit { session.invalidateAndCancel() }
}

final class RedirectGuard: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
