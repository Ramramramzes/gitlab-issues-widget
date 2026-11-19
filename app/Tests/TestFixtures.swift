import Foundation

final class MockProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, String))!
    static var headers: [String: String] = [:]
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, body) = try Self.handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"].merging(Self.headers) { _, value in value })!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
func requestBody(_ request: URLRequest) throws -> Data {
    if let data = request.httpBody { return data }
    guard let stream = request.httpBodyStream else { throw URLError(.badServerResponse) }
    stream.open()
    defer { stream.close() }
    var result = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count < 0 { throw stream.streamError ?? URLError(.cannotDecodeRawData) }
        if count == 0 { break }
        result.append(buffer, count: count)
    }
    return result
}

func datedIssue(_ id: Int, _ closed: String?, state: String = "closed") throws -> Issue {
    let data = try JSONSerialization.data(withJSONObject: ["id": id, "title": "Fixture", "web_url": "https://gitlab.example.com/team/front/-/issues/\(id)", "labels": [], "state": state, "closed_at": closed.map { $0 as Any } ?? NSNull(), "updated_at": "2026-11-17T10:00:00Z"])
    return try JSONDecoder().decode(Issue.self, from: data)
}
