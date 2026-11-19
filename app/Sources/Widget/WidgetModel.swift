import AppKit
import Combine

@MainActor
final class WidgetModel: ObservableObject {
    @Published private(set) var language = WidgetLanguage.current

    // MARK: - Issue list

    @Published var issues: [Issue] = []
    @Published var closedIssues: [Issue] = []
    @Published private(set) var closedIssuesError: WidgetMessage?
    @Published var updated: Date?
    @Published var error: WidgetMessage? = "Нужен вход в GitLab"
    @Published var loading = false
    @Published var saving = false
    @Published var loginRequired = true

    // MARK: - Deployment

    @Published var projects: [GitLabProject] = []
    @Published var branches: [GitLabBranch] = []
    @Published var selectedProjectPath = ""
    @Published var selectedBranch = ""
    @Published var deployment: GitLabDeployment?
    @Published var deploymentHead = ""
    @Published var deploymentLoading = false
    @Published var deploymentError: WidgetMessage?

    // MARK: - Connection

    @Published private(set) var config = Configuration.initial
    @Published private(set) var editingEnabled = false
    @Published private(set) var connecting = false
    @Published private(set) var canRetryConnection = false
    private(set) var currentUser: GitLabUser?
    var connectedUsername: String? { currentUser?.username }
    var canDisconnect: Bool { (!config.username.isEmpty || canRetryConnection) && !connecting && !saving }

    // MARK: - Widget placement

    @Published var layoutLocked = UserDefaults.standard.bool(forKey: "widgetLayoutLocked")
    @Published var fillsLeftSide = UserDefaults.standard.object(forKey: "widgetFullHeightOnLeft") as? Bool ?? true
    @Published var reservedBottom = UserDefaults.standard.double(forKey: "widgetReservedBottom")
    @Published var layoutNotice: WidgetMessage?

    // MARK: - Application actions

    var onLoginRequired: (() -> Void)?
    var onLogout: (() -> Void)?
    var onEdit: ((Issue) -> Void)?
    var onCreate: (() -> Void)?
    var onDelete: ((Issue) -> Void)?
    var onSettings: (() -> Void)?
    var onMoveWidget: (() -> Void)?
    var onAutocompleteVisibilityChange: ((Bool) -> Void)?

    // MARK: - Session and refresh tasks

    private var transport: GitLabTransport
    private let makeTransport: () -> URLSession
    private var token: String?
    private(set) var sessionID = UUID()
    private var refreshTask: Task<Void, Never>?
    private var timer: Timer?
    private var dayTimer: Timer?
    private var deploymentTimer: Timer?
    var projectTask: Task<Void, Never>?
    var branchTask: Task<Void, Never>?
    var deploymentTask: Task<Void, Never>?

