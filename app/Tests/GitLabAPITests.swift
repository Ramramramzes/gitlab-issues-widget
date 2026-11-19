import Foundation

func verifyGitLabAPI(configuration: Configuration, selfManaged: Configuration) async throws {
    let settings = URLSessionConfiguration.ephemeral
    settings.protocolClasses = [MockProtocol.self]
    let transport = GitLabTransport(URLSession(configuration: settings))
    let api = GitLabGraphQL(config: configuration, transport: transport, token: "test-only-token")
    let aliceAPI = GitLabREST(config: configuration, transport: transport, token: "fixture-alice")
    let bobAPI = GitLabREST(config: selfManaged, transport: transport, token: "fixture-bob")
    MockProtocol.handler = { request in
        let token = request.value(forHTTPHeaderField: "PRIVATE-TOKEN")
        let alice = request.url?.host == "gitlab.example.com"
        assert(token == (alice ? "fixture-alice" : "fixture-bob"))
        assert(request.value(forHTTPHeaderField: "Cookie") == nil)
        let prefix = alice ? "/api/v4" : "/forge/api/v4"
        if request.url?.path == prefix + "/user" {
            return (200, alice ? #"{"id":1,"username":"Alice"}"# : #"{"id":2,"username":"Bob"}"#)
        }
        assert(request.url?.path == prefix + "/issues")
        let params = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems ?? []
        assert(params.contains(URLQueryItem(name: "scope", value: "assigned_to_me")))
        assert(!params.contains { $0.name == "assignee_username" || $0.name == "project_id" })
        if params.contains(URLQueryItem(name: "per_page", value: "1")) { return (200, "[]") }
        return (200, #"[{"id":2,"iid":7,"project_id":11,"title":"First project","web_url":"https://gitlab.example.org:8443/forge/team/one/-/issues/7","labels":[]},{"id":3,"iid":7,"project_id":22,"title":"Second project","web_url":"https://gitlab.example.org:8443/forge/team/two/-/issues/7","labels":[]}]"#)
    }
    let alice = try await aliceAPI.verifyUser(expected: "alice")
    let bob = try await bobAPI.verifyUser(expected: "bob")
    assert(alice.id == 1 && alice.username == "Alice" && bob.id == 2 && bob.username == "Bob")
    do { _ = try await bobAPI.verifyUser(expected: "alice"); fatalError("Wrong-account token accepted") }
    catch ConnectionError.differentAccount("Bob") {}
    let crossProject: [Issue] = try await bobAPI.pages(from: selfManaged.issuesURL)
    assert(crossProject.compactMap(\.projectID) == [11, 22])
    let bobPath = try crossProject[1].issueAPIPath()
    assert(bobPath == "projects/22/issues/7")
    MockProtocol.handler = { _ in (401, "{}") }
    do { _ = try await bobAPI.verifyUser(expected: "bob"); fatalError("Expired token accepted") }
    catch let failure as GitLabReadFailure {
        assert(failure.resource == .profile && failure.needsLogin && failure.localizedDescription.contains("HTTP 401"))
    }
    MockProtocol.handler = { request in request.url?.lastPathComponent == "user" ? (200, #"{"id":2,"username":"Bob"}"#) : (403, "{}") }
    do { _ = try await bobAPI.verifyUser(expected: "bob"); fatalError("Token without global issues access accepted") }
    catch let failure as GitLabReadFailure {
        assert(failure.resource == .openIssues && !failure.needsLogin && failure.localizedDescription.contains("HTTP 403"))
    }
    MockProtocol.handler = { _ in (302, "") }
    do { _ = try await bobAPI.verifyUser(expected: "bob"); fatalError("Redirect treated as GitLab authentication") }
    catch let failure as GitLabReadFailure {
        assert(failure.resource == .profile && (failure.cause as? GitLabError) == .gatewayLogin)
    }
    MockProtocol.headers = ["Content-Type": "text/plain"]
    MockProtocol.handler = { request in
        if request.url?.lastPathComponent == "user" { return (200, #"{"id":2,"username":"Bob"}"#) }
        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems
        if query?.contains(URLQueryItem(name: "state", value: "closed")) == true { return (404, "{}") }
        return (200, #"[{"id":2,"iid":7,"project_id":11,"title":"Assigned issue","web_url":"https://gitlab.example.org:8443/forge/team/one/-/issues/7","labels":[],"state":"opened"}]"#)
    }
    let proxied = try await bobAPI.verifyUser(expected: "Bob")
    assert(proxied.id == 2, "A proxy may return valid JSON as text/plain")
    let openIssues = try await bobAPI.assignedIssues()
    assert(openIssues.map(\.title) == ["Assigned issue"], "Open issue reads work without write scope")
    do { _ = try await bobAPI.assignedIssues(closedOn: Date()); fatalError("Failed closed issue request accepted") }
    catch let failure as GitLabReadFailure {
        assert(failure.resource == .closedIssues && failure.localizedDescription.contains("HTTP 404"))
    }
    MockProtocol.headers = [:]
    MockProtocol.handler = { request in
        assert(request.httpMethod == "GET" && request.url?.path == "/api/v4/personal_access_tokens/self")
        return (200, #"{"scopes":["read_api","read_repository"]}"#)
    }
    do { try await aliceAPI.checkWriteScope(); fatalError("Read-only PAT accepted for editing") }
    catch GitLabError.readOnlyToken {}
    MockProtocol.handler = { _ in (200, #"{"scopes":["read_api","api"]}"#) }
    try await aliceAPI.checkWriteScope()
    MockProtocol.handler = { _ in (200, #"{"scopes":["read_api"],"granular_scopes":[{"access":"project","permissions":["work_item_update"]}]}"#) }
    try await aliceAPI.checkWriteScope()
    MockProtocol.handler = { _ in (404, "{}") }
    try await aliceAPI.checkWriteScope()
    let writeURL = configuration.apiURL("projects/22/issues/7")
    MockProtocol.handler = { _ in (403, #"{"error":"insufficient_scope","scope":"api"}"#) }
    do { _ = try await aliceAPI.response(from: writeURL, method: "PUT", body: [:]); fatalError("Missing write scope accepted") }
    catch GitLabError.insufficientScope {}
    MockProtocol.handler = { _ in (422, #"{"message":{"labels":["are unavailable"]},"error_description":"Invalid fixture-alice"}"#) }
    do { _ = try await aliceAPI.response(from: writeURL, method: "PUT", body: [:]); fatalError("REST validation failure accepted") }
    catch GitLabError.serverRejection(status: 422, reason: "Invalid [скрыто] · labels are unavailable") {}
    print("Passed: read-only, writable and fine-grained token scopes, compatible fallback, and redacted REST validation errors.")
    print("Passed: verified PAT ownership for two hosts/accounts, token isolation, instance-wide issue requests, expired/PAT scope and proxy failures.")
    let fixture = try datedIssue(2195, nil, state: "opened")
    var sent: [String: Any] = [:]
    MockProtocol.handler = { request in
        assert(request.httpMethod == "POST" && request.url?.path == "/api/graphql")
        assert(request.value(forHTTPHeaderField: "PRIVATE-TOKEN") == "test-only-token")
        assert(request.value(forHTTPHeaderField: "Cache-Control") == "no-store")
        sent = try JSONSerialization.jsonObject(with: try requestBody(request)) as! [String: Any]
        return (200, ##"{"data":{"workItem":{"title":"Original title","userPermissions":{"updateWorkItem":true,"deleteWorkItem":true},"workItemType":{"widgetDefinitions":[{}, {"allowedStatuses":[{"id":"status-open","name":"To do","color":"#888888","category":"to_do"},{"id":"status-done","name":"Done","color":"#00ff00","category":"done"}]}]},"widgets":[{"description":"Original **Markdown**"},{"status":{"id":"status-open","name":"To do","color":"#888888","category":"to_do"}},{"labels":{"nodes":[{"id":"label-old","title":"status::To do","color":"#888888"}],"pageInfo":{"hasNextPage":false,"endCursor":null}}}]}}}"##)
    }
    let details = try await api.details(for: fixture)
    assert(details.status?.name == "To do" && details.statuses.count == 2 && details.canEdit)
    assert(details.labels.first?.title == "status::To do", "Native status and status labels remain separate")
    assert((sent["variables"] as! [String: String])["id"] == "gid://gitlab/WorkItem/2195")
    let input = try GitLabGraphQL.updateInput(issue: fixture, original: details, statusID: "status-done", labelIDs: ["label-new"], closed: false)
    assert((input["statusWidget"] as! [String: String]) == ["status": "status-done"])
    let delta = input["labelsWidget"] as! [String: [String]]
    assert(delta["addLabelIds"] == ["label-new"] && delta["removeLabelIds"] == ["label-old"], "Send deltas without replacing concurrently added labels")
    assert(input["stateEvent"] == nil, "Native status controls state; do not send a conflicting state change")
    let labelOnly = try GitLabGraphQL.updateInput(issue: fixture, original: details, statusID: "status-open", labelIDs: [], closed: false)
    assert(labelOnly["statusWidget"] == nil)
    do { _ = try GitLabGraphQL.updateInput(issue: fixture, original: details, statusID: "unknown-status", labelIDs: [], closed: false); fatalError("Unknown status accepted") } catch GitLabError.invalidStatus {}
    let readOnly = IssueDetails(status: details.status, statuses: details.statuses, labels: details.labels, canEdit: false)
    do { _ = try GitLabGraphQL.updateInput(issue: fixture, original: readOnly, statusID: "status-done", labelIDs: [], closed: false); fatalError("Read-only issue accepted") } catch GitLabError.forbidden {}
    let fallback = IssueDetails(status: nil, statuses: [], labels: [], canEdit: true)
    let stateInput = try GitLabGraphQL.updateInput(issue: fixture, original: fallback, statusID: "", labelIDs: [], closed: true)
    assert(stateInput["stateEvent"] as? String == "CLOSE")
    var pages = 0
    MockProtocol.handler = { request in
        let body = try JSONSerialization.jsonObject(with: try requestBody(request)) as! [String: Any]
        let variables = body["variables"] as! [String: Any]
        pages += 1
        if pages == 1 {
            assert(variables["after"] is NSNull)
            return (200, ##"{"data":{"project":{"labels":{"nodes":[{"id":"l1","title":"one","color":"#ffffff"}],"pageInfo":{"hasNextPage":true,"endCursor":"page2"}}}}}"##)
        }
        assert(variables["after"] as? String == "page2")
        return (200, ##"{"data":{"project":{"labels":{"nodes":[{"id":"l2","title":"two","color":"#000000"}],"pageInfo":{"hasNextPage":false,"endCursor":"end"}}}}}"##)
    }
    let allLabels = try await api.labels(for: fixture)
    assert(allLabels.map(\.id) == ["l1", "l2"] && pages == 2)
    MockProtocol.handler = { request in
        let body = try JSONSerialization.jsonObject(with: try requestBody(request)) as! [String: Any]
        assert((body["query"] as! String).contains("mutation WidgetUpdateIssue"))
        assert(((body["variables"] as! [String: Any])["input"] as! [String: Any])["labelsWidget"] != nil)
        return (200, ##"{"data":{"workItemUpdate":{"errors":[],"workItem":{"id":"gid://gitlab/WorkItem/2195"}}}}"##)
    }
    try await api.update(issue: fixture, original: details, statusID: "status-done", labelIDs: ["label-new"], closed: false)
    for response in [##"{"errors":[{"message":"Permission denied"}],"data":null}"##, ##"{"data":{"workItemUpdate":{"errors":["Permission denied"],"workItem":null}}}"##] {
        MockProtocol.handler = { _ in (200, response) }
        do { try await api.update(issue: fixture, original: details, statusID: "status-done", labelIDs: [], closed: false); fatalError("Mutation failure reported as success") } catch GitLabError.serverRejection(status: nil, reason: "Permission denied") {}
    }
    MockProtocol.handler = { _ in (401, "{}") }
    do { _ = try await api.details(for: fixture); fatalError("Expired session accepted") } catch let error as URLError { assert(error.code == .userAuthenticationRequired) }
    MockProtocol.handler = { _ in fatalError("Request must not be sent without PAT or for an unchanged issue") }
    try await api.update(issue: fixture, original: details, statusID: "status-open", labelIDs: ["label-old"], closed: false)
    let noLogin = GitLabGraphQL(config: configuration, transport: transport, token: nil)
    do { _ = try await noLogin.details(for: fixture); fatalError("Missing PAT accepted") } catch let error as URLError { assert(error.code == .userAuthenticationRequired) }
    assert(details.title == "Original title" && details.description == "Original **Markdown**")
    let textInput = try GitLabGraphQL.updateInput(issue: fixture, original: details, statusID: "status-open", labelIDs: ["label-old"], closed: false, title: "  Updated title  ", description: "")
    assert(textInput["title"] as? String == "Updated title")
    assert((textInput["descriptionWidget"] as? [String: String]) == ["description": ""], "An empty description must clear it explicitly")
    assert(textInput["labelsWidget"] == nil && textInput["statusWidget"] == nil)
    let unchanged = try GitLabGraphQL.updateInput(issue: fixture, original: details, statusID: "status-open", labelIDs: ["label-old"], closed: false, title: "Original title", description: "Original **Markdown**")
    assert(unchanged.count == 1, "Saving text must not replace untouched fields")
    do { _ = try GitLabGraphQL.updateInput(issue: fixture, original: details, statusID: "status-open", labelIDs: [], closed: false, title: " \n "); fatalError("Blank title accepted") } catch GitLabError.emptyTitle {}
    MockProtocol.handler = { request in
        let body = try JSONSerialization.jsonObject(with: try requestBody(request)) as! [String: Any]
        assert((body["query"] as! String).contains("WidgetCreationContext"))
        return (200, ##"{"data":{"currentUser":{"id":"gid://gitlab/User/9"},"project":{"userPermissions":{"createIssue":true},"workItemTypes":{"nodes":[{"id":"gid://gitlab/WorkItems::Type/1","widgetDefinitions":[{"allowedStatuses":[{"id":"status-open","name":"To do","color":"#888888","category":"to_do"}],"defaultOpenStatus":{"id":"status-open","name":"To do","color":"#888888","category":"to_do"}}]}]}}}}"##)
    }
    let creation = try await api.creationContext(projectPath: "team/front")
    assert(creation.typeID == "gid://gitlab/WorkItems::Type/1" && creation.details.status?.id == "status-open")
    let createInput = try GitLabGraphQL.createInput(projectPath: "team/front", context: creation, title: " New issue ", description: "**Текст**", statusID: "status-open", labelIDs: ["label-2", "label-1"])
    assert(createInput["namespacePath"] as? String == "team/front" && createInput["title"] as? String == "New issue")
    assert((createInput["assigneesWidget"] as! [String: [String]])["assigneeIds"] == ["gid://gitlab/User/9"])
    assert((createInput["labelsWidget"] as! [String: [String]])["labelIds"] == ["label-1", "label-2"])
    do { _ = try GitLabGraphQL.createInput(projectPath: "team/front", context: creation, title: "\n ", description: "", statusID: "", labelIDs: []); fatalError("Blank new issue accepted") } catch GitLabError.emptyTitle {}
    let noCreate = CreationContext(typeID: creation.typeID, userID: creation.userID, details: readOnly)
    do { _ = try GitLabGraphQL.createInput(projectPath: "team/front", context: noCreate, title: "New", description: "", statusID: "", labelIDs: []); fatalError("Creation without permission accepted") } catch GitLabError.forbidden {}
    MockProtocol.handler = { request in
        let body = try JSONSerialization.jsonObject(with: try requestBody(request)) as! [String: Any]
        assert((body["query"] as! String).contains("mutation WidgetCreateIssue"))
        let input = (body["variables"] as! [String: Any])["input"] as! [String: Any]
        assert(input["descriptionWidget"] != nil && input["assigneesWidget"] != nil && input["labelsWidget"] != nil && input["statusWidget"] != nil)
        return (200, ##"{"data":{"workItemCreate":{"errors":[],"workItem":{"webUrl":"https://gitlab.example.com/team/front/-/work_items/100"}}}}"##)
    }
    let created = try await api.create(projectPath: "team/front", context: creation, title: "New", description: "text", statusID: "status-open", labelIDs: ["label-1"])
    assert(created.lastPathComponent == "100")
    MockProtocol.handler = { _ in (200, ##"{"data":{"workItemCreate":{"errors":["Denied"],"workItem":null}}}"##) }
    do { _ = try await api.create(projectPath: "team/front", context: creation, title: "New", description: "", statusID: "", labelIDs: []); fatalError("Creation failure reported as success") } catch GitLabError.serverRejection(status: nil, reason: "Denied") {}
    assert(details.canDelete, "Read the server's deleteWorkItem permission")
    MockProtocol.handler = { request in
        let body = try JSONSerialization.jsonObject(with: try requestBody(request)) as! [String: Any]
        assert((body["query"] as! String).contains("mutation WidgetDeleteIssue"))
        let input = (body["variables"] as! [String: Any])["input"] as! [String: String]
        assert(input == ["id": "gid://gitlab/WorkItem/2195"], "Delete only the selected work item")
        return (200, ##"{"data":{"workItemDelete":{"errors":[]}}}"##)
    }
    try await api.delete(issue: fixture, original: details)
    MockProtocol.handler = { _ in fatalError("No request may be sent without delete permission") }
    do { try await api.delete(issue: fixture, original: readOnly); fatalError("Delete permission ignored") } catch GitLabError.forbidden {}
    MockProtocol.handler = { _ in (200, ##"{"data":{"workItemDelete":{"errors":["Permission denied"]}}}"##) }
    do { try await api.delete(issue: fixture, original: details); fatalError("Deletion failure reported as success") } catch GitLabError.serverRejection(status: nil, reason: "Permission denied") {}
    MockProtocol.handler = { _ in (200, ##"{"errors":[{"message":"Denied"}],"data":null}"##) }
    do { try await api.delete(issue: fixture, original: details); fatalError("Top-level deletion error ignored") } catch GitLabError.serverRejection(status: nil, reason: "Denied") {}
    MockProtocol.handler = { _ in (401, "{}") }
    do { try await api.delete(issue: fixture, original: details); fatalError("Expired deletion session accepted") } catch let error as URLError { assert(error.code == .userAuthenticationRequired) }
    let basic = GitLabREST(config: configuration, transport: transport, token: "basic-token")
    MockProtocol.handler = { request in
        assert(request.value(forHTTPHeaderField: "PRIVATE-TOKEN") == "basic-token")
        switch request.httpMethod {
        case "GET":
            if request.url!.lastPathComponent == "labels" { return (200, ##"[{"name":"old","color":"#888888"},{"name":"new","color":"#ffffff"}]"##) }
            assert(request.url!.lastPathComponent == "2195")
            return (200, #"{"title":"Basic title","id":2195,"web_url":"https://gitlab.example.com/team/front/-/issues/2195","description":"Basic text","state":"opened","labels":["old"]}"#)
        case "PUT":
            let json = try JSONSerialization.jsonObject(with: try requestBody(request)) as! [String: String]
            assert(json == ["title":"New title","description":"","state_event":"close","add_labels":"new","remove_labels":"old"])
            return (200, "{}")
        case "POST":
            let json = try JSONSerialization.jsonObject(with: try requestBody(request)) as! [String: Any]
            assert(json["assignee_ids"] as? [Int] == [42])
            assert(json["labels"] as? String == "new")
            return (201, #"{"title":"New issue","labels":[],"web_url":"https://gitlab.example.com/team/front/-/issues/2196"}"#)
        default: fatalError("Unexpected basic API method")
        }
    }
    let (basicDetails, basicLabels) = try await basic.editorData(for: fixture)
    assert(basicDetails.usesREST && basicDetails.statuses.isEmpty && basicLabels.count == 2)
    try await basic.update(issue: fixture, original: basicDetails, labelIDs: ["new"], closed: true, title: "New title", description: "")
    let basicContext = CreationContext(typeID: "", userID: "42", details: basicDetails)
    let basicCreated = try await basic.create(projectPath: "team/front", context: basicContext, title: "New issue", description: "", labelIDs: ["new"])
    assert(basicCreated.lastPathComponent == "2196")
    print("Passed: basic API editor, label deltas, close/reopen and self-assigned creation without extended status schema.")
    print("Passed: deletion target, permission guard, payload/GraphQL errors and expired sessions using mock requests only.")
    let rest = GitLabREST(config: configuration, transport: transport, token: "test-only-token")
    let project = GitLabProject(id: 10, path: "team/front", defaultBranch: "dev")
    var deploymentPages: [Int] = []
    MockProtocol.handler = { request in
        assert(request.httpMethod == "GET" && request.url!.path == "/api/v4/projects/10/deployments")
        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
        assert(!query.contains { $0.name == "ref" }, "Deployments API has no ref filter")
        let page = Int(query.first { $0.name == "page" }!.value!)!
        deploymentPages.append(page)
        if page == 1 {
            MockProtocol.headers = ["X-Next-Page": "2"]
            return (200, ##"[{"id":12,"ref":"main","sha":"head","status":"success","environment":{"id":1,"name":"production"},"deployable":null}]"##)
        }
        MockProtocol.headers = ["X-Next-Page": "3"]
        return (200, ##"[{"id":11,"ref":"dev","sha":"head","status":"failed","environment":{"id":2,"name":"dev"},"deployable":null}]"##)
    }
    let latest = try await rest.latestDeployment(project: project, branch: "dev")
    assert(latest?.id == 11 && latest?.status == "failed" && deploymentPages == [1, 2], "Find the latest deployment of this ref across pages; do not use another branch or skip failures")
    assert(latest?.caption(head: "head") == "Ошибка деплоя")
    let success = try JSONDecoder().decode(GitLabDeployment.self, from: Data(##"{"id":20,"ref":"dev","sha":"previous","status":"success","environment":{"id":2,"name":"dev"},"deployable":null}"##.utf8))
    assert(success.caption(head: "new-head") == "Другой коммит", "An old successful deployment must not look like deployed HEAD")
    assert(success.caption(head: "previous") == "Развёрнуто")
    MockProtocol.headers = [:]
    MockProtocol.handler = { request in
        assert(request.url!.absoluteString.contains("feature%2Fa%2Bb%26c"), "Branch names must be URL-encoded once")
        return (200, ##"{"name":"feature/a+b&c","commit":{"id":"new-head"}}"##)
    }
    let branch = try await rest.branch(project: project, name: "feature/a+b&c")
    assert(branch.commit.id == "new-head")
    MockProtocol.handler = { _ in (200, "[]") }
    let missing = try await rest.latestDeployment(project: project, branch: "no-deploy")
    assert(missing == nil)
    MockProtocol.handler = { _ in (403, "{}") }
    do { _ = try await rest.latestDeployment(project: project, branch: "dev"); fatalError("Deployment access denial ignored") } catch GitLabError.forbidden {}
    MockProtocol.handler = { _ in (401, "{}") }
    do { _ = try await rest.latestDeployment(project: project, branch: "dev"); fatalError("Deployment session expiry ignored") } catch let error as URLError { assert(error.code == .userAuthenticationRequired) }
    print("Passed: title/Markdown editing, atomic issue creation and self-assignment, blank-title validation, create permissions/errors, paginated branch-specific deployments, outdated SHA, encoded branch names, missing deployments, forbidden/expired sessions.")
    print("Passed: Moscow closed_at boundaries, native status and label deltas, permissions, label pagination, mutation success/errors, expired login and PAT guard.")
}
