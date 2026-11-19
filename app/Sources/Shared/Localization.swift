import Foundation

enum WidgetLanguage: String, CaseIterable {
    case russian = "ru"
    case english = "en"

    static let preferenceKey = "widgetLanguage"
    private static let englishBundle = Bundle.main.url(forResource: "en", withExtension: "lproj").flatMap(Bundle.init(url:))

    static var current: Self {
        UserDefaults.standard.string(forKey: preferenceKey).flatMap(Self.init(rawValue:)) ?? .russian
    }

    var name: String { self == .russian ? "Русский" : "English" }

    func translation(for key: String) -> String {
        guard self == .english else { return key }
        return Self.englishBundle?.localizedString(forKey: key, value: key, table: nil) ?? key
    }
}

func tr(_ key: String, _ arguments: CVarArg...) -> String {
    let format = WidgetLanguage.current.translation(for: key)
    return arguments.isEmpty ? format : String(format: format, arguments: arguments)
}

struct WidgetMessage: ExpressibleByStringLiteral {
    private let render: () -> String

    init(_ render: @escaping () -> String) { self.render = render }
    init(stringLiteral value: String) { self.init { tr(value) } }

    var text: String { render() }
}
