import SwiftUI

/// How notes look on screen. A Mac-only preference: it never changes what is
/// written to the archive, which stays identical to the Windows app's.
nonisolated enum NoteStyle: String, CaseIterable, Sendable {
    /// Rounded card, soft shadow, controls on the left shown on hover.
    case mac
    /// The Windows look: square card, 1-pixel ink outline, − and × on the right.
    case windows

    static let storageKey = "noteStyle"

    static var current: NoteStyle {
        UserDefaults.standard.string(forKey: storageKey).flatMap(NoteStyle.init(rawValue:)) ?? .mac
    }

    var label: String {
        switch self {
        case .mac: "Mac"
        case .windows: "Windows"
        }
    }

    var barHeight: CGFloat { self == .mac ? 28 : 32 }
    var cornerRadius: CGFloat { self == .mac ? 12 : 0 }

    /// Windows types in bold Consolas, so new text there is bold; the Mac style
    /// types in the regular system face. Saved RTF keeps each run's real effects.
    var typesBold: Bool { self == .windows }

    /// Space around the text inside the card (paint_note() on Windows).
    var textInsets: NSEdgeInsets {
        self == .mac ? NSEdgeInsets(top: 2, left: 12, bottom: 12, right: 12)
                     : NSEdgeInsets(top: 6, left: 10, bottom: 10, right: 10)
    }

    var titleFont: Font {
        self == .mac ? .system(size: 13, weight: .semibold) : .system(size: 13, weight: .bold, design: .monospaced)
    }
}

/// The style choice, as used in the menu-bar menu and the note's context menu.
struct NoteStylePicker: View {
    @AppStorage(NoteStyle.storageKey) private var style: NoteStyle = .mac

    var body: some View {
        Picker("Note style", selection: $style) {
            ForEach(NoteStyle.allCases, id: \.self) { Text($0.label).tag($0) }
        }
    }
}
