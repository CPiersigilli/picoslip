import SwiftUI

/// Menu-bar app, like the Windows tray icon: no Dock icon, notes float on top.
@main
struct PicoSlipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("PicoSlip", systemImage: "note.text") {
            Button("New note") { appDelegate.notes.newNote() }
                .keyboardShortcut("n")
            NoteStylePicker()
            Divider()
            Button("Exit") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let notes = NoteWindows()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Run from Xcode the package has no Info.plist; this is LSUIElement.
        NSApp.setActivationPolicy(.accessory)
        notes.newNote()
    }
}
