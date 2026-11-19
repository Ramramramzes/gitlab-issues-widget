import AppKit
import SwiftUI

final class DesktopPanel: NSPanel {
    var allowsMainWindow = false
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { allowsMainWindow }
}

@MainActor
func glassHostingView<Content: View>(_ content: Content) -> NSView {
    let hosting = NSHostingView(rootView: content)
    hosting.autoresizingMask = [.width, .height]
    // Look up the public AppKit class at runtime so older SDKs can build the app.
    if #available(macOS 26.0, *), let glassClass = NSClassFromString("NSGlassEffectView") as? NSView.Type {
        let glass = glassClass.init(frame: .zero)
        // The system's default regular glass is suitable for the whole panel.
        glass.setValue(24.0, forKey: "cornerRadius")
        glass.setValue(false, forKey: "effectIsInteractive")
        glass.setValue(hosting, forKey: "contentView")
        glass.appearance = NSAppearance(named: .darkAqua)
        return glass
    }
    let glass = NSVisualEffectView()
    glass.material = .hudWindow
    glass.blendingMode = .behindWindow
    // The autocomplete popover takes keyboard focus from the panel.
    glass.state = .active
    glass.appearance = NSAppearance(named: .darkAqua)
    glass.wantsLayer = true
    glass.layer?.cornerRadius = 24
    glass.layer?.masksToBounds = true
    glass.addSubview(hosting)
    return glass
}
