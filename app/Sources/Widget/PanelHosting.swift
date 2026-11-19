import AppKit
import SwiftUI

final class DesktopPanel: NSPanel {
    var allowsMainWindow = false
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { allowsMainWindow }

    convenience init(contentRect: NSRect, styleMask: NSWindow.StyleMask) {
        self.init(contentRect: contentRect, styleMask: styleMask, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        // The glass view defines the visible outline of the panel.
        hasShadow = false
    }
}

@MainActor
func glassHostingView<Content: View>(_ content: Content) -> NSView {
    let cornerRadius: CGFloat = 24
    let hosting = NSHostingView(rootView: content)
    hosting.autoresizingMask = [.width, .height]
    let backdrop: NSView

    // Look up the public AppKit class at runtime so older SDKs can build the app.
    if #available(macOS 26.0, *), let glassClass = NSClassFromString("NSGlassEffectView") as? NSView.Type {
        let glass = glassClass.init(frame: .zero)
        // The system's default regular glass is suitable for the whole panel.
        glass.setValue(cornerRadius, forKey: "cornerRadius")
        glass.setValue(false, forKey: "effectIsInteractive")
        glass.setValue(hosting, forKey: "contentView")
        backdrop = glass
    } else {
        let glass = NSVisualEffectView()
        glass.material = .hudWindow
        glass.blendingMode = .behindWindow
        // Keep the blur active while the autocomplete popover has keyboard focus.
        glass.state = .active
        glass.addSubview(hosting)
        backdrop = glass
    }

    backdrop.appearance = NSAppearance(named: .darkAqua)
    backdrop.wantsLayer = true
    backdrop.layer?.cornerRadius = cornerRadius
    backdrop.layer?.cornerCurve = .continuous
    backdrop.layer?.masksToBounds = true
    return backdrop
}
