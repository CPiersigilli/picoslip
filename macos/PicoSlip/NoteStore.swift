import AppKit
import SwiftUI
import PicoKit

/// Where the archive lives: ~/Library/Application Support/PicoSlip/notes by
/// default, or the folder written in archive.path beside it (UTF-8 path).
enum ArchiveConfig {
    static let support = URL.applicationSupportDirectory.appending(path: "PicoSlip")
    static let configURL = support.appending(path: "archive.path")
    static let defaultFolder = ArchiveFolder(url: support.appending(path: "notes"))

    /// The configured folder, and whether it is missing (never silently replaced).
    static func load() -> (folder: ArchiveFolder, missing: Bool) {
        guard let path = try? String(contentsOf: configURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else { return (defaultFolder, false) }
        var directory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &directory) && directory.boolValue
        return exists ? (ArchiveFolder(url: URL(filePath: path, directoryHint: .isDirectory)), false) : (defaultFolder, true)
    }

    static func save(_ folder: ArchiveFolder) throws {
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try Data(folder.url.path.utf8).write(to: configURL, options: .atomic)
    }
}

/// Every open note and the archive they belong to.
@Observable
final class NoteStore {
    static let shared = NoteStore()

    private(set) var folder: ArchiveFolder
    private(set) var palette = Palette.pastel
    /// Bumped whenever archive files change, so the browser can refresh.
    private(set) var revision = 0

    @ObservationIgnored private var nextColor = 0
    @ObservationIgnored private var panels: [String: NotePanel] = [:]
    @ObservationIgnored private var tagEditor: TagEditorPanel?

    private init() {
        let configured = ArchiveConfig.load()
        folder = configured.folder
        if configured.missing {
            Task { @MainActor in
                Self.alert("The configured notes archive is not available.",
                           "PicoSlip is using the default archive for now and will look for the other folder again next time.")
            }
        }
    }

    // MARK: Starting and restoring

    /// Restores the notes left open; the very first start opens an empty note.
    func start(firstRun: Bool = true) {
        do { try folder.create() } catch { Self.report(error) }
        let ini = settings()
        palette = Palette(rawValue: ini.int("app", "palette", default: 0)) ?? .pastel
        nextColor = max(0, min(ini.int("app", "next_color", default: 0), Palette.colorCount - 1))
        let ids = (try? folder.noteIDs()) ?? []
        for id in ids where ini.int(id, "open", default: 1) != 0 { open(id, ini: ini)?.show() }
        if firstRun && ids.isEmpty { newNote() }
    }

    func settings() -> IniFile { (try? folder.loadSettings()) ?? IniFile() }

    /// Read, change and write notes.ini in one step, so edits made meanwhile
    /// by another program (or the Windows app on a shared folder) survive.
    private func updateSettings(_ change: (IniFile) -> Void) throws {
        let ini = try folder.loadSettings()
        change(ini)
        try folder.saveSettings(ini)
    }

    // MARK: Notes

    func newNote() {
        let now = Date.now
        guard let id = (0..<10_000).lazy.compactMap({ NoteID.make(date: now, suffix: $0) })
            .first(where: { self.panels[$0] == nil && !self.folder.exists($0) }) else { return }
        let note = Note(id: id, palette: palette, color: nextColor)
        let step = CGFloat(nextColor % 7) * 28
        nextColor = (nextColor + 1) % Palette.colorCount
        let size = NoteSize.presets[NoteSize.medium].size
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = NSRect(x: visible.minX + 100 + step, y: visible.maxY - 100 - step - size.height,
                           width: size.width, height: size.height)
        let panel = NotePanel(note: note, frame: frame, store: self)
        panels[id] = panel
        panel.show()
    }

