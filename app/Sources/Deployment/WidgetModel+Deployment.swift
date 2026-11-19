import Foundation

extension WidgetModel {
    private var selectedProject: GitLabProject? { projects.first { $0.path == selectedProjectPath } }

    func refreshProjects() {
        guard projectTask == nil, !loginRequired else { return }
        let identity = sessionID
        let api = rest
        projectTask = Task {
            defer { if identity == sessionID { projectTask = nil } }
            do {
                let values: [GitLabProject] = try await api.pages(from: config.apiURL("projects", query: [
                    URLQueryItem(name: "membership", value: "true"), URLQueryItem(name: "simple", value: "true"),
                    URLQueryItem(name: "archived", value: "false"), URLQueryItem(name: "order_by", value: "path"), URLQueryItem(name: "sort", value: "asc")]))
                try Task.checkCancellation()
                guard identity == sessionID, !loginRequired else { return }
                projects = values
                if !values.contains(where: { $0.path == selectedProjectPath }) {
                    selectedProjectPath = values.first(where: { $0.path == issues.first?.projectPath })?.path ?? values.first?.path ?? ""
                }
                loadBranches()
            } catch {
                guard !Task.isCancelled, identity == sessionID else { return }
                deploymentError = WidgetMessage {
                    (error as? GitLabError)?.localizedDescription ?? tr("Не удалось загрузить проекты")
                }
            }
        }
    }

    func selectProject(_ path: String) {
        guard path != selectedProjectPath else { return }
        selectedProjectPath = path
        selectedBranch = UserDefaults.standard.string(forKey: preferenceKey("branch.\(path)")) ?? ""
        UserDefaults.standard.set(path, forKey: preferenceKey("project"))
        loadBranches()
    }

    private func loadBranches() {
        branchTask?.cancel()
        deploymentTask?.cancel()
        branches = []
        deployment = nil
        deploymentError = nil
        guard let project = selectedProject, !loginRequired else { deploymentLoading = false; return }
        deploymentLoading = true
        let identity = sessionID
        let api = rest
        branchTask = Task {
            do {
                let values: [GitLabBranch] = try await api.pages(from: config.apiURL("projects/\(project.id)/repository/branches"))
                try Task.checkCancellation()
                guard identity == sessionID, selectedProjectPath == project.path, !loginRequired else { return }
                branches = values
                if !values.contains(where: { $0.name == selectedBranch }) {
                    selectedBranch = values.first(where: { $0.name == project.defaultBranch })?.name ?? values.first?.name ?? ""
                }
                branchTask = nil
                deploymentLoading = false
                refreshDeployment()
            } catch {
                guard !Task.isCancelled, identity == sessionID, selectedProjectPath == project.path else { return }
                branchTask = nil
                deploymentLoading = false
                deploymentError = WidgetMessage {
                    (error as? GitLabError)?.localizedDescription ?? tr("Ветки недоступны")
                }
            }
        }
    }

    func selectBranch(_ name: String) {
        guard branches.contains(where: { $0.name == name }) else { return }
        selectedBranch = name
        UserDefaults.standard.set(name, forKey: preferenceKey("branch.\(selectedProjectPath)"))
        refreshDeployment()
    }

    func refreshDeployment() {
        guard !loginRequired, branchTask == nil, let project = selectedProject, !selectedBranch.isEmpty else { return }
        deploymentTask?.cancel()
        let branch = selectedBranch
        let identity = sessionID
        let api = rest
        deployment = nil
        deploymentError = nil
        deploymentLoading = true
        deploymentTask = Task {
            do {
                async let head = api.branch(project: project, name: branch)
                async let latest = api.latestDeployment(project: project, branch: branch)
                let (current, latestDeployment) = try await (head, latest)
                try Task.checkCancellation()
                guard identity == sessionID, selectedProjectPath == project.path, selectedBranch == branch, !loginRequired else { return }
                deploymentHead = current.commit.id
                deployment = latestDeployment
                deploymentLoading = false
                deploymentTask = nil
            } catch {
                guard !Task.isCancelled, identity == sessionID, selectedProjectPath == project.path, selectedBranch == branch else { return }
                deploymentLoading = false
                deploymentTask = nil
                deploymentError = WidgetMessage {
                    (error as? GitLabError)?.localizedDescription ?? tr("Деплой недоступен")
                }
            }
        }
    }

    func openDeployment() {
        guard let deployment, let project = selectedProject else { return }
        let fallback = config.endpoint(project.path.split(separator: "/").map { Configuration.encodeSegment(String($0)) }.joined(separator: "/") + "/-/environments/\(deployment.environment.id)")
        open(deployment.deployable?.webURL ?? deployment.deployable?.pipeline?.webURL ?? fallback)
    }

    func clearProjectData() {
        projectTask?.cancel()
        projectTask = nil
        branchTask?.cancel()
        branchTask = nil
        deploymentTask?.cancel()
        deploymentTask = nil
        projects = []
        branches = []
        deployment = nil
        deploymentHead = ""
        deploymentLoading = false
        deploymentError = nil
    }

    func preferenceKey(_ suffix: String) -> String {
        "deployment.\(config.baseURL.absoluteString).\(currentUser?.id ?? 0).\(suffix)"
    }
}
