import AppKit
import Observation
import PicoKit

/// Sizes and opacities of the "Note size" and "Opacity" menus (src/picoslip.c).
enum NoteSize {
    static let presets: [(name: String, size: CGSize)] = [
        ("Small", CGSize(width: 240, height: 180)), ("Medium", CGSize(width: 300, height: 240)),
        ("Large", CGSize(width: 420, height: 340)), ("Extra large", CGSize(width: 540, height: 440)),
        ("Square", CGSize(width: 300, height: 300))
    ]
    static let medium = 1
    static let minimum = CGSize(width: 160, height: 100)
    static let maximum: CGFloat = 4096
    static let opacities = [100, 90, 80, 70, 60]
}

/// One sticky note. The text storage is shared with its editor and is the
/// single source of the body; everything else mirrors a notes.ini key.
@Observable
final class Note {
    let id: String
    var palette: Palette
    var color: Int
    var title: String?
    var tags = ""
    var collapsed = false
    var opacity = 100
    /// Index into NoteSize.presets, or -1 for a custom size.
    var size = NoteSize.medium
    var saveFailed = false
    /// The title bar shows its editor (double-click or "Edit title").
    var editingTitle = false

    @ObservationIgnored let storage = NSTextStorage()
    @ObservationIgnored var persisted = false
    @ObservationIgnored var textDirty = false
    @ObservationIgnored var tagsDirty = false

    init(id: String, palette: Palette, color: Int) {
        self.id = id
        self.palette = palette
        self.color = color
    }

    /// note_has_content(): a title, or any non-blank character.
    var hasContent: Bool {
        title != nil || storage.string.unicodeScalars.contains { !$0.properties.isWhitespace }
    }
}
