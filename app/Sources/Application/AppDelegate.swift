import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var widgetWindow: WidgetWindowController!
    private var model: WidgetModel!
    private(set) var statusItem: NSStatusItem!
    private var loginWindow: NSWindow?
    private var editorWindow: NSWindow?
    private var editorTitle: WidgetMessage?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        model = WidgetModel()
        model.onLoginRequired = { [weak self] in self?.showLogin() }
        model.onLogout = { [weak self] in self?.logout() }
        model.onEdit = { [weak self] issue in self?.showEditor(issue) }
        model.onCreate = { [weak self] in self?.showEditor(nil) }
        model.onDelete = { [weak self] issue in self?.showEditor(issue, requestDeletion: true) }
        model.onSettings = { [weak self] in self?.showSettings() }
        model.onMoveWidget = { [weak self] in self?.widgetWindow.bringWidgetForward() }
        model.onAutocompleteVisibilityChange = { [weak self] active in
            if active { self?.widgetWindow.window.makeKeyAndOrderFront(nil) }
        }
        widgetWindow = WidgetWindowController(model: model)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateMenus()
        widgetWindow.placeOnLaunch()
        showWidget()
        Task { await model.restoreConnection() }
    }

    private func changeLanguage(_ language: WidgetLanguage) {
        guard model.language != language else { return }
        model.setLanguage(language)
        updateMenus()
        settingsWindow?.title = tr("Настройки виджета")
        if let title = editorTitle { editorWindow?.title = title.text }
        DispatchQueue.main.async { [weak self] in
            if let panel = self?.loginWindow, let view = panel.contentView {
                panel.setContentSize(view.fittingSize)
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWidget()
        if model.canRetryConnection { model.refresh() }
        return false
    }

    @objc func showWidget() {
        if !widgetWindow.show() { showSettings() }
    }

    @objc func fillLeftSide() {
        widgetWindow.fillLeftSide()
        showWidget()
    }

    @objc func alignToWidgetGrid() {
        _ = widgetWindow.applyGridAlignment()
    }

    @objc func showSettings() {
        if let settingsWindow, settingsWindow.isVisible {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        settingsWindow?.contentView = nil
        settingsWindow?.close()
        let initial = widgetWindow.currentGeometry()
        let panel = DesktopPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 490),
                                 styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
        panel.allowsMainWindow = true
        panel.title = tr("Настройки виджета")
        panel.isRestorable = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.level = .normal
        panel.minSize = NSSize(width: 340, height: 420)
        panel.maxSize = NSSize(width: 640, height: 900)
        panel.contentView = glassHostingView(WidgetSettingsView(model: model, value: initial, placementWarning: widgetWindow.placementBlocked ? model.layoutNotice : nil,
            onLanguageChange: { [weak self] in self?.changeLanguage($0) },
            onApply: { [weak self] value in
                guard let self else { return "Виджет недоступен." }
                return widgetWindow.applyGeometry(value)
            },
            onAlign: { [weak self] in self?.widgetWindow.applyGridAlignment() ?? false },
            onMove: { [weak self] in self?.widgetWindow.bringWidgetForward() },
            onClose: { [weak panel] in panel?.close() },
            onApplied: { [weak self, weak panel] in
                panel?.close()
                self?.model.refresh()
            }))
        if let screen = widgetWindow.widgetScreen {
            let area = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: area.midX - panel.frame.width / 2,
                                         y: area.midY - panel.frame.height / 2))
        } else { panel.center() }
        settingsWindow = panel
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func refresh() { model.refresh() }

    @objc func openDashboard() { if !model.loginRequired { model.open(model.config.dashboardURL) } }
    func showEditor(_ issue: Issue?, requestDeletion: Bool = false) {
        guard model.editingEnabled, !model.loginRequired, !model.connecting, !model.saving else { return }
        if let editorWindow, editorWindow.isVisible {
            editorWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        editorWindow?.contentView = nil
        editorWindow?.close()
        let window = widgetWindow.window
        let width = max(320, min(window.frame.width, 620))
        let height = max(400, min(window.frame.height, 700))
        let panel = DesktopPanel(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                                 styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
        panel.allowsMainWindow = true
        let title = issue.map { issue in WidgetMessage { tr("Редактирование задачи · %@", issue.number) } } ?? "Новая задача"
        editorTitle = title
        panel.title = title.text
        panel.isRestorable = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.level = .normal
        panel.minSize = NSSize(width: 320, height: 340)
        panel.maxSize = NSSize(width: 800, height: 1000)
        panel.contentView = glassHostingView(IssueEditor(model: model, issue: issue, requestDeletion: requestDeletion) { [weak panel] in panel?.close() })
        if let screen = window.screen {
            let area = screen.visibleFrame
            let preferredX = window.frame.maxX + 10
            let x = preferredX + width <= area.maxX ? preferredX : max(area.minX, window.frame.minX - width - 10)
            let y = min(max(area.minY, window.frame.maxY - height), area.maxY - height)
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        } else { panel.center() }
        editorWindow = panel
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func quit() { NSApp.terminate(nil) }
    @objc func showLogin() {
        if let panel = loginWindow, panel.isVisible {
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        guard !model.connecting else { return }
        let panel = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = "GitLab"
        panel.isRestorable = false
        panel.isReleasedWhenClosed = false
        let view = NSHostingView(rootView: ConnectionView(model: model) { [weak self, weak panel] in
            self?.editorWindow?.close()
            panel?.close()
        })
        panel.contentView = view
        panel.setContentSize(view.fittingSize)
        if let area = widgetWindow.widgetScreen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: area.midX - panel.frame.width / 2, y: area.midY - panel.frame.height / 2))
        } else { panel.center() }
        loginWindow = panel
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func logout() {
        do {
            try model.disconnect()
            editorWindow?.close()
            loginWindow?.close()
        } catch {
            let alert = NSAlert()
            alert.messageText = tr("Не удалось отключить аккаунт")
            alert.informativeText = WidgetModel.connectionMessage(error)
            alert.window.hidesOnDeactivate = true
            alert.runModal()
        }
    }
}
