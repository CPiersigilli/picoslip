import AppKit
import SwiftUI
import PicoKit

/// The Tags dialog: names separated by ";", suggestions from every note
/// ranked by use; ↓/↑ + Enter picks one, Enter saves, Esc cancels.
final class TagEditorPanel: NSPanel {
    init(note: Note, catalog: [TagCount], anchor: NSRect?, save: @escaping (String) -> Void) {
        let size = CGSize(width: 340, height: 260)
        var origin = CGPoint(x: (NSScreen.main?.visibleFrame.midX ?? 600) - size.width / 2,
                             y: (NSScreen.main?.visibleFrame.midY ?? 400) - size.height / 2)
        if let anchor { origin = CGPoint(x: anchor.minX, y: anchor.maxY - size.height - 32) }
        super.init(contentRect: NSRect(origin: origin, size: size), styleMask: [.titled, .closable, .utilityWindow],
                   backing: .buffered, defer: false)
        title = note.title.map { "Tags – \($0)" } ?? "Tags"
        level = .floating
        isReleasedWhenClosed = false
        let current = Tags.names(note.tags).joined(separator: "; ")
        contentView = NSHostingView(rootView: TagEditorView(initial: current, catalog: catalog,
            save: { [weak self] tags in save(tags); self?.close() },
            cancel: { [weak self] in self?.close() }))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Tag editors are created in code") }

    func show() {
        NSApp.activate()
        makeKeyAndOrderFront(nil)
    }
}

struct TagEditorView: View {
    let initial: String
    let catalog: [TagCount]
    let save: (String) -> Void
    let cancel: () -> Void
    @State private var text = ""
    @State private var highlighted: Int?
    @State private var error: String?
    @FocusState private var focused: Bool

    /// The name being typed: what follows the last ";".
    private var prefix: String {
        let last = text.split(separator: ";", omittingEmptySubsequences: false).last.map(String.init) ?? ""
        var name = Substring(last).trimmingPrefix(while: \.isWhitespace)
        if name.first == "#" { name = name.dropFirst() }
        return String(name)
    }

    private var assigned: [String] {
        text.split(separator: ";").dropLast().map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private var suggestions: [TagCount] { Tags.suggest(catalog, prefix: prefix, assigned: assigned, limit: 8) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("work; project alpha", text: $text)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onChange(of: text) { highlighted = nil; error = nil }
                .onKeyPress(.downArrow) { move(1); return .handled }
                .onKeyPress(.upArrow) { move(-1); return .handled }
                .onSubmit(submit)
                .onExitCommand(perform: cancel)
            List(Array(suggestions.enumerated()), id: \.element.name) { index, item in
                HStack {
                    Text(item.name)
                    Spacer()
                    Text("\(item.uses)").foregroundStyle(.secondary).monospacedDigit()
                }
                .contentShape(Rectangle())
                .listRowBackground(index == highlighted ? Color.accentColor.opacity(0.25) : Color.clear)
                .onTapGesture { choose(item.name) }
            }
            .listStyle(.plain)
            .frame(minHeight: 120)
            if let error { Text(error).font(.callout).foregroundStyle(.red) }
            Text("Separate names with “;”. ↓/↑ and Enter choose a suggestion; Enter saves.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                Button("Save") { commit() }
            }
        }
        .padding(14)
        .onAppear { text = initial.isEmpty ? "" : initial + "; "; focused = true }
    }

    private func move(_ step: Int) {
        guard !suggestions.isEmpty else { return }
        let next = (highlighted ?? (step > 0 ? -1 : suggestions.count)) + step
        highlighted = min(max(next, 0), suggestions.count - 1)
    }

    private func submit() {
        if let highlighted, suggestions.indices.contains(highlighted) { choose(suggestions[highlighted].name) }
        else { commit() }
    }

    private func choose(_ name: String) {
        var parts = text.split(separator: ";", omittingEmptySubsequences: false).map(String.init)
        if parts.isEmpty { parts = [""] }
        parts[parts.count - 1] = (parts.count > 1 ? " " : "") + name
        text = parts.joined(separator: ";") + "; "
        highlighted = nil
        focused = true
    }

    private func commit() {
        guard let tags = Tags.normalize(text) else {
            error = "Use up to 24 names of at most 63 characters, without quotes or # inside a name."
            return
        }
        save(tags)
    }
}
