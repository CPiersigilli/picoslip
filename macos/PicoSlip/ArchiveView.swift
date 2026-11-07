import AppKit
import SwiftUI
import PicoKit

/// The "Browse notes" window, created on demand and kept for reuse.
final class ArchiveWindowController {
    static let shared = ArchiveWindowController()
    let model = ArchiveModel()
    private var window: NSWindow?

    func show(focusSearch: Bool) {
        if window == nil {
            let hosting = NSHostingController(rootView: ArchiveView(model: model))
            hosting.sceneBridgingOptions = [.toolbars, .title]
            let window = NSWindow(contentViewController: hosting)
            window.title = "PicoSlip Archive"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(CGSize(width: 980, height: 640))
            window.isReleasedWhenClosed = false
            window.setFrameAutosaveName("PicoSlipArchive")
            if !window.setFrameUsingName("PicoSlipArchive") { window.center() }
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        if focusSearch { model.focusRequest += 1 }
    }
}

struct ArchiveView: View {
    @Bindable var model: ArchiveModel
    private let store = NoteStore.shared
    @FocusState private var searchFocused: Bool
    @State private var pendingDelete: [String] = []
    @State private var lastClicked: String?

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
        } detail: {
            mosaic
        }
        .searchable(text: $model.query, placement: .toolbar, prompt: "Words, \"phrase\", #tag, -#")
        .searchFocused($searchFocused)
        .toolbar {
            ToolbarItemGroup {
                Button { model.reload() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    .help("Reload notes changed outside PicoSlip (⌘R or F5)")
                    .keyboardShortcut("r")
                Menu {
                    Button("Move current archive…") { chooseArchive(move: true) }
                    Button("Open or create archive…") { chooseArchive(move: false) }
                    Divider()
                    Button("Show in Finder") { store.revealArchive() }
                } label: { Label("Archive", systemImage: "folder") }
                    .help(store.folder.url.path)
            }
        }
        .background {
            // ⌘F focuses the search field; F5 reloads, as on Windows.
            Button("") { searchFocused = true }.keyboardShortcut("f").hidden()
            Button("") { model.reload() }.keyboardShortcut(KeyEquivalent(Character(UnicodeScalar(UInt32(NSF5FunctionKey))!)), modifiers: [])
                .hidden()
        }
        .onAppear { model.reload(); model.startWatching() }
        .onDisappear { model.stopWatching() }
        .onChange(of: store.revision) { model.reload() }
        .onChange(of: store.folder) { model.reload(); model.startWatching() }
        .onChange(of: model.focusRequest) { searchFocused = true }
        .confirmationDialog(pendingDelete.count == 1 ? "Delete this note?" : "Delete \(pendingDelete.count) notes?",
                            isPresented: Binding(get: { !pendingDelete.isEmpty }, set: { if !$0 { pendingDelete = [] } })) {
            Button("Delete", role: .destructive) {
                store.delete(pendingDelete)
                model.selection.subtract(pendingDelete)
                pendingDelete = []
            }
        } message: {
            Text("The TXT and RTF files and their settings are removed from the archive. This cannot be undone.")
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $model.mode) {
                ForEach(SidebarMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(10)
            switch model.mode {
            case .tags:
                List(selection: $model.tag) {
                    row("All notes", model.notes.count).tag(String?.none)
                    ForEach(model.catalog, id: \.name) { item in
                        row(item.name, item.uses).tag(Optional(item.name))
                    }
                }
            case .date:
                List(model.dates, children: \.children, selection: $model.date) { node in
                    row(node.label, node.count)
                }
            }
        }
    }

    private func row(_ label: String, _ count: Int) -> some View {
        HStack {
            Text(label).lineLimit(1)
            Spacer()
            Text("\(count)").foregroundStyle(.secondary).monospacedDigit()
        }
    }

    // MARK: Mosaic

    private var mosaic: some View {
        ScrollView {
            if let error = model.error {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary).padding()
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 340), spacing: 14, alignment: .top)], spacing: 14) {
                ForEach(model.results) { result in
                    NoteCard(result: result, selected: model.selection.contains(result.id)) { name in
                        model.mode = .tags
                        model.tag = name
                    }
                    .onTapGesture { click(result.id) }
                    .contextMenu {
                        Button("Open") { store.showArchived(result.id) }
                        Button("Delete…", role: .destructive) {
                            pendingDelete = model.selection.contains(result.id) ? Array(model.selection) : [result.id]
                        }
                    }
                }
            }
            .padding(16)
        }
        .overlay {
            if model.results.isEmpty && model.error == nil {
                ContentUnavailableView(model.notes.isEmpty ? "No notes yet" : "No matching notes",
                                       systemImage: "note.text",
                                       description: Text(model.notes.isEmpty ? "Notes you write appear here." : "Try other words or another filter."))
            }
        }
    }

    /// Click reopens a note; ⌘-click and ⇧-click select, as Ctrl/Shift on Windows.
    private func click(_ id: String) {
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            if model.selection.contains(id) { model.selection.remove(id) } else { model.selection.insert(id) }
            lastClicked = id
        } else if flags.contains(.shift), let anchor = lastClicked,
                  let from = model.results.firstIndex(where: { $0.id == anchor }),
                  let to = model.results.firstIndex(where: { $0.id == id }) {
            model.selection = Set(model.results[min(from, to)...max(from, to)].map(\.id))
        } else {
            model.selection = [id]
            lastClicked = id
            store.showArchived(id)
        }
    }

    private func chooseArchive(move: Bool) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = move ? "Move Here" : "Open"
        panel.message = move ? "Choose an empty folder. Notes, formatting and tags move there."
                             : "Choose a folder to use as the archive. The current archive stays where it is."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.changeArchive(to: ArchiveFolder(url: url), move: move)
    }
}

/// One post-it of the mosaic, in its own colors.
private struct NoteCard: View {
    let result: ArchiveResult
    let selected: Bool
    let selectTag: (String) -> Void

    private var note: ArchivedNote { result.note }
    private var paper: Color { Color(note.palette.card(note.color)) }
    private var ink: Color { Color(note.palette.ink(note.color)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title = note.title {
                Text(title).font(.system(size: 12, weight: .bold, design: .monospaced)).lineLimit(1)
            }
            Group {
                if let excerpt = result.excerpt { Text(highlighted(excerpt)) } else { Text(String(note.body.prefix(600))) }
            }
            .font(.system(size: 11, design: .monospaced))
            .lineLimit(9)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            Spacer(minLength: 0)
            if !note.tags.isEmpty {
                HStack(spacing: 6) {
                    Rectangle().fill(ink).frame(width: 2, height: 14)
                    ForEach(Tags.names(note.tags), id: \.self) { name in
                        Button(name) { selectTag(name) }.buttonStyle(.plain).font(.caption)
                    }
                }
                .lineLimit(1)
            }
        }
        .foregroundStyle(ink)
        .padding(12)
        .frame(height: 190, alignment: .topLeading)
        .background(paper, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(selected ? Color.accentColor : ink.opacity(0.15), lineWidth: selected ? 3 : 0.5)
        }
        .contentShape(Rectangle())
    }

    private func highlighted(_ excerpt: Excerpt) -> AttributedString {
        var match = AttributedString(excerpt.match)
        match.backgroundColor = .yellow.opacity(0.6)
        match.foregroundColor = .black
        return AttributedString(excerpt.before) + match + AttributedString(excerpt.after)
    }
}
