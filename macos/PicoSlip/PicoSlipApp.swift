import SwiftUI

/// Menu-bar app, like the Windows tray icon: no Dock icon, notes float on top.
@main
struct PicoSlipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("PicoSlip", systemImage: "note.text") {
            Button("New note") { NoteStore.shared.newNote() }
                .keyboardShortcut("+", modifiers: [.control, .option])
            Button("Browse notes") { ArchiveWindowController.shared.show(focusSearch: false) }
            Button("Search notes") { ArchiveWindowController.shared.show(focusSearch: true) }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            Button("Open notes archive") { NoteStore.shared.revealArchive() }
            Divider()
            NoteStylePicker()
            Divider()
            Button("Exit") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let hotKey = HotKey { NoteStore.shared.newNote() }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Run from Xcode the package has no Info.plist; this is LSUIElement.
        NSApp.setActivationPolicy(.accessory)
        NSApp.mainMenu = Self.mainMenu()
        NoteStore.shared.start()
        hotKey.register()
    }

    func applicationWillTerminate(_ notification: Notification) {
        NoteStore.shared.saveAll()
    }

    /// Not shown (the app has no menu bar of its own) but it routes the
    /// standard editing shortcuts to notes, tags and the search field.
    private static func mainMenu() -> NSMenu {
        let menu = NSMenu()
        let app = NSMenu()
        app.addItem(withTitle: "Quit PicoSlip", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(MenuItems.submenu("PicoSlip", app))
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        menu.addItem(MenuItems.submenu("Edit", edit))
        let file = NSMenu(title: "File")
        file.addItem(MenuItems.action("New Note") { NoteStore.shared.newNote() }.withKey("n"))
        file.addItem(MenuItems.action("Browse Notes") { ArchiveWindowController.shared.show(focusSearch: false) }.withKey("f", [.command, .shift]))
        file.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        menu.addItem(MenuItems.submenu("File", file))
        return menu
    }
}

extension NSMenuItem {
    func withKey(_ key: String, _ modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        keyEquivalent = key
        keyEquivalentModifierMask = modifiers
        return self
    }
}
