import Foundation

extension WidgetModel {
    func creationData(projectPath: String) async throws -> (CreationContext, [IssueLabel]) {
        guard editingEnabled else { throw GitLabError.forbidden }
        guard !loginRequired else { throw URLError(.userAuthenticationRequired) }
        let identity = sessionID
        let api = graphQL
        do {
            try await rest.checkWriteScope()
            guard identity == sessionID else { throw CancellationError() }
            let result: (CreationContext, [IssueLabel])
            do {
                let context = try await api.creationContext(projectPath: projectPath)
                result = (context, try await api.labels(projectPath: projectPath))
            } catch {
                try Task.checkCancellation()
                guard identity == sessionID, let user = currentUser else { throw CancellationError() }
                let available = try await rest.labels(project: Configuration.encodeSegment(projectPath))
                result = (CreationContext(typeID: "", userID: String(user.id),
                         details: IssueDetails(status: nil, statuses: [], labels: [], canEdit: true, usesREST: true)), available)
            }
            try Task.checkCancellation()
            guard identity == sessionID else { throw CancellationError() }
            return result
        } catch {
            if identity == sessionID && (error as? URLError)?.code == .userAuthenticationRequired { requireLogin() }
            throw error
        }
    }

    func create(projectPath: String, context: CreationContext, title: String, description: String,
                statusID: String, labelIDs: Set<String>, pendingURL: URL?,
                onCreated: (URL) -> Void, onSuccess: () -> Void) async throws {
        guard editingEnabled else { throw GitLabError.forbidden }
        guard !loginRequired else { throw URLError(.userAuthenticationRequired) }
        guard !saving, !loading else { throw GitLabError.unavailable }
        guard let user = currentUser else { throw URLError(.userAuthenticationRequired) }
        let identity = sessionID
        let api = rest
        saving = true
        defer { if identity == sessionID { saving = false } }
        do {
            let url: URL
            if let pendingURL {
                url = pendingURL
            } else if context.details.usesREST {
                url = try await api.create(projectPath: projectPath, context: context, title: title, description: description, labelIDs: labelIDs)
            } else {
                url = try await graphQL.create(projectPath: projectPath, context: context, title: title, description: description, statusID: statusID, labelIDs: labelIDs)
            }
            try Task.checkCancellation()
            guard identity == sessionID else { throw CancellationError() }
            if pendingURL == nil { onCreated(url) }
            try await api.confirmCreation(at: url, projectPath: projectPath, assigneeID: user.id)
            try Task.checkCancellation()
            guard identity == sessionID else { throw CancellationError() }
            finishMutation(onSuccess)
        } catch {
            if identity == sessionID && (error as? URLError)?.code == .userAuthenticationRequired { requireLogin() }
            throw error
        }
    }

    func editorData(for issue: Issue) async throws -> (IssueDetails, [IssueLabel]) {
        guard editingEnabled else { throw GitLabError.forbidden }
        guard !loginRequired else { throw URLError(.userAuthenticationRequired) }
        let identity = sessionID
        let api = graphQL
        do {
            try await rest.checkWriteScope()
            guard identity == sessionID else { throw CancellationError() }
            let result: (IssueDetails, [IssueLabel])
            do {
                let details = try await api.details(for: issue)
                result = (details, try await api.labels(for: issue))
            } catch {
                try Task.checkCancellation()
                guard identity == sessionID else { throw CancellationError() }
                if case GitLabError.labelsIncomplete = error { throw error }
                result = try await rest.editorData(for: issue)
            }
            try Task.checkCancellation()
            guard identity == sessionID else { throw CancellationError() }
            return result
        } catch {
            if identity == sessionID && (error as? URLError)?.code == .userAuthenticationRequired { requireLogin() }
            throw error
        }
    }

    func update(issue: Issue, original: IssueDetails, statusID: String, labelIDs: Set<String>, closed: Bool,
                title: String? = nil, description: String? = nil, onSuccess: () -> Void) async throws {
        guard editingEnabled else { throw GitLabError.forbidden }
        guard !loginRequired else { throw URLError(.userAuthenticationRequired) }
        guard !saving, !loading else { throw GitLabError.unavailable }
        let identity = sessionID
        saving = true
        defer { if identity == sessionID { saving = false } }
        do {
            if original.usesREST {
                try await rest.update(issue: issue, original: original, labelIDs: labelIDs, closed: closed, title: title, description: description)
            } else {
                try await graphQL.update(issue: issue, original: original, statusID: statusID, labelIDs: labelIDs, closed: closed, title: title, description: description)
            }
            try Task.checkCancellation()
            guard identity == sessionID else { throw CancellationError() }
            finishMutation(onSuccess)
        } catch {
            if identity == sessionID && (error as? URLError)?.code == .userAuthenticationRequired { requireLogin() }
            throw error
        }
    }

    func delete(issue: Issue, original: IssueDetails, onSuccess: () -> Void) async throws {
        guard editingEnabled else { throw GitLabError.forbidden }
        guard !loginRequired else { throw URLError(.userAuthenticationRequired) }
        guard !saving, !loading else { throw GitLabError.unavailable }
        let identity = sessionID
        saving = true
        defer { if identity == sessionID { saving = false } }
        do {
            try await graphQL.delete(issue: issue, original: original)
            try Task.checkCancellation()
            guard identity == sessionID else { throw CancellationError() }
            issues.removeAll { $0.id == issue.id }
            closedIssues.removeAll { $0.id == issue.id }
            finishMutation(onSuccess)
        } catch {
            if identity == sessionID && (error as? URLError)?.code == .userAuthenticationRequired { requireLogin() }
            throw error
        }
    }

    private func finishMutation(_ onSuccess: () -> Void) {
        saving = false
        onSuccess()
        refresh()
    }
}
