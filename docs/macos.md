# PicoSlip for macOS

A native macOS 26 port that reads and writes the same archive as the Windows app. The portable rules live in a C17 core (`core/`) that also compiles for Windows; the Mac front end is SwiftUI with AppKit for floating windows and the rich text editor.

## Build and run

Open `Package.swift` in Xcode 26, choose the **PicoSlip** scheme and **My Mac**, and press Run. `swift build` and `swift test` work from Terminal too. The **macOS build and tests** workflow builds and tests every change to `core/`, `macos/` or the package on a macOS 26 runner.

## Install from a disk image

`tools/make-macos-dmg.sh` builds a universal `PicoSlip.app` (Apple silicon and Intel) and `dist/macos/PicoSlip-<version>.dmg`. Open the disk image and drag PicoSlip to Applications. The **macOS build and tests** workflow also attaches the disk image to each run as the `PicoSlip-macOS` artifact.

The app is signed ad-hoc unless `SIGN_IDENTITY` names a certificate (a free Apple Development certificate works for your own Macs). It is not notarized, which needs a paid Apple Developer membership, so a copy downloaded from the internet is blocked the first time: open it once, then choose **Open Anyway** in System Settings → Privacy & Security. A disk image built on the same Mac opens directly.

PicoSlip lives in the menu bar (no Dock icon): **New note**, **Browse notes**, **Search notes**, **Open notes archive**, **Note style**, **Exit**.

## Using it

The Mac uses ⌘ where Windows uses Ctrl.

| Windows | Mac |
|---|---|
| Ctrl + Alt + + (also numpad +) | ⌃ ⌥ + (the key that types "+" on your layout, also keypad +), from any app |
| Ctrl + B / I / U | ⌘B / ⌘I / ⌘U |
| Ctrl + Shift + X | ⌘⇧X |
| Ctrl + T | ⌘T |
| Ctrl + Shift + F | ⌘⇧F |
| Ctrl + F (archive) | ⌘F |
| Ctrl + mouse wheel | ⌘ + scroll |
| F5 (archive) | F5 or ⌘R; the archive also refreshes by itself when files change |
| Ctrl/Shift-click (archive) | ⌘-click / ⇧-click |

Everything else matches the Windows README: drag the title bar to move, double-click it to edit the title, − collapses and + / □ expands, × closes; drag edges to resize (the text never scrolls, so a note refuses sizes its text does not fit); `*` + Shift+Enter starts checkboxes, Enter adds items, Backspace on an empty item ends the list, a click on a box checks it; `#Title` + Enter makes a title, Shift+Enter keeps it as text. Right-click the title bar for Open notes archive, Browse notes, Opacity, Edit title, Note size, New note palette, Note style and Tags.

**Note style** chooses how notes look on the Mac: **Mac** (default: rounded card, soft shadow, controls on the left shown on hover, system font) or **Windows** (square card, 1-pixel outline, − and × on the right, bold monospaced text). It never changes the archive.

## Your notes

The archive is `~/Library/Application Support/PicoSlip/notes`, or the folder chosen with **Archive → Move current archive** / **Open or create archive** in the browser window (stored in `~/Library/Application Support/PicoSlip/archive.path`). A configured folder that is missing, such as an unplugged drive, is never replaced: PicoSlip uses the default archive for that session and looks again next time.

Files are the Windows ones and can be shared between the two systems:

- `<id>.txt`: UTF-8 without BOM, CRLF line breaks, `#Title` CRLF before the body when the note has a title. A BOM is accepted when reading.
- `<id>.rtf`: formatting companion, written in Rich Edit's own plain dialect (Consolas 11 pt, `\b \i \ul \strike`). It is used only when its text equals the TXT body, so an external TXT edit always wins.
- `notes.ini`: one section per note, read and written line by line through the C core, so unknown keys and other programs' settings survive. It moves from ANSI to UTF-16LE the first time a tag is saved, exactly as on Windows.

Shared keys keep their Windows meaning (`color`, `has_title`, `collapsed`, `open`, `palette`, `size`, `opacity`, `width`, `height`, `tags`, `[app] palette` and `next_color`). Screen positions differ between systems, so the Mac stores its own `mac_x` and `mac_y` and leaves Windows' `x` and `y` untouched.

## Known differences

- Windows types in bold Consolas, so most text written there is bold in the RTF and appears bold on the Mac too. Text typed in the Mac style is regular unless you press ⌘B.
- Case and accent folding for search, and lowercase for tags, use Apple's Unicode tables. They agree with Windows for ordinary text; the golden corpus (`docs/golden-corpus.md`) lists the rare characters where Windows differs.
- Two copies of PicoSlip editing the same archive at the same moment (for example through a synced folder) are not coordinated; the last save of a note wins.
