import SwiftUI

struct IssueEditor: View {
    @ObservedObject var model: WidgetModel
    let issue: Issue?
    let onClose: () -> Void
    let requestDeletion: Bool
    @State private var projectPath: String
    @State private var original: IssueDetails?
    @State private var creation: CreationContext?
    @State private var pendingCreation: URL?
    @State private var labels: [IssueLabel] = []
    @State private var selectedLabels: Set<String> = []
    @State private var selectedStatus = ""
    @State private var title: String
    @State private var description = ""
    @State private var closed = false
    @State private var loading = true
    @State private var failure: WidgetMessage?
    @State private var reload = 0
    @State private var confirmingDeletion = false

    init(model: WidgetModel, issue: Issue?, requestDeletion: Bool = false, onClose: @escaping () -> Void) {
        self.model = model
        self.issue = issue
        self.onClose = onClose
        self.requestDeletion = requestDeletion
        _projectPath = State(initialValue: issue?.projectPath ?? model.selectedProjectPath)
        _title = State(initialValue: issue?.title ?? "")
    }

    private var hasChanges: Bool {
        guard let original, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard let issue else { return true }
        return title != (original.title ?? issue.title) || description != (original.description ?? "") ||
            selectedStatus != (original.status?.id ?? "") || selectedLabels != Set(original.labels.map(\.id)) ||
            (original.statuses.isEmpty && closed != (issue.state == "closed"))
    }