    /// Opens a saved note (open_note() with restore).
    @discardableResult
    func open(_ id: String, ini: IniFile? = nil) -> NotePanel? {
        if let panel = panels[id] { return panel }
        let ini = ini ?? settings()
        guard let stored = try? folder.readText(id) else { return nil }
        let palette = Palette(rawValue: ini.int(id, "palette", default: 0)) ?? .pastel
        let color = ini.int(id, "color", default: 0)
        let note = Note(id: id, palette: palette, color: (0..<Palette.colorCount).contains(color) ? color : 0)
        let split = NoteText.split(stored, hasTitleFlag: ini.int(id, "has_title", default: 0) != 0)
        let body = NoteText.editorText(split.body)
        note.title = split.title
        note.tags = Tags.normalize(ini.string(id, "tags") ?? "") ?? ""
        note.collapsed = ini.int(id, "collapsed", default: 0) != 0
        let opacity = ini.int(id, "opacity", default: 100)
        note.opacity = (60...100).contains(opacity) ? opacity : 100
        let size = ini.int(id, "size", default: NoteSize.medium)
        note.size = NoteSize.presets.indices.contains(size) ? size : NoteSize.medium
        let preset = NoteSize.presets[note.size].size
        let width = CGFloat(max(Int(NoteSize.minimum.width), min(ini.int(id, "width", default: Int(preset.width)), 4096)))
        let height = CGFloat(max(Int(NoteSize.minimum.height), min(ini.int(id, "height", default: Int(preset.height)), 4096)))
        if width != preset.width || height != preset.height { note.size = -1 }
        note.persisted = true

        let style = NoteStyle.current
        let ink = NSColor(Color(palette.ink(note.color)))
        let runs = folder.readRich(id).flatMap { RichTextBridge.read($0, body: body) }
            ?? [RichRun(text: body, bold: style.typesBold)]
        note.storage.setAttributedString(RichTextBridge.attributed(runs, style: style, ink: ink))

        let panel = NotePanel(note: note, frame: frame(for: id, ini: ini, size: CGSize(width: width, height: height)), store: self)
        panels[id] = panel
        return panel
    }

    /// Stored Mac position, kept fully on a visible screen. A note last placed
    /// on Windows starts from its Windows position, which uses the same
    /// top-left origin on the primary screen.
    private func frame(for id: String, ini: IniFile, size: CGSize) -> NSRect {
        let top = NSScreen.screens.first?.frame.maxY ?? size.height
        let x = CGFloat(ini.int(id, "mac_x", default: ini.int(id, "x", default: 100)))
        let y = top - CGFloat(ini.int(id, "mac_y", default: ini.int(id, "y", default: 100))) - size.height
        var frame = NSRect(x: x, y: y, width: size.width, height: size.height)
        let screen = NSScreen.screens.first { $0.visibleFrame.intersects(frame) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            frame.size.width = min(frame.width, visible.width)
            frame.size.height = min(frame.height, visible.height)
            frame.origin.x = max(visible.minX, min(frame.minX, visible.maxX - frame.width))
            frame.origin.y = max(visible.minY, min(frame.minY, visible.maxY - frame.height))
        }
        return frame
    }

    /// Opens or brings forward a note from the archive, expanded.
    func showArchived(_ id: String) {
        guard let panel = open(id) else {
            Self.alert("The note could not be opened.", "Its file may have been moved, deleted or changed outside PicoSlip.")
            return
        }
        if panel.note.collapsed { panel.expand() }
        panel.show()
        save(panel.note)
    }

