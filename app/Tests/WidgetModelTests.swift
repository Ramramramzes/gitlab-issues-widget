import Foundation
import Security

@MainActor
func verifyConnectionLifecycle() async throws {
    let makeTransport = {
        let settings = URLSessionConfiguration.ephemeral
        settings.protocolClasses = [MockProtocol.self]
        return URLSession(configuration: settings)
    }
    let server = "https://gitlab.example.com"
    let alice = SavedConnection(server: server, username: "alice", token: "fixture-alice", editingEnabled: false)
    let bob = SavedConnection(server: server, username: "bob", token: "fixture-bob", editingEnabled: false)
    MockProtocol.handler = { request in
        let token = request.value(forHTTPHeaderField: "PRIVATE-TOKEN")
        switch (request.url?.path, token) {
        case ("/api/v4/user", "fixture-offline"): throw URLError(.notConnectedToInternet)
        case ("/api/v4/user", "fixture-expired"): return (401, "{}")
        case ("/api/v4/user", "fixture-alice"): return (200, #"{"id":1,"username":"Alice"}"#)
        case ("/api/v4/user", "fixture-bob"): return (200, #"{"id":2,"username":"Bob"}"#)
        case ("/api/v4/issues", "fixture-bob"): return (503, "{}")
        default: return (200, "[]")
        }
    }
    let model = WidgetModel(makeTransport: makeTransport)
    await model.restoreConnection { alice }
    assert(model.connectedUsername == "Alice" && !model.loginRequired)
    do {
        try await model.connect(server: server, username: "alice", token: bob.token, editingEnabled: false, store: false)
        fatalError("Account switch used a token with a mismatched username")
    } catch ConnectionError.differentAccount("Bob") {}
    assert(model.connectedUsername == "Alice", "A failed switch must leave the verified account intact")
    try await model.connect(server: server, username: "@bOb", token: bob.token, editingEnabled: false, store: false)
    assert(model.connectedUsername == "Bob" && model.config.username == "Bob" && !model.loginRequired)

    let relaunched = WidgetModel(makeTransport: makeTransport)
    let offline = SavedConnection(server: server, username: "bob", token: "fixture-offline", editingEnabled: false)
    await relaunched.restoreConnection { offline }
    assert(relaunched.canRetryConnection && relaunched.connectedUsername == nil)
    await relaunched.restoreConnection { bob }
    assert(!relaunched.canRetryConnection && relaunched.connectedUsername == "Bob" && !relaunched.loginRequired)
    for _ in 0..<100 where relaunched.loading {
        try await Task.sleep(nanoseconds: 20_000_000)
    }
    assert(relaunched.error?.text.contains("HTTP 503") == true && !relaunched.loginRequired,
           "A saved account must survive an issues API failure and show the issue error")
    relaunched.setLanguage(.english)
    assert(WidgetModel().language == .english, "The selected language must survive relaunch")
    assert(tr("Выйти из аккаунта") == "Sign out")
    assert(relaunched.error?.text == "Open issues · GitLab returned HTTP 503.",
           "Messages already visible in the widget must follow a language change")
    assert(ConnectionError.differentAccount("Bob").localizedDescription.contains("@Bob"))
    assert(relaunched.connectedUsername == "Bob", "Changing language must preserve the session")
    relaunched.setLanguage(.russian)
    assert(tr("Выйти из аккаунта") == "Выйти из аккаунта")
    assert(relaunched.error?.text.hasPrefix("Открытые задачи ·") == true)

    assert(relaunched.canDisconnect)
    do {
        try relaunched.disconnect { throw ConnectionError.keychain(errSecAuthFailed) }
        fatalError("A Keychain error must prevent sign-out")
    } catch ConnectionError.keychain(errSecAuthFailed) {}
    assert(relaunched.connectedUsername == "Bob")
    var removedConnection = false
    try relaunched.disconnect { removedConnection = true }
    assert(removedConnection && relaunched.loginRequired && !relaunched.canDisconnect)
    assert(relaunched.connectedUsername == nil && relaunched.issues.isEmpty && relaunched.closedIssues.isEmpty)
    assert(relaunched.config.username.isEmpty && relaunched.config.baseURL.absoluteString == server)

    let expired = WidgetModel(makeTransport: makeTransport)
    await expired.restoreConnection {
        SavedConnection(server: server, username: "bob", token: "fixture-expired", editingEnabled: false)
    }
    assert(expired.loginRequired && !expired.canRetryConnection && expired.connectedUsername == nil)
}

@MainActor
func verifyMutationCompletion() async throws {
    let model = WidgetModel(makeTransport: {
        let settings = URLSessionConfiguration.ephemeral
        settings.protocolClasses = [MockProtocol.self]
        return URLSession(configuration: settings)
    })
    let lock = NSLock()
    var posts = 0
    var checks = 0
    var title = "New issue"
    var deleted = false
    func issueJSON(assigned: Bool) -> String {
        let assignees = assigned ? #"[{"id":42,"username":"fixture"}]"# : "[]"
        return #"{"id":303,"iid":17,"project_id":9,"title":"\#(title)","web_url":"https://gitlab.example.com/team/front/-/issues/17","labels":[],"state":"opened","assignees":\#(assignees)}"#
    }
    MockProtocol.handler = { request in
        lock.lock()
        defer { lock.unlock() }
        let url = request.url!
        switch (request.httpMethod, url.lastPathComponent) {
        case ("GET", "user"): return (200, #"{"id":42,"username":"fixture"}"#)
        case ("GET", "issues"):
            let open = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains(URLQueryItem(name: "state", value: "opened")) == true
            return (200, checks >= 3 && open && !deleted ? "[" + issueJSON(assigned: true) + "]" : "[]")
        case ("POST", "issues"):
            posts += 1
            return (201, issueJSON(assigned: true))
        case ("GET", "17"):
            assert(url.absoluteString.hasSuffix("/api/v4/projects/team%2Ffront/issues/17"))
            checks += 1
            return checks == 1 ? (404, "{}") : (200, issueJSON(assigned: checks >= 3))
        case ("PUT", "17"):
            title = "Edited issue"
            return (200, issueJSON(assigned: true))
        case ("POST", "graphql"):
            let body = try JSONSerialization.jsonObject(with: requestBody(request)) as! [String: Any]
            if (body["query"] as? String)?.contains("mutation WidgetDeleteIssue") == true {
                deleted = true
                return (200, #"{"data":{"workItemDelete":{"errors":[]}}}"#)
            }
            return (200, #"{"data":{}}"#)
        default: return (200, "[]")
        }
    }
    func waitForRefresh() async throws {
        for _ in 0..<100 where model.loading { try await Task.sleep(nanoseconds: 20_000_000) }
        assert(!model.loading, "The refresh did not finish")
    }
    try await model.connect(server: "https://gitlab.example.com", username: "fixture", token: "fixture-write", editingEnabled: true, store: false)
    try await waitForRefresh()
    let original = IssueDetails(status: nil, statuses: [], labels: [], canEdit: true, canDelete: true, usesREST: true)
    let context = CreationContext(typeID: "", userID: "42", details: original)
    var pending: URL?
    var closed = 0
    let onSuccess = {
        assert(!model.loading && !model.saving, "Close the modal before triggering the refresh")
        closed += 1
    }
    func create() async throws {
        try await model.create(projectPath: "team/front", context: context, title: "New issue", description: "",
                               statusID: "", labelIDs: [], pendingURL: pending, onCreated: { pending = $0 }, onSuccess: onSuccess)
    }
    do { try await create(); fatalError("A missing server-side issue reported success") }
    catch GitLabError.creationUnconfirmed {}
    do { try await create(); fatalError("An unassigned issue reported success") }
    catch GitLabError.creationUnassigned {}
    assert(pending?.lastPathComponent == "17" && closed == 0 && !model.loading && model.issues.isEmpty)
    try await create()
    assert(lock.withLock { posts == 1 && checks == 3 }, "Retry must verify the same issue without another POST")
    assert(closed == 1 && model.loading)
    try await waitForRefresh()
    let issue = model.issues[0]
    assert(issue.title == "New issue")
    try await model.update(issue: issue, original: original, statusID: "", labelIDs: [], closed: false, title: "Edited issue", onSuccess: onSuccess)
    assert(closed == 2 && model.loading)
    try await waitForRefresh()
    assert(model.issues.map(\.title) == ["Edited issue"])
    try await model.delete(issue: issue, original: original, onSuccess: onSuccess)
    assert(closed == 3 && model.loading)
    try await waitForRefresh()
    assert(model.issues.isEmpty)
}
