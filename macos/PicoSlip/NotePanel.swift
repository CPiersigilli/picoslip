import AppKit
import SwiftUI
import PicoKit

/// A floating, borderless, resizable note window. It owns the editor and
/// applies every window-level rule of the Windows app.
final class NotePanel: NSPanel, NSWindowDelegate, NoteEditorOwner {
    let note: Note
    let editor: NoteEditor
    private let scroll: NSScrollView
    private unowned let store: NoteStore
    private var expandedHeight: CGFloat
    private var wheel: CGFloat = 0
    private var saveTask: Task<Void, Never>?

    init(note: Note, frame: NSRect, store: NoteStore) {
        self.note = note
        self.store = store
        scroll = NoteEditor.make(storage: note.storage)
        editor = scroll.documentView as! NoteEditor
        expandedHeight = frame.height
        super.init(contentRect: frame, styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
        delegate = self
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        hasShadow = true
        isOpaque = false
        backgroundColor = .clear
        minSize = NoteSize.minimum
        maxSize = CGSize(width: NoteSize.maximum, height: NoteSize.maximum)
        alphaValue = CGFloat(note.opacity) / 100
        editor.owner = self
        editor.resetTypingAttributes(bold: style.typesBold)
        contentView = NSHostingView(rootView: NoteView(note: note, editor: scroll, actions: NoteActions(
            toggleCollapsed: { [weak self] in self?.toggleCollapsed() },
            close: { [weak self] in self.map { $0.store.close($0.note) } },
            menu: { [weak self] in self?.makeMenu() ?? NSMenu() },
            setTitle: { [weak self] in self?.setTitle($0) },
            styleChanged: { [weak self] in self?.applyStyle() })))
        if note.collapsed { applyCollapsed() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Note panels are created in code") }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func show() {
        NSApp.activate()
        makeKeyAndOrderFront(nil)
        if !note.collapsed { makeFirstResponder(editor) }
    }

    /// Closes the window without saving; the store decides what to persist.
    func dismiss() {
        saveTask?.cancel()
        super.close()
    }

    // MARK: NoteEditorOwner

    var style: NoteStyle { NoteStyle.current }
    var ink: NSColor { NSColor(Color(note.palette.ink(note.color))) }

    var textAreaSize: CGSize {
        textArea(for: CGSize(width: frame.width, height: note.collapsed ? expandedHeight : frame.height))
    }

    func textArea(for size: CGSize) -> CGSize {
        let insets = style.textInsets
        let bar = style.barHeight + (style == .windows ? 1 : 0)
        return CGSize(width: size.width - insets.left - insets.right,
                      height: size.height - bar - insets.top - insets.bottom)
    }

    func editorDidChange(text: Bool) {
        note.textDirty = true
        scheduleSave()
    }

    func editorPromotedTitle(_ title: String) {
        note.title = title
        note.textDirty = true
    }

    func editorRequestsTags() { store.editTags(note) }
    func editorRequestsSearch() { ArchiveWindowController.shared.show(focusSearch: true) }

    // MARK: Saving

    func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard let self, !Task.isCancelled else { return }
            self.store.save(self.note)
        }
    }

    /// Position on the Mac: top-left corner, measured from the top-left of the
    /// main screen. Windows keeps its own x and y.
    var macPosition: (x: Int, y: Int) {
        let top = NSScreen.screens.first?.frame.maxY ?? frame.maxY
        return (Int(frame.minX.rounded()), Int((top - frame.maxY).rounded()))
    }

    var savedSize: CGSize { CGSize(width: frame.width, height: note.collapsed ? expandedHeight : frame.height) }

