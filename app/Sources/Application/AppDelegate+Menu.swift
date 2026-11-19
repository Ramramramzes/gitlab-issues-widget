import AppKit
import ServiceManagement

extension AppDelegate {
    func updateMenus() {
        statusItem.button?.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: tr("GitLab задачи"))
        let menu = NSMenu()
        for (title, action, key, symbol) in [
            (tr("Показать виджет"), #selector(showWidget), "", "rectangle.on.rectangle"),
            (tr("Слева по свободной высоте"), #selector(fillLeftSide), "", "sidebar.left"),
            (tr("Выровнять по сетке виджетов"), #selector(alignToWidgetGrid), "", "square.grid.2x2"),
            (tr("Настройки виджета…"), #selector(showSettings), ",", "gearshape"),
            (tr("Обновить сейчас"), #selector(refresh), "r", "arrow.clockwise"),
            (tr("Открыть задачи в браузере"), #selector(openDashboard), "", "arrow.up.right.square"),
            (tr("Подключение GitLab…"), #selector(showLogin), "", "person.crop.circle"),
            (tr("Отключить аккаунт"), #selector(logout), "", "rectangle.portrait.and.arrow.right")
        ] {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
            item.target = self
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        }
        menu.addItem(.separator())
        let login = menu.addItem(withTitle: tr("Запускать при входе"), action: #selector(toggleLogin(_:)), keyEquivalent: "")
        login.target = self
        login.image = NSImage(systemSymbolName: "power.circle", accessibilityDescription: nil)
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(.separator())
        let quit = menu.addItem(withTitle: tr("Завершить GitLab Widget"), action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        quit.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        statusItem.menu = menu
        let mainMenu = NSMenu()
        let appItem = mainMenu.addItem(withTitle: "GitLab Widget", action: nil, keyEquivalent: "")
        let appMenu = NSMenu()
        for item in menu.items { appMenu.addItem(item.copy() as! NSMenuItem) }
        appItem.submenu = appMenu
        let editItem = mainMenu.addItem(withTitle: tr("Правка"), action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: tr("Правка"))
        for (title, action, key) in [(tr("Отменить"), "undo:", "z"), (tr("Повторить"), "redo:", "Z"),
                                     (tr("Вырезать"), "cut:", "x"), (tr("Копировать"), "copy:", "c"),
                                     (tr("Вставить"), "paste:", "v"), (tr("Выбрать всё"), "selectAll:", "a")] {
            let item = editMenu.addItem(withTitle: title, action: NSSelectorFromString(action), keyEquivalent: key)
            item.target = nil
        }
        editItem.submenu = editMenu
        NSApp.mainMenu = mainMenu
    }

    @objc private func toggleLogin(_ sender: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
            sender.state = SMAppService.mainApp.status == .enabled ? .on : .off
            if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        } catch {
            let alert = NSAlert()
            alert.messageText = tr("Не удалось изменить автозапуск")
            alert.informativeText = tr("Добавь GitLab Issues в Системные настройки → Основные → Объекты входа.")
            alert.window.hidesOnDeactivate = true
            alert.runModal()
        }
    }
}
