import AppKit
import PicoKit

/// What the editor asks of its note window.
@MainActor
protocol NoteEditorOwner: AnyObject {
    var style: NoteStyle { get }
    var ink: NSColor { get }
    func editorDidChange(text: Bool)
    func editorPromotedTitle(_ title: String)
    func editorRequestsTags()
    func editorRequestsSearch()
    /// Room for text, in points, at the window's current size.
    var textAreaSize: CGSize { get }
}

/// The note body: NSTextView on TextKit 1 so the window can measure text.
/// Shortcuts use ⌘ where Windows uses Ctrl.
final class NoteEditor: NSTextView {
    weak var owner: NoteEditorOwner?

    static func make(storage: NSTextStorage) -> NSScrollView {
        let layoutManager = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)
        let editor = NoteEditor(frame: .zero, textContainer: container)
        editor.isRichText = true
        editor.allowsUndo = true
        editor.drawsBackground = false
        editor.textContainerInset = .zero
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.minSize = .zero
        editor.maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        editor.autoresizingMask = [.width]
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.usesFontPanel = false
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.verticalScrollElasticity = .none
        scroll.horizontalScrollElasticity = .none
        scroll.documentView = editor
        return scroll
    }

    var owningScrollView: NSScrollView? { enclosingScrollView }

    // MARK: Typing defaults

    func resetTypingAttributes(bold: Bool? = nil) {
        guard let owner else { return }
        var run = RichTextBridge.run("", typingAttributes)
        if let bold { run.bold = bold }
        run.strike = false
        typingAttributes = RichTextBridge.attributes(run, style: owner.style, ink: owner.ink)
        insertionPointColor = owner.ink
    }

    // MARK: "The text never scrolls"

    /// Height the attributed text needs at a given width, including an empty last line.
    static func height(of text: NSAttributedString, width: CGFloat, typing: [NSAttributedString.Key: Any]) -> CGFloat {
        let storage = NSTextStorage(attributedString: text)
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        layout.ensureLayout(for: container)
        var height = layout.usedRect(for: container).height
        if text.length == 0 || text.string.hasSuffix("\n") {
            let font = typing[.font] as? NSFont ?? .systemFont(ofSize: 13)
            if text.length > 0 { height += layout.defaultLineHeight(for: font) }
            else { height = layout.defaultLineHeight(for: font) }
        }
        return ceil(height)
    }

    func fits(_ text: NSAttributedString, in area: CGSize) -> Bool {
        Self.height(of: text, width: area.width, typing: typingAttributes) <= area.height + 0.5
    }

    override func shouldChangeText(in range: NSRange, replacementString string: String?) -> Bool {
        guard super.shouldChangeText(in: range, replacementString: string) else { return false }
        guard let string, let owner, let storage = textStorage else { return true }
        let proposed = NSMutableAttributedString(attributedString: storage)
        proposed.replaceCharacters(in: range, with: NSAttributedString(string: string, attributes: typingAttributes))
        if fits(proposed, in: owner.textAreaSize) { return true }
        NSSound.beep()
        return false
    }

    override func didChangeText() {
        super.didChangeText()
        owner?.editorDidChange(text: true)
    }

    /// Pasted text takes the note's own font and colors, as typed text does.
    override func paste(_ sender: Any?) { pasteAsPlainText(sender) }

    // MARK: Shortcuts

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        switch (modifiers, key) {
        case ([.command], "b"): toggleBold(); return true
        case ([.command], "i"): toggleItalic(); return true
        case ([.command], "u"): toggleEffect(.underlineStyle); return true
        case ([.command, .shift], "x"): toggleEffect(.strikethroughStyle); return true
        case ([.command], "t"): owner?.editorRequestsTags(); return true
        case ([.command, .shift], "f"): owner?.editorRequestsSearch(); return true
        // Editing shortcuts work even without a visible Edit menu.
        case ([.command], "c"): copy(nil); return true
        case ([.command], "x"): cut(nil); return true
        case ([.command], "v"): paste(nil); return true
        case ([.command], "a"): selectAll(nil); return true
        case ([.command], "z"): undoManager?.undo(); return true
        case ([.command, .shift], "z"): undoManager?.redo(); return true
        default: return super.performKeyEquivalent(with: event)
        }
    }

    private var hasSelection: Bool { selectedRange().length > 0 }

    func toggleBold() { toggleTrait(.bold) }
    func toggleItalic() { toggleTrait(.italic) }

    /// Like toggle_format(): if the whole selection has the effect it is
    /// removed, otherwise applied. Without a selection it affects typing.
    private func toggleTrait(_ trait: NSFontDescriptor.SymbolicTraits) {
        guard let owner, let storage = textStorage else { return }
        let range = selectedRange()
        func has(_ attributes: [NSAttributedString.Key: Any]) -> Bool {
            ((attributes[.font] as? NSFont)?.fontDescriptor.symbolicTraits ?? []).contains(trait)
        }
        func change(_ attributes: [NSAttributedString.Key: Any], on: Bool) -> NSFont {
            var run = RichTextBridge.run("", attributes)
            if trait == .bold { run.bold = on } else { run.italic = on }
            return RichTextBridge.font(owner.style, bold: run.bold, italic: run.italic)
        }
        if !hasSelection {
            typingAttributes[.font] = change(typingAttributes, on: !has(typingAttributes))
            return
        }
        var all = true
        storage.enumerateAttributes(in: range) { attributes, _, stop in
            if !has(attributes) { all = false; stop.pointee = true }
        }
        guard super.shouldChangeText(in: range, replacementString: nil) else { return }
        storage.beginEditing()
        storage.enumerateAttributes(in: range) { attributes, sub, _ in
            storage.addAttribute(.font, value: change(attributes, on: !all), range: sub)
        }
        storage.endEditing()
        super.didChangeText()
        owner.editorDidChange(text: false)
    }

    private func toggleEffect(_ key: NSAttributedString.Key) {
        guard let storage = textStorage else { return }
        let range = selectedRange()
        if !hasSelection {
            let on = (typingAttributes[key] as? Int ?? 0) != 0
            typingAttributes[key] = on ? nil : NSUnderlineStyle.single.rawValue
            return
        }
        var all = true
        storage.enumerateAttribute(key, in: range) { value, _, stop in
            if (value as? Int ?? 0) == 0 { all = false; stop.pointee = true }
        }
        guard super.shouldChangeText(in: range, replacementString: nil) else { return }
        if all { storage.removeAttribute(key, range: range) }
        else { storage.addAttribute(key, value: NSUnderlineStyle.single.rawValue, range: range) }
        super.didChangeText()
        owner?.editorDidChange(text: false)
    }

    // MARK: Checklists and titles

    private var nsString: NSString { string as NSString }

    /// Paragraph content (without its line break) containing a location.
    private func paragraph(at location: Int) -> NSRange {
        var range = nsString.paragraphRange(for: NSRange(location: location, length: 0))
        if range.length > 0, nsString.character(at: NSMaxRange(range) - 1) == 0x0a { range.length -= 1 }
        return range
    }

    private func marker(in paragraph: NSRange) -> Character? {
        NoteText.todoMarker(nsString.substring(with: paragraph))
    }

    /// One undoable edit made of several replacements.
    private func edit(_ body: () -> Bool) {
        undoManager?.beginUndoGrouping()
        let done = body()
        undoManager?.endUndoGrouping()
        if !done { undoManager?.undo() }
    }

    @discardableResult
    private func replace(_ range: NSRange, with text: String, attributes: [NSAttributedString.Key: Any]? = nil) -> Bool {
        guard shouldChangeText(in: range, replacementString: text) else { return false }
        textStorage?.replaceCharacters(in: range, with: NSAttributedString(string: text, attributes: attributes ?? typingAttributes))
        didChangeText()
        return true
    }

    private func setStrike(_ on: Bool, in range: NSRange) {
        guard range.length > 0, super.shouldChangeText(in: range, replacementString: nil) else { return }
        if on { textStorage?.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range) }
        else { textStorage?.removeAttribute(.strikethroughStyle, range: range) }
        super.didChangeText()
    }

    override func doCommand(by selector: Selector) {
        let shift = NSApp.currentEvent?.modifierFlags.contains(.shift) == true
        if selector == #selector(insertNewline(_:)) || selector == #selector(insertLineBreak(_:)) {
            if checklistEnter(shift: shift) { return }
            if !shift, promoteTitle() { return }
            if shift { insertText("\n", replacementRange: selectedRange()); return }
        }
        if selector == #selector(deleteBackward(_:)), removeMarker() { return }
        super.doCommand(by: selector)
    }

    /// todo_enter(): "*" + Shift+Enter starts a list; Enter adds an item, or
    /// ends the list on an empty one.
    private func checklistEnter(shift: Bool) -> Bool {
        let selection = selectedRange()
        guard selection.length == 0 else { return false }
        let paragraph = self.paragraph(at: selection.location)
        if shift, paragraph.length == 1, nsString.substring(with: paragraph) == "*", selection.location == NSMaxRange(paragraph) {
            resetTypingAttributes()
            edit { replace(paragraph, with: "\u{2610} ") }
            return true
        }
        guard marker(in: paragraph) != nil, selection.location >= paragraph.location + 2 else { return false }
        resetTypingAttributes()
        if paragraph.length == 2 {
            edit { replace(paragraph, with: "") }
        } else {
            edit { replace(selection, with: "\n\u{2610} ") }
        }
        return true
    }

    /// Backspace just after an item's box removes the box (remove_todo_marker()).
    private func removeMarker() -> Bool {
        let selection = selectedRange()
        guard selection.length == 0 else { return false }
        let paragraph = self.paragraph(at: selection.location)
        guard selection.location == paragraph.location + 2, marker(in: paragraph) != nil else { return false }
        edit {
            setStrike(false, in: NSRange(location: paragraph.location + 2, length: paragraph.length - 2))
            return replace(NSRange(location: paragraph.location, length: 2), with: "")
        }
        resetTypingAttributes()
        return true
    }

    /// Enter at the end of a first line "#Title" (promote_title()).
    private func promoteTitle() -> Bool {
        let selection = selectedRange()
        guard selection.length == 0,
              let promoted = NoteText.promoteTitle(in: string, caret: selection.location) else { return false }
        let firstLine = nsString.length - (promoted.body as NSString).length
        owner?.editorPromotedTitle(promoted.title)
        edit { replace(NSRange(location: 0, length: firstLine), with: "") }
        setSelectedRange(NSRange(location: 0, length: 0))
        return true
    }

    /// A click on an item's box checks it and strikes its text (click_todo()).
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let layoutManager, let container = textContainer, nsString.length > 0 {
            let local = CGPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
            let index = layoutManager.characterIndex(for: local, in: container, fractionOfDistanceBetweenInsertionPoints: nil)
            let paragraph = self.paragraph(at: min(index, nsString.length))
            if let marker = marker(in: paragraph) {
                let glyphs = layoutManager.glyphRange(forCharacterRange: NSRange(location: paragraph.location, length: 1),
                                                      actualCharacterRange: nil)
                let box = layoutManager.boundingRect(forGlyphRange: glyphs, in: container).insetBy(dx: -3, dy: 0)
                if box.contains(local) {
                    let checked = marker == NoteText.todoOpen
                    let selection = selectedRange()
                    edit {
                        guard replace(NSRange(location: paragraph.location, length: 1), with: checked ? "\u{2611}" : "\u{2610}",
                                      attributes: textStorage?.attributes(at: paragraph.location, effectiveRange: nil))
                        else { return false }
                        setStrike(checked, in: NSRange(location: paragraph.location + 2, length: paragraph.length - 2))
                        return true
                    }
                    setSelectedRange(selection)
                    owner?.editorDidChange(text: false)
                    return
                }
            }
        }
        super.mouseDown(with: event)
    }
}