    // MARK: Size, wheel and resize

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        guard !note.collapsed else { return frame.size }
        return editor.fits(note.storage, in: textArea(for: frameSize)) ? frameSize : frame.size
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        note.size = -1
        expandedHeight = frame.height
        scheduleSave()
    }

    func windowDidMove(_ notification: Notification) { scheduleSave() }

    /// ⌘ + scroll wheel scales the note by 10% per notch, keeping its proportions.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .scrollWheel, event.modifierFlags.contains(.command) {
            guard !note.collapsed else { return }
            wheel += event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / 12 : event.scrollingDeltaY
            while abs(wheel) >= 1 {
                let grow = wheel > 0
                wheel -= grow ? 1 : -1
                let width = grow ? frame.width * 1.1 : frame.width / 1.1
                if !resize(to: CGSize(width: width, height: frame.height * width / frame.width), preset: -1) {
                    wheel = 0
                    break
                }
            }
            return
        }
        super.sendEvent(event)
    }

    /// fit_dimensions(): within the limits and only if the text still fits.
    @discardableResult
    func resize(to size: CGSize, preset: Int) -> Bool {
        guard size.width >= NoteSize.minimum.width, size.height >= NoteSize.minimum.height,
              size.width <= NoteSize.maximum, size.height <= NoteSize.maximum,
              editor.fits(note.storage, in: textArea(for: size)) else { return false }
        expandedHeight = size.height
        if !note.collapsed { setFrame(NSRect(x: frame.minX, y: frame.maxY - size.height, width: size.width, height: size.height), display: true) }
        else { setFrame(NSRect(x: frame.minX, y: frame.minY, width: size.width, height: frame.height), display: true) }
        note.size = preset
        scheduleSave()
        return true
    }

    // MARK: Collapse, opacity, title, style

    private func toggleCollapsed() {
        if !note.collapsed { expandedHeight = frame.height }
        note.collapsed.toggle()
        if note.collapsed { applyCollapsed() }
        else {
            styleMask.insert(.resizable)
            setHeight(expandedHeight)
            makeFirstResponder(editor)
        }
        scheduleSave()
    }

    func expand() { if note.collapsed { toggleCollapsed() } }

    private func applyCollapsed() {
        styleMask.remove(.resizable)
        setHeight(style.barHeight)
    }

    private func setHeight(_ height: CGFloat) {
        var frame = self.frame
        frame.origin.y += frame.height - height
        frame.size.height = height
        setFrame(frame, display: true, animate: false)
    }

    func setOpacity(_ opacity: Int) {
        note.opacity = opacity
        alphaValue = CGFloat(opacity) / 100
        scheduleSave()
    }

    /// Title dialog: first line, trimmed; empty removes the title.
    func setTitle(_ input: String?) {
        note.title = input.flatMap(NoteText.title(fromInput:))
        note.editingTitle = false
        note.textDirty = true
        store.save(note)
    }

    private func applyStyle() {
        RichTextBridge.restyle(note.storage, style: style, ink: ink)
        editor.resetTypingAttributes(bold: style.typesBold)
        if note.collapsed { setHeight(style.barHeight) }
        invalidateShadow()
    }

    // MARK: Right-click menu of the title bar

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(MenuItems.action("Open notes archive") { [store] in store.revealArchive() })
        menu.addItem(MenuItems.action("Browse notes") { ArchiveWindowController.shared.show(focusSearch: false) })
        menu.addItem(.separator())
        let opacity = NSMenu()
        for value in NoteSize.opacities {
            opacity.addItem(MenuItems.action(value == 100 ? "100% (opaque)" : "\(value)% opacity", checked: note.opacity == value) { [weak self] in
                self?.setOpacity(value)
            })
        }
        menu.addItem(MenuItems.submenu("Opacity", opacity))
        menu.addItem(MenuItems.action("Edit title") { [weak self] in self?.note.editingTitle = true })
        let sizes = NSMenu()
        for (index, preset) in NoteSize.presets.enumerated() {
            sizes.addItem(MenuItems.action(preset.name, checked: note.size == index) { [weak self] in
                guard let self else { return }
                if !self.resize(to: preset.size, preset: index) {
                    let alert = NSAlert()
                    alert.messageText = "The text does not fit this size."
                    alert.informativeText = "Choose a larger size or shorten the note first."
                    alert.runModal()
                }
            })
        }
        menu.addItem(MenuItems.submenu("Note size", sizes))
        menu.addItem(.separator())
        let palettes = NSMenu()
        for palette in Palette.allCases {
            palettes.addItem(MenuItems.action(palette.name, checked: store.palette == palette) { [store] in store.setPalette(palette) })
        }
        menu.addItem(MenuItems.submenu("New note palette", palettes))
        let styles = NSMenu()
        for style in NoteStyle.allCases {
            styles.addItem(MenuItems.action(style.label, checked: NoteStyle.current == style) {
                UserDefaults.standard.set(style.rawValue, forKey: NoteStyle.storageKey)
            })
        }
        menu.addItem(MenuItems.submenu("Note style", styles))
        menu.addItem(.separator())
        let tags = MenuItems.action("Tags…") { [weak self] in self.map { $0.store.editTags($0.note) } }
        tags.keyEquivalent = "t"
        tags.keyEquivalentModifierMask = .command
        menu.addItem(tags)
        return menu
    }
}

/// Menu items that run closures. The closure's owner is kept by the item.
enum MenuItems {
    static func action(_ title: String, checked: Bool = false, handler: @escaping () -> Void) -> NSMenuItem {
        let target = MenuAction(handler)
        let item = NSMenuItem(title: title, action: #selector(MenuAction.run), keyEquivalent: "")
        item.target = target
        item.representedObject = target
        item.state = checked ? .on : .off
        return item
    }

    static func submenu(_ title: String, _ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }
}

private final class MenuAction: NSObject {
    private let handler: () -> Void

    init(_ handler: @escaping () -> Void) { self.handler = handler }

    @objc func run() { handler() }
}
