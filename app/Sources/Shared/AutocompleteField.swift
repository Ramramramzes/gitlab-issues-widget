import AppKit
import SwiftUI

struct AutocompleteSearchInput: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let onMove: (Int) -> Void
    let onSubmit: () -> Void
    let onCancel: () -> Void

    final class SearchField: NSSearchField {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window, self.window === window else { return }
                window.makeKeyAndOrderFront(nil)
                window.makeFirstResponder(self)
            }
        }
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: AutocompleteSearchInput
        init(_ parent: AutocompleteSearchInput) { self.parent = parent }
        func controlTextDidChange(_ notification: Notification) {
            if let field = notification.object as? NSTextField { parent.text = field.stringValue }
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch NSStringFromSelector(selector) {
            case "moveDown:": parent.onMove(1)
            case "moveUp:": parent.onMove(-1)
            case "insertNewline:": parent.onSubmit()
            case "cancelOperation:": parent.onCancel()
            default: return false
            }
            return true
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> SearchField {
        let field = SearchField()
        field.delegate = context.coordinator
        field.isBezeled = true
        field.drawsBackground = true
        field.focusRingType = .default
        field.sendsSearchStringImmediately = true
        field.font = .systemFont(ofSize: 13)
        field.textColor = .labelColor
        field.placeholderString = placeholder
        field.stringValue = text
        return field
    }
    func updateNSView(_ field: SearchField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
    }
}

private struct PopoverWindowLevel: NSViewRepresentable {
    func makeNSView(context: Context) -> LevelView { LevelView() }
    func updateNSView(_ view: LevelView, context: Context) {}

    final class LevelView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, !(window is DesktopPanel) else { return }
            // Apply the level after SwiftUI attaches the popover window.
            DispatchQueue.main.async { [weak self, weak window] in
                guard let window, self?.window === window, window.level < .normal else { return }
                window.level = .normal
            }
        }
    }
}

struct AutocompleteField: View {
    enum Selection {
        case single(Binding<String>)
        case multiple(Binding<Set<String>>)
    }

    let key: String
    let options: [AutocompleteOption]
    let selection: Selection
    var compact = false
    var onPresentationChange: (Bool) -> Void = { _ in }
    @State private var presented = false
    @State private var query = ""
    @State private var highlighted = 0

    private var label: String { tr(key) }
    private var matches: [AutocompleteOption] { AutocompleteOption.filtered(options, query: query) }
    private var selectedIDs: Set<String> {
        switch selection {
        case .single(let value): return [value.wrappedValue]
        case .multiple(let values): return values.wrappedValue
        }
    }
    private var selectedTitle: String {
        let ids = selectedIDs
        guard let first = options.first(where: { ids.contains($0.id) }) else { return label }
        return ids.count > 1 ? "\(first.title) +\(ids.count - 1)" : first.title
    }
    private var symbol: String {
        switch key {
        case "Проект": return "folder"
        case "Ветка": return "arrow.triangle.branch"
        case "Метки": return "tag"
        default: return "circle.lefthalf.filled"
        }
    }

    var body: some View {
        Button {
            query = ""
            highlighted = 0
            onPresentationChange(true)
            NSApp.activate(ignoringOtherApps: true)
            presented = true
        } label: {
            HStack(spacing: 7) {
                Image(systemName: symbol).symbolRenderingMode(.hierarchical).foregroundStyle(.secondary)
                Text(selectedTitle).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }.font(.system(size: compact ? 11 : 13))
                .frame(minHeight: compact ? 18 : 24)
                .contentShape(Rectangle())
        }.buttonStyle(AppleButtonStyle()).controlSize(.small)
            .accessibilityLabel("\(label): \(selectedTitle)")
            .help(tr("%@ — поиск по названию", label))
            .popover(isPresented: $presented, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 9) {
                    AutocompleteSearchInput(text: $query, placeholder: tr("Поиск: %@", label.lowercased()),
                                                onMove: { offset in highlighted = min(max(0, highlighted + offset), max(0, matches.count - 1)) },
                                                onSubmit: chooseHighlighted, onCancel: { presented = false })
                            .frame(height: 28)
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 3) {
                                ForEach(Array(matches.enumerated()), id: \.element.id) { index, option in
                                    Button { choose(option) } label: {
                                        HStack(spacing: 8) {
                                            if let color = option.color {
                                                Image(systemName: "tag.fill").foregroundStyle(Color.gitLabHex(color))
                                            }
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(option.title).font(.system(size: 12)).lineLimit(1)
                                                if !option.detail.isEmpty {
                                                    Text(option.detail).font(.system(size: 10)).foregroundStyle(.secondary)
                                                        .lineLimit(2).truncationMode(.middle)
                                                }
                                            }
                                            Spacer(minLength: 0)
                                            if selectedIDs.contains(option.id) { Image(systemName: "checkmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(.blue) }
                                        }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
                                            .background(index == highlighted ? .blue.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 10))
                                            .contentShape(Rectangle())
                                    }.buttonStyle(.plain).id(option.id).onHover { inside in if inside { highlighted = index } }
                                        .accessibilityAddTraits(selectedIDs.contains(option.id) ? .isSelected : [])
                                }
                                if matches.isEmpty { Text(tr("Ничего не найдено")).font(.caption).foregroundStyle(.secondary).padding(10) }
                            }
                        }.frame(height: min(240, max(44, CGFloat(matches.reduce(0) { $0 + ($1.detail.isEmpty ? 35 : 55) }))))
                            .onChange(of: highlighted) { value in
                                if matches.indices.contains(value) { proxy.scrollTo(matches[value].id) }
                            }
                    }
                }.padding(12).frame(width: 300).preferredColorScheme(.dark)
                    .background(PopoverWindowLevel().allowsHitTesting(false))
                    .onChange(of: query) { _ in highlighted = 0 }
            }
            .onChange(of: presented) { open in
                if !open { onPresentationChange(false) }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
                presented = false
            }
            .onDisappear { if presented { onPresentationChange(false) } }
    }

    private func chooseHighlighted() {
        guard matches.indices.contains(highlighted) else { return }
        choose(matches[highlighted])
    }

    private func choose(_ option: AutocompleteOption) {
        switch selection {
        case .single(let value):
            value.wrappedValue = option.id
            presented = false
        case .multiple(let values):
            values.wrappedValue = AutocompleteOption.toggling(option, in: values.wrappedValue, options: options)
        }
    }
}
