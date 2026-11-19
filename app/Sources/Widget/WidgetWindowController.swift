import AppKit

@MainActor
final class WidgetWindowController: NSObject {
    let window: DesktopPanel
    private let model: WidgetModel
    private var layoutTimer: Timer?
    private(set) var placementBlocked = false
    private var lastPlacedVisibleArea: CGRect?

    init(model: WidgetModel) {
        self.model = model
        window = DesktopPanel(contentRect: NSRect(x: 26, y: 120, width: 400, height: 440),
                              styleMask: [.borderless, .resizable, .nonactivatingPanel])
        super.init()

        window.title = "GitLab Issues"
        window.isRestorable = false
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.hidesOnDeactivate = false
        window.isFloatingPanel = false
        window.becomesKeyOnlyIfNeeded = true
        window.minSize = NSSize(width: 300, height: 320)
        window.maxSize = NSSize(width: 800, height: CGFloat.greatestFiniteMagnitude)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.contentView = glassHostingView(WidgetView(model: model))
        if !window.setFrameUsingName("GitLabDesktopWidget"), let screen = NSScreen.screens.first {
            window.setFrameTopLeftPoint(NSPoint(x: screen.visibleFrame.minX + 26,
                                                y: screen.visibleFrame.maxY - 26))
        }
        window.setFrameAutosaveName("GitLabDesktopWidget")
        applyLayoutLock()
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        layoutTimer = Timer.scheduledTimer(timeInterval: 5, target: self,
                                          selector: #selector(updateLeftColumnLayout), userInfo: nil, repeats: true)
        NotificationCenter.default.addObserver(self, selector: #selector(updateLeftColumnLayout),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(updateLeftColumnLayout),
                                                          name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
    }

    func placeOnLaunch() {
        if model.fillsLeftSide && model.reservedBottom == 0, let current = widgetScreen {
            let candidates = [current] + NSScreen.screens.filter { $0 != current }
            if let screen = candidates.first(where: { screen in
                let column = WidgetGeometry.fullHeightFrame(in: screen.visibleFrame, width: window.frame.width)
                return desktopWidgets(on: screen)?.contains(where: { $0.intersects(column) }) == true
            }) {
                placeLeftColumn(on: screen)
            }
        }
    }

    func show() -> Bool {
        updateLeftColumnLayout()
        guard !placementBlocked else { return false }
        bringWidgetForward()
        return true
    }

    func bringWidgetForward() {
        guard !placementBlocked else { return }
        window.orderFrontRegardless()
    }

    func currentGeometry() -> WidgetGeometry {
        let area = widgetScreen?.visibleFrame ?? window.frame
        return WidgetGeometry(width: window.frame.width, height: window.frame.height,
                              left: window.frame.minX - area.minX, top: area.maxY - window.frame.maxY,
                              locked: model.layoutLocked, fillsLeftSide: model.fillsLeftSide, reservedBottom: model.reservedBottom)
    }

    var widgetScreen: NSScreen? {
        let center = CGPoint(x: window.frame.midX, y: window.frame.midY)
        return NSScreen.screens.first { $0.frame.contains(center) } ?? window.screen ?? NSScreen.main
    }

    private func applyLayoutLock() {
        window.isMovable = !model.layoutLocked && !model.fillsLeftSide
        window.isMovableByWindowBackground = !model.layoutLocked && !model.fillsLeftSide
        if model.layoutLocked || model.fillsLeftSide { window.styleMask.remove(.resizable) }
        else { window.styleMask.insert(.resizable) }
    }

    func applyGeometry(_ value: WidgetGeometry) -> WidgetMessage? {
        guard let screen = widgetScreen else { return "Экран недоступен." }
        let area = screen.visibleFrame
        let reserve = value.reservedBottom.isFinite ? max(0, value.reservedBottom) : 0
        var frame = WidgetGeometry.fittedFrame(value, in: area, minimum: window.minSize, maximum: window.maxSize)
        if value.fillsLeftSide {
            let widgets = desktopWidgets(on: screen)
            guard let available = WidgetGeometry.availableFrame(in: area, width: frame.width, widgets: widgets, reservedBottom: reserve) else {
                return placementError(widgets: widgets, reservedBottom: reserve)
            }
            frame = available
        }
        model.layoutLocked = value.locked
        model.fillsLeftSide = value.fillsLeftSide
        model.reservedBottom = reserve
        UserDefaults.standard.set(reserve, forKey: "widgetReservedBottom")
        UserDefaults.standard.set(value.fillsLeftSide, forKey: "widgetFullHeightOnLeft")
        applyLayoutLock()
        UserDefaults.standard.set(value.locked, forKey: "widgetLayoutLocked")
        window.setFrame(frame, display: true)
        window.saveFrame(usingName: "GitLabDesktopWidget")
        lastPlacedVisibleArea = value.fillsLeftSide ? area : nil
        placementBlocked = false
        model.layoutNotice = nil
        bringWidgetForward()
        return nil
    }

    func fillLeftSide() {
        model.fillsLeftSide = true
        UserDefaults.standard.set(true, forKey: "widgetFullHeightOnLeft")
        applyLayoutLock()
    }

    private func desktopWidgets(on screen: NSScreen) -> [CGRect]? {
        guard let baseline = NSScreen.screens.first?.frame.maxY,
              let all = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]],
              !all.isEmpty else { return nil }
        var unidentified = false
        let column = WidgetGeometry.fullHeightFrame(in: screen.visibleFrame, width: window.frame.width)
        let frames: [CGRect] = all.compactMap { info in
            let owner = (info[kCGWindowOwnerName as String] as? String ?? "").lowercased()
            guard let layer = info[kCGWindowLayer as String] as? Int, layer < 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  rect.width >= 140, rect.width <= 800, rect.height >= 140, rect.height <= 800 else { return nil }
            // Core Graphics uses a top-left origin; AppKit uses a bottom-left origin.
            let frame = CGRect(x: rect.minX + 7, y: baseline - rect.maxY + 7,
                               width: rect.width - 14, height: rect.height - 14)
            guard screen.visibleFrame.intersects(frame) else { return nil }
            let pid = info[kCGWindowOwnerPID as String] as? Int32
            let bundle = pid.flatMap { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier }?.lowercased() ?? ""
            if owner.isEmpty && bundle.isEmpty && frame.intersects(column) { unidentified = true }
            guard owner.contains("notification") || owner.contains("уведомлен") || owner.contains("widgetkit") ||
                  bundle.contains("notificationcenter") || bundle.contains("widgetkit") else { return nil }
            return frame
        }
        return unidentified ? nil : frames
    }

