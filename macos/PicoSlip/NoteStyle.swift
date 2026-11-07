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

    /// Windows draws all text in bold Consolas; the Mac style uses the system face.
    /// Only the display changes: saved formatting keeps the Windows meaning.
    var bodyFont: NSFont {
        self == .mac ? .systemFont(ofSize: 13) : .monospacedSystemFont(ofSize: 13, weight: .bold)
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
