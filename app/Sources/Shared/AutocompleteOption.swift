import Foundation

struct AutocompleteOption: Identifiable, Equatable {
    let id: String
    let title: String
    var detail = ""
    var color: String?
    var scope: String?

    static func filtered(_ options: [AutocompleteOption], query: String) -> [AutocompleteOption] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? options : options.filter {
            $0.title.localizedStandardContains(query) || $0.detail.localizedStandardContains(query)
        }
    }

    static func toggling(_ option: AutocompleteOption, in selection: Set<String>, options: [AutocompleteOption]) -> Set<String> {
        var updated = selection
        if updated.remove(option.id) == nil {
            if let scope = option.scope { updated.subtract(options.filter { $0.scope == scope }.map(\.id)) }
            updated.insert(option.id)
        }
        return updated
    }
}