    init(makeTransport: (() -> URLSession)? = nil) {
        let factory = makeTransport ?? { GitLabTransport.makeSession() }
        self.makeTransport = factory
        transport = GitLabTransport(factory())
        timer = Timer.scheduledTimer(withTimeInterval: max(60, config.refreshSeconds),
                                    repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.refresh() } }
        scheduleDayRefresh()
        deploymentTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshDeployment() }
        }
    }

    private func scheduleDayRefresh() {
        dayTimer = Timer.scheduledTimer(withTimeInterval: max(1, IssueDay.interval(on: Date()).end.timeIntervalSinceNow),
                                       repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.closedIssues = []
                self?.refresh()
                self?.scheduleDayRefresh()
            }
        }
    }

    func setLanguage(_ language: WidgetLanguage) {
        guard self.language != language else { return }
        UserDefaults.standard.set(language.rawValue, forKey: WidgetLanguage.preferenceKey)
        self.language = language
    }


    // MARK: - Connection lifecycle

    func restoreConnection(load: () throws -> SavedConnection? = ConnectionKeychain.load) async {
        guard loginRequired, !connecting, !saving else { return }
        do {
            guard let saved = try load() else {
                canRetryConnection = false
                error = "Нужен вход в GitLab"
                return
            }
            config = Configuration(baseURL: try Configuration.serverURL(saved.server), username: saved.username)
            try await connect(server: saved.server, username: saved.username, token: saved.token,
                              editingEnabled: saved.editingEnabled, store: false)
        } catch {
            guard !Task.isCancelled else { return }
            switch error {
            case let failure as GitLabReadFailure: canRetryConnection = !failure.needsLogin
            case ConnectionError.keychain: canRetryConnection = true
            default: canRetryConnection = false
            }
            self.error = WidgetMessage { WidgetModel.connectionMessage(error) }
        }
    }

    func connect(server: String, username: String, token: String, editingEnabled: Bool, store: Bool = true,
                 onConnected: () -> Void = {}) async throws {
        guard !connecting, !saving else { throw GitLabError.unavailable }
        let base = try Configuration.serverURL(server)
        let nick = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nick.isEmpty, !secret.isEmpty, !secret.contains(where: \.isWhitespace) else { throw ConnectionError.missingFields }
        connecting = true
        defer { connecting = false }

        let candidate = Configuration(baseURL: base, username: nick.hasPrefix("@") ? String(nick.dropFirst()) : nick)
        let candidateTransport = GitLabTransport(makeTransport())
        let user = try await GitLabREST(config: candidate, transport: candidateTransport, token: secret)
            .verifyUser(expected: candidate.username, checkIssues: store)
        try Task.checkCancellation()
        guard !saving else { throw GitLabError.unavailable }
        if store {
            try ConnectionKeychain.save(SavedConnection(server: base.absoluteString, username: user.username,
                                                       token: secret, editingEnabled: editingEnabled))
        }
        discardSession(replacement: candidateTransport)
        config = Configuration(baseURL: base, username: user.username)
        currentUser = user
        self.token = secret
        self.editingEnabled = editingEnabled
        selectedProjectPath = UserDefaults.standard.string(forKey: preferenceKey("project")) ?? ""
        selectedBranch = UserDefaults.standard.string(forKey: preferenceKey("branch.\(selectedProjectPath)")) ?? ""
        loginRequired = false
        error = nil
        onConnected()
        refresh()
    }

    static func connectionMessage(_ error: Error) -> String {
        if let failure = error as? GitLabReadFailure { return failure.localizedDescription }
        if (error as? URLError)?.code == .userAuthenticationRequired {
            return tr("GitLab не принял токен. Проверь, действителен ли он и не истёк ли срок.")
        }
        if let known = error as? ConnectionError { return known.localizedDescription }
        if let known = error as? GitLabError {
            return known == .forbidden ? tr("Токену нужен доступ к профилю и задачам по всему GitLab. Проверь права токена и настройки сервера.") : known.localizedDescription
        }
        return tr("Не удалось подключиться. Проверь HTTPS-адрес GitLab, сеть и VPN.")
    }

    var graphQL: GitLabGraphQL { GitLabGraphQL(config: config, transport: transport, token: token) }
    var rest: GitLabREST { GitLabREST(config: config, transport: transport, token: token) }

    func requireLogin(message: WidgetMessage = "Токен недействителен или истёк. Подключись заново.") {
        discardSession()
        error = message
    }

    private func discardSession(replacement: GitLabTransport? = nil) {
        sessionID = UUID()
        refreshTask?.cancel()
        refreshTask = nil
        transport = replacement ?? GitLabTransport(makeTransport())
        loading = false
        saving = false
        clearProjectData()
        selectedProjectPath = ""
        selectedBranch = ""
        issues = []
        closedIssues = []
        closedIssuesError = nil
        token = nil
        currentUser = nil
        canRetryConnection = false
        editingEnabled = false
        updated = nil
        loginRequired = true
    }


    func disconnect(remove: () throws -> Void = ConnectionKeychain.remove) throws {
        guard !connecting, !saving else { throw GitLabError.unavailable }
        try remove()
        discardSession()
        config = Configuration(baseURL: config.baseURL, username: "")
        error = "Нужен вход в GitLab"
    }

    func open(_ url: URL) {
        guard config.allowsAPIURL(url) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Issue refresh

    func refresh() {
        guard !loading, !saving else { return }
        if loginRequired {
            if canRetryConnection && !connecting { Task { await restoreConnection() } }
            return
        }
        loading = true
        let identity = sessionID
        let api = rest
        let gql = graphQL
        let config = config
        let now = Date()
        refreshTask = Task {
            defer { if identity == sessionID { loading = false; refreshTask = nil } }
            do {
                let opened = try await api.assignedIssues().filter { config.allowsAPIURL($0.url) }
                try Task.checkCancellation()
                guard identity == sessionID else { return }
                issues = opened.filter { $0.state != "closed" }
                updated = Date()
                error = nil

                var closed: [Issue]?
                do {
                    let items = IssueDay.closedToday(try await api.assignedIssues(closedOn: now), on: now)
                        .filter { config.allowsAPIURL($0.url) }
                    try Task.checkCancellation()
                    guard identity == sessionID else { return }
                    closed = items
                    closedIssues = items
                    closedIssuesError = nil
                } catch {
                    try Task.checkCancellation()
                    guard identity == sessionID else { return }
                    closedIssuesError = WidgetMessage { error.localizedDescription }
                }
                let refreshed = try await loadIssueDetails(opened + (closed ?? []), using: api, graphQL: gql)
                try Task.checkCancellation()
                guard identity == sessionID else { return }
                issues = refreshed.filter { $0.state != "closed" }
                if closed != nil { closedIssues = IssueDay.closedToday(refreshed, on: Date()) }
                updated = Date()
                error = nil
                if projects.isEmpty { refreshProjects() }
                else { refreshDeployment() }
            } catch {
                guard !Task.isCancelled, identity == sessionID else { return }
                if let failure = error as? GitLabReadFailure {
                    let message = WidgetMessage { failure.localizedDescription }
                    if failure.needsLogin { requireLogin(message: message) }
                    else { self.error = message }
                } else {
                    self.error = "Не удалось обновить GitLab"
                }
            }
        }
    }

    private func loadIssueDetails(_ issues: [Issue], using api: GitLabREST, graphQL: GitLabGraphQL) async throws -> [Issue] {
        let config = api.config
        var refreshed = issues
        if !config.baseURL.path.isEmpty {
            for index in refreshed.indices {
                let path = String(refreshed[index].url.path.dropFirst(config.baseURL.path.count))
                refreshed[index].relativeProjectPath = path.components(separatedBy: "/-/")[0]
                    .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            }
        }
        // Limit per-issue lookups so a large cross-project issue list doesn't flood the server.
        for start in stride(from: 0, to: refreshed.count, by: 8) {
            try Task.checkCancellation()
            await withTaskGroup(of: (Int, [IssueLink]?, IssueDetails?).self) { group in
                for index in start..<min(start + 8, refreshed.count) {
                    let issue = refreshed[index]
                    group.addTask {
                        let links: [IssueLink]?
                        if let path = try? issue.issueAPIPath() {
                            links = try? await api.pages(from: config.apiURL(path + "/links"))
                        } else { links = nil }
                        let details = try? await graphQL.details(for: issue)
                        return (index, links, details)
                    }
                }
                for await (index, links, details) in group {
                    refreshed[index].links = links?.filter { config.allowsAPIURL($0.url) }
                    refreshed[index].details = details
                }
            }
        }
        return refreshed
    }
}
