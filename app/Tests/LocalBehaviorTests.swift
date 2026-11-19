import AppKit
import SwiftUI

func verifyLocalBehavior(configuration: Configuration, selfManaged: Configuration) throws {
    let apiIssue = ##"{"title":"API task","web_url":"https://gitlab.example.com/team/front/-/issues/79","labels":[],"description":"Not needed by the widget"}"##.data(using: .utf8)!
    var issue = try JSONDecoder().decode(Issue.self, from: apiIssue)
    assert(issue.links == nil)
    let payload = #"[{"title":"Открытый блокер","web_url":"https://gitlab.example.com/team/back/-/work_items/40","state":"opened","link_type":"is_blocked_by"},{"title":"Закрытый блокер","web_url":"https://gitlab.example.com/team/back/-/issues/41","state":"closed","link_type":"is_blocked_by"},{"title":"Зависимая задача","web_url":"https://gitlab.example.com/team/front/-/issues/51","state":"opened","link_type":"blocks"},{"title":"Просто связь","web_url":"https://gitlab.example.com/team/front/-/issues/52","state":"opened","link_type":"relates_to"}]"#.data(using: .utf8)!
    issue.links = try JSONDecoder().decode([IssueLink].self, from: payload)
    assert(issue.blockers.map(\.number) == ["#40"], "Only open is_blocked_by links block the current task")
    assert(issue.blockedIssues.map(\.number) == ["#51"], "blocks links have the opposite direction")
    assert(issue.blockers[0].title == "Открытый блокер")
    assert(issue.blockers[0].project == "back")
    let issuePath = try issue.issueAPIPath()
    assert(issuePath == "projects/team%2Ffront/issues/79")
    issue.links = [IssueLink(title: "Resolved", url: issue.url, state: "closed", linkType: "is_blocked_by")]
    assert(issue.blockers.isEmpty, "Closing the blocker must clear the blocked indicator")
    issue.links = []
    assert(issue.links != nil && issue.blockers.isEmpty && issue.blockedIssues.isEmpty)
    let toDo = WorkStatus(id: "todo", name: "To do", color: "#ffffff", category: "to_do")
    let progressing = WorkStatus(id: "progress", name: "In progress", color: "#0000ff", category: "in_progress")
    var ordinary = issue
    ordinary.details = IssueDetails(status: toDo, statuses: [], labels: [], canEdit: true)
    var unassignedStatus = ordinary
    unassignedStatus.details = IssueDetails(status: nil, statuses: [], labels: [], canEdit: true)
    var inProgress = ordinary
    inProgress.details = IssueDetails(status: progressing, statuses: [], labels: [], canEdit: true)
    var blockedProgress = inProgress
    blockedProgress.links = [IssueLink(title: "Blocking", url: issue.url, state: "opened", linkType: "is_blocked_by")]
    var blockedToDo = ordinary
    blockedToDo.links = blockedProgress.links
    var closedTask = try JSONDecoder().decode(Issue.self, from: Data(##"{"title":"Closed","web_url":"https://gitlab.example.com/team/front/-/issues/80","labels":[],"state":"closed"}"##.utf8))
    closedTask.details = ordinary.details
    closedTask.links = blockedProgress.links
    let actualServerCase = IssueCounts(issues: [blockedToDo, blockedProgress, blockedProgress, inProgress, closedTask])
    assert(actualServerCase.toDo == 1 && actualServerCase.inProgress == 3 && actualServerCase.blocked == 3, "Regression: real GitLab lowercase categories and independent blocker counts must yield 1 | 3 | 3, not 0 | 0 | 3")
    var uncheckedStatus = ordinary
    uncheckedStatus.details = nil
    var uncheckedLinks = inProgress
    uncheckedLinks.links = nil
    let partial = IssueCounts(issues: [unassignedStatus, uncheckedStatus, uncheckedLinks])
    assert(partial.toDo == 0 && partial.inProgress == 1 && partial.unchecked == 2, "Missing status is not To Do; missing links must not hide a known workflow status")
    var triage = ordinary
    triage.details = IssueDetails(status: WorkStatus(id: "triage", name: "Triage", color: "#fff", category: "TRIAGE"), statuses: [], labels: [], canEdit: true)
    assert(IssueCounts(issues: [triage]).toDo == 0, "White must mean strictly To Do")
    blockedProgress.links = [IssueLink(title: "Resolved", url: issue.url, state: "closed", linkType: "is_blocked_by")]
    let resolvedCounts = IssueCounts(issues: [blockedProgress])
    assert(resolvedCounts.inProgress == 1 && resolvedCounts.blocked == 0)
    assert(WorkStatus(id: "done", name: "Done", color: "#fff", category: "done").closesIssue)
    assert(WorkStatus(id: "cancel", name: "Canceled", color: "#fff", category: "CANCELED").closesIssue)
    assert(!progressing.closesIssue)
    let visible = CGRect(x: -1440, y: 20, width: 1440, height: 880)
    let minSize = NSSize(width: 300, height: 320)
    let maxSize = NSSize(width: 800, height: 1200)
    let geometry = WidgetGeometry(width: 400, height: 500, left: 30, top: 40, locked: false)
    assert(WidgetGeometry.fittedFrame(geometry, in: visible, minimum: minSize, maximum: maxSize) == CGRect(x: -1410, y: 360, width: 400, height: 500), "Coordinates are relative to the current screen's top-left, including secondary screens")
    let oversized = WidgetGeometry(width: 9999, height: 9999, left: -20, top: 9999, locked: true)
    assert(WidgetGeometry.fittedFrame(oversized, in: visible, minimum: minSize, maximum: maxSize) == CGRect(x: -1440, y: 20, width: 800, height: 880))
    let tiny = WidgetGeometry(width: -10, height: 0, left: 9999, top: 9999, locked: false)
    assert(WidgetGeometry.fittedFrame(tiny, in: visible, minimum: minSize, maximum: maxSize) == CGRect(x: -300, y: 20, width: 300, height: 320))
    let invalid = WidgetGeometry(width: .nan, height: .infinity, left: .nan, top: .infinity, locked: false)
    let safeFrame = WidgetGeometry.fittedFrame(invalid, in: visible, minimum: minSize, maximum: maxSize)
    assert(visible.contains(safeFrame) && safeFrame.width >= minSize.width && safeFrame.height >= minSize.height)
    let fullHeight = WidgetGeometry.fullHeightFrame(in: visible, width: 344)
    assert(fullHeight == CGRect(x: -1430, y: 30, width: 344, height: 860), "Use the complete work area with ten-point margins")
    let nativeWeather = CGRect(x: -1430, y: 200, width: 344, height: 160)
    let nativeCalendar = CGRect(x: -1430, y: 30, width: 344, height: 160)
    let aboveWidgets = WidgetGeometry.availableFrame(in: visible, width: 344, widgets: [nativeCalendar, nativeWeather])
    assert(aboveWidgets == CGRect(x: -1430, y: 376, width: 344, height: 514), "Fit above both widgets with a 16-point gap")
    let rightWidget = nativeWeather.offsetBy(dx: 400, dy: 0)
    assert(WidgetGeometry.availableFrame(in: visible, width: 344, widgets: [rightWidget]) == fullHeight)
    assert(WidgetGeometry.availableFrame(in: visible, width: 344, widgets: nil) == nil, "Unavailable positions must not be treated as a free screen")
    assert(WidgetGeometry.availableFrame(in: visible, width: 344, widgets: nil, reservedBottom: 346) == aboveWidgets)
    assert(WidgetGeometry.availableFrame(in: visible, width: 344, widgets: [nativeWeather], reservedBottom: 346) == aboveWidgets)
    assert(WidgetGeometry.availableFrame(in: visible, width: 344, widgets: [fullHeight]) == nil)
    assert(WidgetGeometry.availableFrame(in: visible, width: 344, widgets: nil, reservedBottom: 700) == nil)
    let topWidget = CGRect(x: -1430, y: 720, width: 344, height: 170)
    assert(WidgetGeometry.availableFrame(in: visible, width: 344, widgets: [topWidget])?.maxY == 704)
    let previousSmallWindow = WidgetGeometry(width: 344, height: 440, left: 100, top: 80, locked: true)
    let expanded = WidgetGeometry.fullHeightFrame(in: visible, width: previousSmallWindow.width)
    assert(expanded.height > previousSmallWindow.height && expanded.minX == visible.minX + 10, "A restored short window must expand and move left without querying other windows")
    let belowPrimary = CGRect(x: 1920, y: -543, width: 1920, height: 1049)
    assert(WidgetGeometry.fullHeightFrame(in: belowPrimary, width: 344) == CGRect(x: 1930, y: -533, width: 344, height: 1029), "Secondary displays below the primary keep their own origin")
    let tallScreen = CGRect(x: 0, y: 40, width: 1920, height: 1600)
    assert(WidgetGeometry.fullHeightFrame(in: tallScreen, width: 400).height == 1580, "Full-height mode must not inherit the former 1200-point height limit")
    let resizedScreen = CGRect(x: -1440, y: 20, width: 1440, height: 700)
    assert(WidgetGeometry.fullHeightFrame(in: resizedScreen, width: 344).height == 680, "Recompute the height after the work area changes")
    print("Passed: reserved space for desktop widgets, unknown and crowded layouts, full height on free screens, and multiple display origins.")
    print("Passed: real lowercase categories, strict To Do / In progress, independent blockers (1 | 3 | 3), partial data, closed issues, final statuses and bounded geometry on secondary screens.")
    let choices = [AutocompleteOption(id: "front", title: "Frontend", detail: "team/football"), AutocompleteOption(id: "back", title: "Backend", detail: "team/api"), AutocompleteOption(id: "ru", title: "Проект", detail: "группа/сервис"), AutocompleteOption(id: "", title: "По умолчанию")]
    assert(AutocompleteOption.filtered(choices, query: "  FRONT ").map(\.id) == ["front"])
    assert(AutocompleteOption.filtered(choices, query: "football").map(\.id) == ["front"], "Projects are searchable by full path as well as name")
    assert(AutocompleteOption.filtered(choices, query: "ПРОЕКТ").map(\.id) == ["ru"])
    assert(AutocompleteOption.filtered(choices, query: " \n ") == choices)
    assert(AutocompleteOption.filtered(choices, query: "missing").isEmpty)
    assert(AutocompleteOption.filtered(choices, query: "умолчанию").first?.id == "", "The default status remains a valid selectable value")
    let labelOptions = [
        AutocompleteOption(id: "old", title: "status::To Do", scope: "status"),
        AutocompleteOption(id: "new", title: "status::Done", scope: "status"),
        AutocompleteOption(id: "bug", title: "Баг")
    ]
    let matchedLabel = AutocompleteOption.filtered(labelOptions, query: " done ")[0]
    let labelSelection = AutocompleteOption.toggling(matchedLabel, in: ["old", "bug"], options: labelOptions)
    assert(labelSelection == ["new", "bug"], "Selecting a scoped label replaces only the previous label of that scope")
    assert(AutocompleteOption.toggling(matchedLabel, in: labelSelection, options: labelOptions) == ["bug"])
    assert(AutocompleteOption.toggling(labelOptions[2], in: ["new"], options: labelOptions) == ["new", "bug"])
    print("Passed: autocomplete filtering by name/path, Cyrillic, whitespace, default/empty matches.")
    let query = URLComponents(url: configuration.issuesURL, resolvingAgainstBaseURL: false)!.queryItems!
    assert(query.contains(URLQueryItem(name: "scope", value: "assigned_to_me")))
    assert(query.contains(URLQueryItem(name: "state", value: "opened")))
    assert(!query.contains(where: { $0.name == "assignee_username" || $0.name == "project_id" }))
    assert(configuration.issuesURL.path == "/api/v4/issues")
    assert(configuration.allowsAPIURL(configuration.issuesURL))
    assert(!configuration.allowsAPIURL(URL(string: "http://gitlab.example.com/api/v4/issues")!))
    assert(!configuration.allowsAPIURL(URL(string: "https://gitlab.example.com.evil.example/api/v4/issues")!))
    assert(!configuration.allowsAPIURL(URL(string: "https://gitlab.example.com:444/api/v4/issues")!))
    assert(selfManaged.issuesURL.absoluteString.hasPrefix("https://gitlab.example.org:8443/forge/api/v4/issues?"))
    assert(selfManaged.endpoint("api/graphql").path == "/forge/api/graphql")
    assert(!selfManaged.allowsAPIURL(URL(string: "https://gitlab.example.org:8443/other/api/v4/issues")!))
    for invalid in ["http://gitlab.example.com", "https://name:password@gitlab.example.com", "https://gitlab.example.com/?token=dummy",
                    "https://gitlab.example.com/#x", "https://gitlab.example.com/../admin", "https://gitlab.example.com/%2e%2e/admin"] {
        do { _ = try Configuration.serverURL(invalid); fatalError("Invalid base URL was accepted") }
        catch ConnectionError.invalidServer {}
    }
    MainActor.assumeIsolated {
        let model = WidgetModel()
        assert(model.issues.isEmpty && model.loginRequired && !model.editingEnabled)
        let backdrop = glassHostingView(EmptyView())
        if #available(macOS 26.0, *), let glassClass = NSClassFromString("NSGlassEffectView") as? NSView.Type {
            assert(backdrop.isKind(of: glassClass), "Supported systems must use native Liquid Glass")
            assert((backdrop.value(forKey: "style") as? NSNumber)?.intValue == 0,
                   "Use the standard Liquid Glass material for an entire panel")
            assert((backdrop.value(forKey: "effectIsInteractive") as? NSNumber)?.boolValue == false,
                   "The panel backdrop must not respond to clicks like a glass control")
        } else {
            let effect = backdrop as? NSVisualEffectView
            assert(effect?.state == .active && effect?.blendingMode == .behindWindow,
                   "The fallback backdrop must keep blurring content behind the window as focus changes")
        }
        let transport = GitLabTransport.makeSession()
        assert(transport.configuration.urlCache == nil)
        assert(transport.configuration.urlCredentialStorage == nil)
        assert(transport.configuration.httpCookieStorage == nil && !transport.configuration.httpShouldSetCookies)
        let redirectGuard = transport.delegate as! RedirectGuard
        let task = transport.dataTask(with: configuration.issuesURL)
        let redirect = HTTPURLResponse(url: configuration.issuesURL, statusCode: 302, httpVersion: nil, headerFields: [:])!
        for destination in [URL(string: "https://evil.example/")!, configuration.issuesURL] {
            var result: URLRequest? = URLRequest(url: configuration.issuesURL)
            redirectGuard.urlSession(transport, task: task, willPerformHTTPRedirection: redirect,
                                     newRequest: URLRequest(url: destination)) { result = $0 }
            assert(result == nil, "PAT transport must never follow redirects")
        }
        task.cancel()
        transport.invalidateAndCancel()
    }
    let moscow = TimeZone(identifier: "Europe/Moscow")!
    let now = IssueDay.parse("2026-11-17T10:00:00Z")!
    assert(IssueDay.interval(on: now, timeZone: moscow).start == IssueDay.parse("2026-11-16T21:00:00Z")!)
    assert(IssueDay.interval(on: now, timeZone: moscow).end == IssueDay.parse("2026-11-17T21:00:00Z")!)
    let closedQuery = URLComponents(url: configuration.closedIssuesURL(on: now, timeZone: moscow), resolvingAgainstBaseURL: false)!.queryItems!
    assert(closedQuery.contains(URLQueryItem(name: "state", value: "closed")))
    assert(closedQuery.contains(URLQueryItem(name: "updated_after", value: "2026-11-16T21:00:00Z")))
    let dateFixtures = try [datedIssue(1, "2026-11-16T20:59:59.999Z"), datedIssue(2, "2026-11-16T21:00:00Z"), datedIssue(3, "2026-11-17T20:59:59.999Z"), datedIssue(4, "2026-11-17T21:00:00Z"), datedIssue(5, nil), datedIssue(6, "2026-11-17T10:00:00Z", state: "opened")]
    assert(IssueDay.closedToday(dateFixtures, on: now, timeZone: moscow).map(\.globalID) == [3, 2], "Use closed_at, Moscow midnight and half-open day bounds, not updated_at")
    assert(IssueDay.closedToday([dateFixtures[1]], on: IssueDay.parse("2026-11-17T21:00:00Z")!, timeZone: moscow).isEmpty, "Yesterday's tasks disappear at Moscow midnight")
}