    @objc private func updateLeftColumnLayout() {
        guard model.fillsLeftSide, let screen = widgetScreen else { return }
        placeLeftColumn(on: screen)
    }

    private func placeLeftColumn(on screen: NSScreen) {
        let widgets = desktopWidgets(on: screen)
        guard let frame = WidgetGeometry.availableFrame(in: screen.visibleFrame, width: window.frame.width,
                                                        widgets: widgets, reservedBottom: model.reservedBottom) else {
            if widgets == nil, lastPlacedVisibleArea == screen.visibleFrame, !placementBlocked { return }
            placementBlocked = true
            model.layoutNotice = placementError(widgets: widgets, reservedBottom: model.reservedBottom)
            window.orderOut(nil)
            return
        }
        model.layoutNotice = widgets == nil ? "Учтена заданная область системных виджетов" : nil
        lastPlacedVisibleArea = screen.visibleFrame
        if window.frame != frame {
            window.setFrame(frame, display: window.isVisible)
            window.saveFrame(usingName: "GitLabDesktopWidget")
        }
        if placementBlocked { window.orderFrontRegardless() }
        placementBlocked = false
    }

    private func placementError(widgets: [CGRect]?, reservedBottom: Double) -> WidgetMessage {
        if widgets == nil && reservedBottom <= 0 {
            return "macOS не сообщила расположение системных виджетов. Укажи занятую снизу область или выбери ручное размещение."
        }
        return "Слева не хватает места для GitLab. Проверь занятый отступ или выбери ручное размещение."
    }

    func applyGridAlignment() -> Bool {
        guard let screen = window.screen ?? NSScreen.main,
              let baseline = NSScreen.screens.first?.frame.maxY,
              let all = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID)
                as? [[String: Any]] else { return false }
        let area = CGRect(x: screen.visibleFrame.minX,
                          y: baseline - screen.visibleFrame.maxY,
                          width: screen.visibleFrame.width, height: screen.visibleFrame.height)
        let widgets: [CGRect] = all.compactMap { info in
            let owner = (info[kCGWindowOwnerName as String] as? String ?? "").lowercased()
            guard owner.contains("notification") || owner.contains("уведомлен"),
                  let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  rect.width >= 140, rect.width <= 800,
                  rect.height >= 140, rect.height <= 800,
                  area.contains(CGPoint(x: rect.midX, y: rect.midY)) else { return nil }
            return rect
        }
        guard let reference = widgets.min(by: {
            $0.minY == $1.minY ? $0.minX < $1.minX : $0.minY < $1.minY
        }) else {
            let alert = NSAlert()
            alert.messageText = tr("Системные виджеты не найдены")
            alert.informativeText = tr("Открой рабочий стол с системными виджетами и повтори выравнивание.")
            alert.window.hidesOnDeactivate = true
            alert.runModal()
            return false
        }
        let smallSide = min(reference.width, reference.height)
        let step = smallSide > 250 ? smallSide / 2 : smallSide
        let outerSide = step * 2
        let currentTop = CGPoint(x: window.frame.minX, y: baseline - window.frame.maxY)
        var choices: [CGRect] = []
        for row in -6...12 {
            for column in -12...12 {
                let cell = CGRect(x: reference.minX + CGFloat(column) * step,
                                  y: reference.minY + CGFloat(row) * step,
                                  width: outerSide, height: outerSide)
                if area.contains(cell), !widgets.contains(where: {
                    $0.insetBy(dx: 1, dy: 1).intersects(cell.insetBy(dx: 1, dy: 1))
                }) { choices.append(cell) }
            }
        }
        guard let cell = choices.min(by: {
            hypot($0.minX - currentTop.x, $0.minY - currentTop.y) <
                hypot($1.minX - currentTop.x, $1.minY - currentTop.y)
        }) else { return false }
        // Match the visible card inside the system window's eight-point padding.
        let side = outerSide - 14
        let frame = CGRect(x: cell.minX + 7, y: baseline - cell.minY - 7 - side,
                           width: side, height: side)
        model.fillsLeftSide = false
        placementBlocked = false
        model.layoutNotice = nil
        UserDefaults.standard.set(false, forKey: "widgetFullHeightOnLeft")
        applyLayoutLock()
        window.setFrame(frame, display: true)
        window.saveFrame(usingName: "GitLabDesktopWidget")
        let layout: [String: Any] = [
            "gridStep": step, "reference": NSStringFromRect(reference),
            "targetCell": NSStringFromRect(cell), "windowFrame": NSStringFromRect(frame),
            "visibleCardSide": side - 2
        ]
        if let data = try? JSONSerialization.data(withJSONObject: layout) {
            try? data.write(to: Bundle.main.bundleURL.deletingLastPathComponent()
                .appendingPathComponent(".widget-layout.json"), options: .atomic)
        }
        bringWidgetForward()
        return true
    }
}