    private func statusOptions(_ details: IssueDetails) -> [AutocompleteOption] {
        var values = details.statuses.map { AutocompleteOption(id: $0.id, title: $0.name) }
        if let current = details.status, !values.contains(where: { $0.id == current.id }) {
            values.insert(AutocompleteOption(id: current.id, title: current.name), at: 0)
        }
        if details.status == nil { values.insert(AutocompleteOption(id: "", title: tr("По умолчанию")), at: 0) }
        return values
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider().overlay(.white.opacity(0.08))
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if issue == nil {
                        fieldCaption(tr("Проект"))
                        AutocompleteField(key: "Проект", options: model.projects.map {
                            AutocompleteOption(id: $0.path, title: $0.name, detail: $0.path)
                        }, selection: .single($projectPath)).disabled(pendingCreation != nil)
                    }
                    if loading {
                        ProgressView(tr("Загрузка…")).font(.caption).frame(maxWidth: .infinity, minHeight: 130)
                    } else if let original {
                        editorFields(original).disabled(pendingCreation != nil)
                    }
                    if let failure {
                        Text(failure.text).font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                        if let pendingCreation {
                            Button { model.open(pendingCreation) } label: {
                                Label(tr("Открыть в GitLab"), systemImage: "arrow.up.right.square")
                            }.buttonStyle(AppleButtonStyle()).font(.caption)
                        } else if original == nil {
                            Button { reload += 1 } label: { Label(tr("Повторить загрузку"), systemImage: "arrow.clockwise") }
                                .buttonStyle(AppleButtonStyle()).font(.caption)
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 2)
            }.scrollIndicators(.hidden).disabled(model.saving || model.loginRequired)
            Divider().overlay(.white.opacity(0.08))
            actions
        }
        .padding(16).frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme(.dark)
        .task(id: projectPath + ":" + String(reload)) { await load() }
        .alert(tr("Удалить %@?", issue?.number ?? tr("задачу")), isPresented: $confirmingDeletion) {
            Button(tr("Отмена"), role: .cancel) {}
            Button(tr("Удалить"), role: .destructive) { removeIssue() }
                .disabled(model.loading || model.saving || model.loginRequired || original?.canDelete != true)
        } message: {
            Text("\(original?.title ?? issue?.title ?? "")\n\(issue?.projectPath ?? "")\n\n" + tr("Задача и её обсуждение будут удалены из GitLab. Это действие необратимо."))
        }
    }

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: "square.and.pencil").symbolRenderingMode(.hierarchical).foregroundStyle(.blue).font(.system(size: 22))
            VStack(alignment: .leading, spacing: 3) {
                Text(issue == nil ? tr("Новая задача") : tr("Редактирование задачи")).font(.system(size: 15, weight: .semibold))
                Text(issue.map { "\($0.number) · \($0.project)" } ?? tr("Будет назначена тебе"))
                    .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            WidgetIconButton(title: tr("Закрыть редактор"), symbol: "xmark", action: onClose).disabled(model.saving)
        }
    }

    private var saveTitle: String {
        if model.saving { return tr("Сохранение…") }
        if pendingCreation != nil { return tr("Проверить создание") }
        return issue == nil ? tr("Создать") : tr("Сохранить")
    }

    private var actions: some View {
        HStack(spacing: 8) {
            if let issue {
                WidgetIconButton(title: tr("Открыть в браузере"), symbol: "arrow.up.right.square") { model.open(issue.url) }
                WidgetIconButton(title: tr("Удалить задачу"), symbol: "trash", tint: .red) { confirmingDeletion = true }
                    .disabled(original?.canDelete != true || model.saving || model.loading || model.loginRequired)
            }
            Spacer(minLength: 0)
            Button(tr("Отмена"), action: onClose).buttonStyle(AppleButtonStyle())
                .keyboardShortcut(.cancelAction).disabled(model.saving)
            Button(action: save) {
                HStack(spacing: 5) {
                    if model.saving { ProgressView().controlSize(.mini) }
                    Text(saveTitle)
                }.font(.system(size: 12, weight: .semibold))
            }.buttonStyle(AppleButtonStyle(tint: .blue, prominent: true)).tint(.blue).keyboardShortcut(.defaultAction)
                .disabled(loading || model.loading || model.saving || model.loginRequired || original?.canEdit != true || !hasChanges)
        }.font(.system(size: 11))
    }

    private func fieldCaption(_ title: String) -> some View {
        Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
    }

    @ViewBuilder private func editorFields(_ original: IssueDetails) -> some View {
        Group {
            fieldCaption(tr("Название"))
            TextField(tr("Что нужно сделать?"), text: $title).textFieldStyle(.plain).font(.system(size: 13)).padding(10)
                .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            fieldCaption(tr("Описание · Markdown"))
            TextEditor(text: $description).font(.system(size: 12)).scrollContentBackground(.hidden)
                .padding(8).frame(height: 120).background(Color(nsColor: .textBackgroundColor).opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
            if original.statuses.isEmpty {
                if issue != nil {
                    fieldCaption(tr("Состояние"))
                    Picker(tr("Состояние"), selection: $closed) {
                        Text(tr("Открыта")).tag(false)
                        Text(tr("Закрыта")).tag(true)
                    }.pickerStyle(.segmented)
                }
            } else {
                fieldCaption(tr("Статус"))
                AutocompleteField(key: "Статус", options: statusOptions(original), selection: .single($selectedStatus))
                if let status = original.statuses.first(where: { $0.id == selectedStatus }),
                   status.closesIssue != (issue?.state == "closed") {
                    Text(status.closesIssue ? tr("Этот статус закроет задачу.") : tr("Этот статус снова откроет задачу."))
                        .font(.system(size: 10)).foregroundStyle(.orange)
                }
            }
            fieldCaption(tr("Метки"))
            AutocompleteField(key: "Метки", options: labels.map {
                AutocompleteOption(id: $0.id, title: $0.title, color: $0.color, scope: $0.scope)
            }, selection: .multiple($selectedLabels))
            if !original.canEdit { Text(tr("Нет права изменять задачи в этом проекте.")).font(.caption).foregroundStyle(.orange) }
        }.disabled(!original.canEdit)
    }

    @MainActor private func load() async {
        loading = true
        original = nil
        creation = nil
        failure = nil
        do {
            let details: IssueDetails
            let available: [IssueLabel]
            if let issue {
                (details, available) = try await model.editorData(for: issue)
                title = details.title ?? issue.title
                description = details.description ?? ""
                closed = issue.state == "closed"
            } else {
                let (context, values) = try await model.creationData(projectPath: projectPath)
                creation = context
                details = context.details
                available = values
            }
            try Task.checkCancellation()
            original = details
            selectedStatus = details.status?.id ?? ""
            selectedLabels = Set(details.labels.map(\.id))
            var unique: [String: IssueLabel] = [:]
            for label in available + details.labels { unique[label.id] = label }
            labels = unique.values.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            if requestDeletion {
                if details.canDelete { confirmingDeletion = true }
                else { failure = "У тебя нет права удалить эту задачу." }
            }
        } catch {
            guard !Task.isCancelled else { return }
            failure = message(for: error, saving: false)
        }
        loading = false
    }

    private func save() {
        guard let original else { return }
        failure = nil
        Task {
            do {
                if let issue {
                    try await model.update(issue: issue, original: original, statusID: selectedStatus, labelIDs: selectedLabels,
                                           closed: closed, title: title, description: description, onSuccess: onClose)
                } else if let creation {
                    try await model.create(projectPath: projectPath, context: creation, title: title, description: description,
                                           statusID: selectedStatus, labelIDs: selectedLabels, pendingURL: pendingCreation,
                                           onCreated: { pendingCreation = $0 }, onSuccess: onClose)
                } else { throw GitLabError.unavailable }
            } catch { failure = message(for: error, saving: true) }
        }
    }

    private func removeIssue() {
        guard let issue, let original else { return }
        failure = nil
        Task {
            do {
                try await model.delete(issue: issue, original: original, onSuccess: onClose)
            } catch { failure = message(for: error, saving: true) }
        }
    }

    private func message(for error: Error, saving: Bool) -> WidgetMessage {
        if (error as? URLError)?.code == .userAuthenticationRequired { return "Сессия истекла. Войди в GitLab заново." }
        if let known = error as? GitLabError { return WidgetMessage { known.localizedDescription } }
        return saving ? "Ответ GitLab не получен. Проверь список задач перед повторной отправкой." : "Не удалось загрузить редактор. Проверь сеть и повтори загрузку."
    }
}
