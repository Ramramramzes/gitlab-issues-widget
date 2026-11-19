import AppKit
import SwiftUI

struct WidgetView: View {
    @ObservedObject var model: WidgetModel
    @State private var showClosed = false
    private var displayedIssues: [Issue] { showClosed ? IssueDay.closedToday(model.closedIssues, on: Date()) : model.issues }
    private var displayedError: String? { (model.error ?? (showClosed ? model.closedIssuesError : nil))?.text }
    private var counts: IssueCounts { IssueCounts(issues: model.issues) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Picker(tr("Задачи"), selection: $showClosed) {
                Text(tr("Открытые")).tag(false)
                Text(tr("Закрытые сегодня")).tag(true)
            }.pickerStyle(.segmented).labelsHidden().controlSize(.regular)
                .onChange(of: showClosed) { _ in model.refresh() }
            issueList
            if model.loginRequired {
                if model.canRetryConnection {
                    Button(tr("Повторить подключение")) { model.refresh() }
                        .buttonStyle(AppleButtonStyle()).disabled(model.connecting)
                }
                Button { model.onLoginRequired?() } label: {
                    Label(model.canRetryConnection ? tr("Ввести другой токен") : tr("Подключить GitLab"), systemImage: "person.crop.circle")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity).padding(.vertical, 4)
                }.buttonStyle(AppleButtonStyle(tint: .blue, prominent: true)).controlSize(.large)
                    .tint(.blue).disabled(model.connecting)
                Text(tr("Адрес GitLab, ник и персональный токен"))
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            if displayedIssues.isEmpty { Spacer(minLength: 0) }
            refreshStatus
            if displayedError != nil, let updated = model.updated {
                Text(tr("Последнее обновление: %@", updated.formatted(date: .abbreviated, time: .shortened)))
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            if let notice = model.layoutNotice {
                Text(notice.text).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            DeploymentFooter(model: model)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .preferredColorScheme(.dark)
        .contextMenu {
            Button { model.refresh() } label: { Label(tr("Обновить"), systemImage: "arrow.clockwise") }
            Button { model.open(model.config.dashboardURL) } label: { Label(tr("Открыть задачи в браузере"), systemImage: "arrow.up.right.square") }.disabled(model.loginRequired)
            Button { model.onLogout?() } label: { Label(tr("Отключить аккаунт"), systemImage: "rectangle.portrait.and.arrow.right") }.disabled(!model.canDisconnect)
            Divider()
            Button { NSApp.terminate(nil) } label: { Label(tr("Завершить виджет"), systemImage: "power") }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            WidgetDragHandle(locked: model.layoutLocked || model.fillsLeftSide, onStart: { model.onMoveWidget?() }).frame(width: 20, height: 24)
                .help(model.fillsLeftSide ? tr("Автоматически слева по свободной высоте") : model.layoutLocked ? tr("Положение закреплено в настройках") : tr("Перетащи за этот значок, чтобы переместить виджет"))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(tr("Мои задачи")).font(.system(size: 15, weight: .bold)).lineLimit(1)
                    HStack(spacing: 4) {
                        Text("\(counts.toDo)").foregroundStyle(.white)
                        Text("|").foregroundStyle(.secondary)
                        Text("\(counts.inProgress)").foregroundStyle(.blue)
                        Text("|").foregroundStyle(.secondary)
                        Text("\(counts.blocked)").foregroundStyle(.red)
                    }.font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit()
                        .fixedSize().help(counts.help)
                        .accessibilityElement(children: .ignore).accessibilityLabel(counts.help)
                }
                Text(model.connectedUsername.map { "GitLab · @\($0)" } ?? "GitLab")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            WidgetIconButton(title: tr("Создать задачу"), symbol: "plus", tint: .blue) { model.onCreate?() }
                .disabled(!model.editingEnabled || model.loginRequired || model.projects.isEmpty || model.saving)
            WidgetIconButton(title: tr("Настройки виджета"), symbol: "gearshape") { model.onSettings?() }
        }
    }

    private var emptyStateTitle: String {
        if model.loginRequired {
            if model.connecting { return tr("Проверяем подключение…") }
            if model.canRetryConnection { return tr("Восстановление подключения") }
            return tr("Войди, чтобы увидеть задачи")
        }
        if model.loading { return tr("Загрузка задач…") }
        if displayedError != nil { return tr("Не удалось загрузить задачи") }
        return showClosed ? tr("Сегодня закрытых задач нет") : tr("Открытых задач нет")
    }

    @ViewBuilder private var issueList: some View {
        if displayedIssues.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: model.loginRequired ? "person.crop.circle" : displayedError != nil ? "wifi.exclamationmark" : "checkmark.circle")
                    .font(.system(size: 32, weight: .light)).symbolRenderingMode(.hierarchical)
                Text(emptyStateTitle)
                    .font(.system(size: 13)).multilineTextAlignment(.center)
            }.foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 24)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(displayedIssues) { issue in
                        IssueCard(model: model, issue: issue, showClosed: showClosed)
                    }
                }
            }.scrollIndicators(.hidden)
        }
    }

    private var refreshStatus: some View {
        HStack(spacing: 7) {
            Circle().fill(displayedError == nil ? .green : .orange).frame(width: 5, height: 5)
            if let error = displayedError {
                Text(error).foregroundStyle(.orange)
            } else if let updated = model.updated {
                Text(tr("Обновлено %@", updated.formatted(date: .omitted, time: .shortened)))
            } else { Text(tr("Подключение…")) }
            Spacer()
            Text(tr("15 мин"))
            WidgetIconButton(title: tr("Обновить задачи"), symbol: "arrow.clockwise") { model.refresh() }
                .disabled(model.loading || model.saving)
        }.font(.system(size: 10)).foregroundStyle(.secondary)
    }
}

private struct WidgetDragHandle: NSViewRepresentable {
    let locked: Bool
    let onStart: () -> Void

    final class DragImage: NSImageView {
        var locked = false
        var onStart: (() -> Void)?
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func resetCursorRects() {
            super.resetCursorRects()
            addCursorRect(bounds, cursor: locked ? .arrow : .openHand)
        }
        override func mouseDown(with event: NSEvent) {
            guard !locked, let window else { return }
            onStart?()
            window.performDrag(with: event)
            window.saveFrame(usingName: "GitLabDesktopWidget")
        }
    }
    func makeNSView(context: Context) -> DragImage {
        let view = DragImage()
        view.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: tr("Переместить виджет"))
        view.contentTintColor = .secondaryLabelColor
        view.imageScaling = .scaleProportionallyUpOrDown
        return view
    }
    func updateNSView(_ view: DragImage, context: Context) {
        view.setAccessibilityLabel(tr("Переместить виджет"))
        view.locked = locked
        view.onStart = onStart
        view.window?.invalidateCursorRects(for: view)
    }
}
