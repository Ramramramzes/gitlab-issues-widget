import SwiftUI

struct AppleButtonStyle: ButtonStyle {
    var tint: Color = .primary
    var prominent = false
    var iconOnly = false

    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        Surface(configuration: configuration, tint: tint, prominent: prominent, iconOnly: iconOnly)
    }

    private struct Surface: View {
        let configuration: ButtonStyleConfiguration
        let tint: Color
        let prominent: Bool
        let iconOnly: Bool
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovered = false

        var body: some View {
            configuration.label
                .padding(.horizontal, iconOnly ? 0 : 12)
                .padding(.vertical, iconOnly ? 0 : 7)
                .frame(width: iconOnly ? 30 : nil, height: iconOnly ? 30 : nil)
                .foregroundStyle(prominent ? .white : tint)
                .background {
                    Capsule().fill(prominent ? tint.opacity(configuration.isPressed ? 0.7 : hovered ? 1 : 0.9) :
                        Color.primary.opacity(configuration.isPressed ? 0.18 : hovered ? 0.12 : 0.065))
                }
                .contentShape(Capsule())
                .opacity(isEnabled ? 1 : 0.4)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .onHover { hovered = $0 }
                .animation(.easeOut(duration: 0.12), value: hovered)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }
    }
}

struct WidgetIconButton: View {
    let title: String
    let symbol: String
    var tint: Color = .secondary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .frame(width: 17, height: 20)
        }
        .buttonStyle(AppleButtonStyle(tint: tint, iconOnly: true))
        .controlSize(.small)
        .accessibilityLabel(title)
        .help(title)
    }
}

extension Color {
    static func gitLabHex(_ value: String) -> Color {
        let hex = value.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard hex.count == 6, let rgb = UInt32(hex, radix: 16) else { return .gray }
        return Color(red: Double((rgb >> 16) & 255) / 255, green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255)
    }
}
