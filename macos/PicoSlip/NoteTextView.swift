import AppKit
import SwiftUI
import PicoKit

/// The note editor. NSTextView, not SwiftUI's TextEditor, because later phases
/// need key interception, checkbox clicks and text measurement. It sits in the
/// standard scroll view so text starts at the top; scrollers stay hidden.
struct NoteTextView: NSViewRepresentable {
    let note: Note
    let ink: NSColor
    let font: NSFont

    func makeCoordinator() -> Coordinator { Coordinator(note: note) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.verticalScrollElasticity = .none
        scrollView.horizontalScrollElasticity = .none
        let textView = scrollView.documentView as! NSTextView
        textView.delegate = context.coordinator
        textView.isRichText = true
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.string = note.body
        apply(to: textView)
        Task { textView.window?.makeFirstResponder(textView) }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != note.body { textView.string = note.body }
        apply(to: textView)
    }

    /// Font and ink for existing and newly typed text.
    private func apply(to textView: NSTextView) {
        if textView.font != font { textView.font = font }
        if textView.textColor != ink { textView.textColor = ink }
        textView.insertionPointColor = ink
        textView.typingAttributes = [.font: font, .foregroundColor: ink]
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let note: Note

        init(note: Note) { self.note = note }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            note.body = textView.string
        }

        /// Enter at the end of a first line "#Title" makes it the note title;
        /// Shift+Enter keeps the line as text. The rule lives in the C core.
        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.insertNewline(_:)),
                  NSApp.currentEvent?.modifierFlags.contains(.shift) != true,
                  textView.selectedRange().length == 0,
                  let promoted = NoteText.promoteTitle(in: textView.string, caret: textView.selectedRange().location)
            else { return false }
            note.title = promoted.title
            textView.string = promoted.body
            textView.setSelectedRange(NSRange(location: 0, length: 0))
            textView.undoManager?.removeAllActions()
            note.body = promoted.body
            return true
        }
    }
}

/// Dragging the title bar moves the window, like the Windows caption area.
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DragView: NSView {
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }
}