    /// save_note(): TXT and RTF when the text changed, layout and tags always.
    /// An empty note leaves no files and no notes.ini section.
    @discardableResult
    func save(_ note: Note, open: Bool = true) -> Bool {
        guard let panel = panels[note.id] else { return false }
        do {
            if !note.hasContent {
                if note.persisted {
                    try folder.remove(note.id)
                    try updateSettings { $0.removeSection(note.id) }
                    note.persisted = false
                    revision += 1
                }
                note.textDirty = false
                note.saveFailed = false
                return true
            }
            var changed = note.tagsDirty
            if note.textDirty || !note.persisted {
                let body = NoteText.storedText(note.storage.string)
                guard let text = NoteText.encode(title: note.title, body: body) else { throw ArchiveError.invalidText(note.id) }
                try folder.write(note.id, text: text, rich: RichTextWriter.rtf(RichTextBridge.runs(note.storage)))
                note.persisted = true
                note.textDirty = false
                changed = true
            }
            let position = panel.macPosition, size = panel.savedSize
            try updateSettings { ini in
                let id = note.id
                ini.set(id, "color", note.color)
                ini.set(id, "has_title", note.title == nil ? 0 : 1)
                ini.set(id, "collapsed", note.collapsed ? 1 : 0)
                ini.set(id, "open", open ? 1 : 0)
                ini.set(id, "palette", note.palette.rawValue)
                ini.set(id, "size", note.size)
                ini.set(id, "opacity", note.opacity)
                ini.set(id, "width", Int(size.width.rounded()))
                ini.set(id, "height", Int(size.height.rounded()))
                ini.set(id, "mac_x", position.x)
                ini.set(id, "mac_y", position.y)
                if note.tagsDirty {
                    if note.tags.isEmpty { ini.set(id, "tags", nil) } else { ini.makeUnicode(); ini.set(id, "tags", note.tags) }
                }
                ini.set("app", "next_color", nextColor)
            }
            note.tagsDirty = false
            note.saveFailed = false
            if changed { revision += 1 }
            return true
        } catch {
            note.saveFailed = true
            return false
        }
    }

    /// × closes a note: saved, kept in the archive, not reopened at start.
    func close(_ note: Note) {
        save(note, open: false)
        panels.removeValue(forKey: note.id)?.dismiss()
    }

    func saveAll() {
        for panel in panels.values { save(panel.note) }
    }

    /// Deletes notes from the archive (Browse notes → Delete).
    func delete(_ ids: [String]) {
        do {
            for id in ids {
                panels.removeValue(forKey: id)?.dismiss()
                try folder.remove(id)
            }
            try updateSettings { ini in ids.forEach(ini.removeSection) }
        } catch { Self.report(error) }
        revision += 1
    }

    func refresh() { revision += 1 }

    // MARK: Preferences and archive location

    func setPalette(_ palette: Palette) {
        do {
            try updateSettings { ini in
                ini.set("app", "palette", palette.rawValue)
                ini.set("app", "next_color", 0)
            }
            self.palette = palette
            nextColor = 0
        } catch { Self.alert("The palette preference could not be saved.", error.localizedDescription) }
    }

    func revealArchive() { NSWorkspace.shared.open(folder.url) }

    /// Move current archive, or open/create another one (location_change()).
    func changeArchive(to target: ArchiveFolder, move: Bool) {
        guard target != folder else { return }
        saveAll()
        do {
            if move { try ArchiveLocation.move(folder, to: target) } else { try target.create() }
            try ArchiveConfig.save(target)
        } catch {
            Self.alert(move ? "The archive could not be moved." : "The archive could not be opened.", error.localizedDescription)
            return
        }
        for panel in panels.values { panel.dismiss() }
        panels.removeAll()
        folder = target
        start(firstRun: false)
        revision += 1
    }

    // MARK: Tags

    func tagCatalog() -> [TagCount] {
        let ini = settings()
        var lists = ini.sectionNames.compactMap { ini.string($0, "tags") }.compactMap(Tags.normalize)
        for panel in panels.values where panel.note.tagsDirty { lists.append(panel.note.tags) }
        return Tags.catalog(lists)
    }

    func editTags(_ note: Note) {
        tagEditor?.close()
        let editor = TagEditorPanel(note: note, catalog: tagCatalog(), anchor: panels[note.id]?.frame) { [weak self] tags in
            note.tags = tags
            note.tagsDirty = true
            self?.save(note)
        }
        tagEditor = editor
        editor.show()
    }

    // MARK: Messages

    static func alert(_ message: String, _ detail: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        NSApp.activate()
        alert.runModal()
    }

    static func report(_ error: Error) { alert("PicoSlip could not complete the operation.", error.localizedDescription) }
}
