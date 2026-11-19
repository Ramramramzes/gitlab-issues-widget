import SwiftUI

struct DeploymentFooter: View {
    @ObservedObject var model: WidgetModel
    private var statusSymbol: String {
        if model.loginRequired { return "person.crop.circle" }
        if model.deploymentError != nil { return "exclamationmark.triangle.fill" }
        guard let deployment = model.deployment else { return "minus.circle" }
        if deployment.sha != model.deploymentHead { return "clock.arrow.circlepath" }
        switch deployment.status {
        case "success": return "checkmark.circle.fill"
        case "failed": return "xmark.circle.fill"
        case "running", "created": return "arrow.triangle.2.circlepath"
        case "blocked": return "pause.circle.fill"
        default: return "minus.circle"
        }
    }
    private var caption: String {
        if model.loginRequired { return tr("Нужен вход") }
        if model.deploymentLoading { return tr("Обновление…") }
        if model.deploymentError != nil { return tr("Недоступен") }
        if model.selectedBranch.isEmpty { return tr("Выбери ветку") }
        return model.deployment?.caption(head: model.deploymentHead) ?? tr("Деплоев нет")
    }
    private var color: Color {
        guard !model.loginRequired, !model.deploymentLoading, model.deploymentError == nil, let deployment = model.deployment else { return .secondary }
        if deployment.sha != model.deploymentHead { return .orange }
        switch deployment.status {
        case "success": return .green
        case "failed": return .red
        case "running", "created", "blocked": return .orange
        default: return .secondary
        }
    }
    private var detail: String {
        if let error = model.deploymentError { return error.text }
        guard let deployment = model.deployment else { return tr("Последний деплой выбранной ветки · обновление каждую минуту") }
        return "\(deployment.environment.name) · \(deployment.status) · \(deployment.sha.prefix(8))" +
            (deployment.sha == model.deploymentHead ? "" : tr(" · HEAD ветки отличается от коммита этого деплоя"))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text(tr("Деплой")).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                AutocompleteField(key: "Проект", options: model.projects.map {
                    AutocompleteOption(id: $0.path, title: $0.name, detail: $0.path)
                }, selection: .single(Binding(get: { model.selectedProjectPath }, set: { model.selectProject($0) })), compact: true,
                                  onPresentationChange: { model.onAutocompleteVisibilityChange?($0) })
                    .foregroundStyle(.secondary)
                    .disabled(model.loginRequired || model.projects.isEmpty).help(model.selectedProjectPath)
                WidgetIconButton(title: tr("Обновить деплой"), symbol: "arrow.clockwise") {
                    if model.projects.isEmpty || model.branches.isEmpty { model.refreshProjects() }
                    else { model.refreshDeployment() }
                }.disabled(model.loginRequired || model.deploymentLoading)
            }
            HStack(spacing: 8) {
                AutocompleteField(key: "Ветка", options: model.branches.map { AutocompleteOption(id: $0.name, title: $0.name) },
                                  selection: .single(Binding(get: { model.selectedBranch }, set: { model.selectBranch($0) })), compact: true,
                                  onPresentationChange: { model.onAutocompleteVisibilityChange?($0) })
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .disabled(model.loginRequired || model.branches.isEmpty).help(model.selectedBranch)
                Button { model.openDeployment() } label: {
                    HStack(spacing: 5) {
                        if model.deploymentLoading { ProgressView().controlSize(.mini) }
                        else { Image(systemName: statusSymbol).symbolRenderingMode(.hierarchical) }
                        Text(caption).font(.system(size: 11, weight: .medium)).lineLimit(1)
                    }.foregroundStyle(color)
                }.buttonStyle(AppleButtonStyle(tint: color)).controlSize(.small)
                    .disabled(model.deployment == nil || model.deploymentLoading).help(detail)
            }
        }.padding(10).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityElement(children: .contain)
    }
}
