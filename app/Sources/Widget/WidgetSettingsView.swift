import SwiftUI

struct WidgetSettingsView: View {
    @ObservedObject var model: WidgetModel
    @State private var draft: WidgetGeometry
    @State private var placementWarning: WidgetMessage?
    let onLanguageChange: (WidgetLanguage) -> Void
    let onApply: (WidgetGeometry) -> WidgetMessage?
    let onAlign: () -> Bool
    let onMove: () -> Void
    let onClose: () -> Void
    let onApplied: () -> Void

    init(model: WidgetModel, value: WidgetGeometry, placementWarning: WidgetMessage? = nil,
         onLanguageChange: @escaping (WidgetLanguage) -> Void,
         onApply: @escaping (WidgetGeometry) -> WidgetMessage?, onAlign: @escaping () -> Bool,
         onMove: @escaping () -> Void, onClose: @escaping () -> Void, onApplied: @escaping () -> Void) {
        self.model = model
        _draft = State(initialValue: value)
        _placementWarning = State(initialValue: placementWarning)
        self.onLanguageChange = onLanguageChange
        self.onApply = onApply
        self.onAlign = onAlign
        self.onMove = onMove
        self.onClose = onClose
        self.onApplied = onApplied
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "gearshape").symbolRenderingMode(.hierarchical).foregroundStyle(.blue).font(.system(size: 20))
                Text(tr("Настройки виджета")).font(.system(size: 15, weight: .semibold))
                Spacer()
                WidgetIconButton(title: tr("Закрыть настройки"), symbol: "xmark", action: onClose)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Picker(tr("Язык"), selection: Binding(get: { model.language }, set: onLanguageChange)) {
                        ForEach(WidgetLanguage.allCases, id: \.self) { language in
                            Text(language.name).tag(language)
                        }
                    }
                    .accessibilityIdentifier("widgetLanguagePicker")
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(tr("Аккаунт GitLab")).font(.system(size: 12, weight: .semibold))
                            Text(model.connectedUsername.map { "@\($0)" } ?? tr("Вход не выполнен"))
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        Button {
                            model.onLogout?()
                        } label: {
                            Label(tr("Выйти из аккаунта"), systemImage: "rectangle.portrait.and.arrow.right")
                        }
                        .buttonStyle(AppleButtonStyle())
                        .disabled(!model.canDisconnect)
                        .accessibilityIdentifier("widgetSignOut")
                    }
                    Divider()
                    Toggle(tr("Слева по свободной высоте"), isOn: $draft.fillsLeftSide).toggleStyle(.switch).tint(.blue)
                        .font(.system(size: 12, weight: .semibold))
                    Text(tr("До ближайшего системного виджета, с зазором 16 пт. Если слева свободно — вся рабочая высота. Отключи для ручного размещения."))
                        .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if let placementWarning {
                        Text(placementWarning.text).font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    }
                    numberField(tr("Занято системными виджетами снизу, пт"), value: $draft.reservedBottom).disabled(!draft.fillsLeftSide)
                    Text(tr("0 — определить автоматически. Если автопоиск недоступен, укажи высоту занятой снизу области: она останется свободной."))
                        .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Label(tr("Размер"), systemImage: "arrow.up.left.and.arrow.down.right").font(.system(size: 12, weight: .semibold))
                    HStack {
                        numberField(tr("Ширина"), value: $draft.width)
                        numberField(tr("Высота"), value: $draft.height).disabled(draft.fillsLeftSide)
                    }
                    HStack(spacing: 7) {
                        preset("344 × 344", width: 344, height: 344)
                        preset("400 × 500", width: 400, height: 500)
                        preset("520 × 700", width: 520, height: 700)
                    }.font(.system(size: 10)).disabled(draft.fillsLeftSide)
                    Label(tr("Положение на экране"), systemImage: "rectangle.inset.filled").font(.system(size: 12, weight: .semibold))
                    HStack {
                        numberField(tr("Слева"), value: $draft.left)
                        numberField(tr("Сверху"), value: $draft.top)
                    }.disabled(draft.fillsLeftSide)
                    Text(tr("Отступы от верхнего левого угла доступной области экрана."))
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                    Toggle(tr("Закрепить размер и положение"), isOn: $draft.locked).toggleStyle(.switch).tint(.blue)
                        .font(.system(size: 12))
                    Button {
                        if onAlign() { onApplied() }
                    } label: { Label(tr("Выровнять по сетке"), systemImage: "square.grid.2x2") }
                        .buttonStyle(AppleButtonStyle())
                    Button {
                        if applyDraft() { onMove() }
                    } label: { Label(tr("Переместить мышью"), systemImage: "hand.draw") }
                        .buttonStyle(AppleButtonStyle()).disabled(draft.locked || draft.fillsLeftSide)
                    Text(tr("Перетаскивай значок слева от «Мои задачи». Размер также можно менять за края окна, если оно не закреплено."))
                        .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.padding(.vertical, 2)
            }.scrollIndicators(.hidden)
            HStack {
                Spacer()
                Button(tr("Отмена"), action: onClose).buttonStyle(AppleButtonStyle()).keyboardShortcut(.cancelAction)
                Button(tr("Применить")) { _ = applyDraft() }.buttonStyle(AppleButtonStyle(tint: .blue, prominent: true))
                    .keyboardShortcut(.defaultAction).tint(.blue)
            }.font(.system(size: 12))
        }.padding(18).frame(maxWidth: .infinity, maxHeight: .infinity)
            .preferredColorScheme(.dark)
    }

    private func applyDraft() -> Bool {
        placementWarning = onApply(draft)
        guard placementWarning == nil else { return false }
        onApplied()
        return true
    }

    private func numberField(_ title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
            TextField(title, value: value, format: .number.grouping(.never).precision(.fractionLength(0)))
                .textFieldStyle(.plain).font(.system(size: 13)).padding(10)
                .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func preset(_ title: String, width: Double, height: Double) -> some View {
        Button(title) { draft.width = width; draft.height = height }
            .buttonStyle(AppleButtonStyle()).controlSize(.small)
    }
}
