import AppKit
import SwiftUI
import PicoKit

/// The note editor. NSTextView, not SwiftUI's TextEditor, because later phases
/// need key interception, checkbox clicks and text measurement.
struct NoteTextView: NSViewRepresentable {
    let note: Note
    let ink: NSColor

    func makeCoordinator() -> Coordinator { Coordinator(note: note) }

    func makeNSView(context: Context) -> NSTextView {
        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = true
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        // Windows uses bold Consolas 11 pt; this is the closest system face.
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .bold)
        textView.textColor = ink
        textView.insertionPointColor = ink
        textView.typingAttributes = [.font: textView.font!, .foregroundColor: ink]
        textView.string = note.body
        Task { textView.window?.makeFirstResponder(textView) }
        return textView
    }

    func updateNSView(_ textView: NSTextView, context: Context) {
        if textView.string != note.body { textView.string = note.body }
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
