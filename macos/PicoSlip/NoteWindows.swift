import AppKit
import SwiftUI
import PicoKit

/// Owns the open note panels: creation, cascading and collapse.
final class NoteWindows {
    static let size = NSSize(width: 300, height: 240)   // "Medium", as on Windows

    private var panels: [String: NotePanel] = [:]
    private var nextColor = 0
    private var palette = Palette.pastel

    func newNote() {
        guard let id = freeID() else { return }
        let note = Note(id: id, palette: palette, color: nextColor)
        let panel = NotePanel(note: note, frame: cascadedFrame(step: nextColor % 7))
        panel.onClose = { [weak self] in self?.panels[id] = nil }
        panels[id] = panel
        nextColor = (nextColor + 1) % Palette.colorCount
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    /// First free suffix for this millisecond, like new_note(). Files join the check
    /// once notes are saved.
    private func freeID() -> String? {
        let now = Date.now
        for suffix in 0..<10_000 {
            if let id = NoteID.make(date: now, suffix: suffix), panels[id] == nil { return id }
        }
        return nil
    }

    /// Windows places new notes at 100 + n * 28 pixels from the top-left corner.
    private func cascadedFrame(step: Int) -> NSRect {
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let offset = 100 + CGFloat(step) * 28
        return NSRect(x: visible.minX + offset, y: visible.maxY - offset - Self.size.height,
                      width: Self.size.width, height: Self.size.height)
    }
}

/// Borderless floating panel; SwiftUI draws the card, its outline and title bar.
final class NotePanel: NSPanel {
    var onClose: (() -> Void)?
    private let note: Note
    private var expandedHeight: CGFloat

    init(note: Note, frame: NSRect) {
        self.note = note
        expandedHeight = frame.height
        super.init(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        hasShadow = true
        isOpaque = false
        backgroundColor = .clear
        contentView = NSHostingView(rootView: NoteView(
            note: note,
            onToggle: { [weak self] in self?.toggleCollapsed() },
            onClose: { [weak self] in self?.close() },
            onStyleChange: { [weak self] in self?.fitCollapsedHeight() }))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Note panels are created in code") }

    // Borderless windows refuse keyboard focus unless asked.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func close() {
        super.close()
        onClose?()
    }

    /// Collapsing keeps only the title bar and the top edge in place.
    private func toggleCollapsed() {
        if !note.collapsed { expandedHeight = frame.height }
        note.collapsed.toggle()
        setHeight(note.collapsed ? NoteStyle.current.barHeight : expandedHeight)
    }

    /// The two styles have different title bars; a collapsed note follows.
    private func fitCollapsedHeight() {
        if note.collapsed { setHeight(NoteStyle.current.barHeight) }
    }

    private func setHeight(_ height: CGFloat) {
        var frame = self.frame
        frame.origin.y += frame.height - height
        frame.size.height = height
        setFrame(frame, display: true, animate: false)
    }
}
