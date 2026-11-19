import SwiftUI

struct ConnectionView: View {
    @ObservedObject var model: WidgetModel
    let onConnected: () -> Void
    @State private var server: String
    @State private var username = ""
    @State private var token = ""
    @State private var editingEnabled = false
    @State private var failure: WidgetMessage?

    init(model: WidgetModel, onConnected: @escaping () -> Void) {
        self.model = model
        self.onConnected = onConnected
        _server = State(initialValue: model.config.baseURL.absoluteString)
    }

    private var tokenSettings: URL? {
        guard let base = try? Configuration.serverURL(server) else { return nil }
        return Configuration(baseURL: base, username: "").tokenSettingsURL
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(tr("Подключение к GitLab"), systemImage: "person.crop.circle.badge.checkmark")
                .font(.title3.weight(.semibold))
            if let username = model.connectedUsername {
                Text(tr("Подключён @%@. Для смены аккаунта введи ник и токен нового пользователя.", username))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(tr("Адрес GitLab")).font(.caption.weight(.semibold))
                TextField("https://gitlab.com", text: $server).textFieldStyle(.roundedBorder)
                Text(tr("Имя пользователя")).font(.caption.weight(.semibold))
                TextField(tr("Ник GitLab"), text: $username).textFieldStyle(.roundedBorder)
                Text(tr("Персональный токен")).font(.caption.weight(.semibold))
                SecureField(tr("Токен с ограниченным сроком"), text: $token).textFieldStyle(.roundedBorder)
                if let tokenSettings {
                    Link(tr("Создать токен в GitLab"), destination: tokenSettings).font(.caption)
                }
            }
            Text(tr("Создай личный токен с датой истечения в профиле GitLab. Для просмотра задач из всех доступных проектов выбери read_api."))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Toggle(tr("Разрешить редактирование задач"), isOn: $editingEnabled)
                .toggleStyle(.switch).tint(.blue)
            if editingEnabled {
                Text(tr("Для редактирования выбери api. Это право открывает чтение и запись через API в пределах прав аккаунта."))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Text(tr("Токен сохраняется в Связке ключей macOS."))
                .font(.caption).foregroundStyle(.secondary)
            if let failure {
                Text(failure.text).font(.callout).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("connectionError")
            }
            HStack {
                Spacer()
                if model.connecting { ProgressView().controlSize(.small) }
                Button(tr("Подключить")) { connect() }
                    .buttonStyle(AppleButtonStyle(tint: .blue, prominent: true)).keyboardShortcut(.defaultAction)
                    .disabled(model.connecting || server.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || token.isEmpty)
            }
        }.padding(22).frame(width: 430).disabled(model.connecting)
    }

    private func connect() {
        failure = nil
        Task {
            do {
                try await model.connect(server: server, username: username, token: token, editingEnabled: editingEnabled) {
                    token = ""
                    onConnected()
                }
            } catch {
                failure = WidgetMessage { WidgetModel.connectionMessage(error) }
            }
        }
    }
}
