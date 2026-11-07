import Foundation
import Testing
@testable import PicoKit

// Expected values come from src/picoslip.c and tests/tests.c, so the Swift
// layer is checked against the Windows behavior, not against itself.

@Suite struct NoteIDTests {
    @Test func formatMatchesWindows() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Rome"))
        let date = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 11, day: 4, hour: 8, minute: 35, second: 27, nanosecond: 123_000_000)))
        #expect(NoteID.make(date: date, calendar: calendar, suffix: 0) == "note-2026-11-04_08-35-27-123-000")
        #expect(NoteID.make(date: date, calendar: calendar, suffix: 1234) == "note-2026-11-04_08-35-27-123-1234")
    }

    @Test func restoredFileNames() {
        #expect(NoteID.fromFileName("note-2026-11-04_08-35-27-123-000.txt") == "note-2026-11-04_08-35-27-123-000")
        #expect(NoteID.fromFileName("nota-vecchia.TXT") == "nota-vecchia")
        #expect(NoteID.fromFileName("note-x.rtf") == nil)
        #expect(NoteID.fromFileName("notes.ini") == nil)
        #expect(NoteID.fromFileName("note-" + String(repeating: "x", count: 75) + ".txt") == nil)   // ID must stay under 80 units
    }
}

@Suite struct NoteTextTests {
    @Test func encodesTitleAndBodyLikeSaveText() throws {
        let data = try #require(NoteText.encode(title: "Spesa è urgente", body: "Caffè e pane"))
        #expect(data == Data("#Spesa è urgente\r\nCaffè e pane".utf8))
        #expect(NoteText.encode(title: nil, body: "😀") == Data("😀".utf8))
        #expect(NoteText.encode(title: "Titolo 😀", body: "") == Data("#Titolo 😀\r\n".utf8))
    }

    @Test func decodesWithBOMAndRejectsInvalidUTF8() {
        #expect(NoteText.decode(Data([0xEF, 0xBB, 0xBF]) + Data("ok".utf8)) == "ok")
        #expect(NoteText.decode(Data("Caffè, perché, € e 😀".utf8)) == "Caffè, perché, € e 😀")
        #expect(NoteText.decode(Data([0xC0, 0xAF])) == nil)          // overlong
        #expect(NoteText.decode(Data([0xED, 0xA0, 0x80])) == nil)    // encoded surrogate
        #expect(NoteText.decode(Data([0xE2, 0x82])) == nil)          // truncated
        #expect(NoteText.decode(Data()) == "")
    }

    @Test func splitsTitleOnlyWhenFlagged() {
        let text = "#Spesa è urgente\r\nCaffè e pane"
        #expect(NoteText.split(text, hasTitleFlag: true) == ("Spesa è urgente", "Caffè e pane"))
        #expect(NoteText.split(text, hasTitleFlag: false) == (nil, text))
        #expect(NoteText.split("#\r\nx", hasTitleFlag: true) == (nil, "#\r\nx"))
    }

    @Test func promotesTrimmedTitleAtEndOfFirstLine() {
        #expect(NoteText.promoteTitle(in: "#  Titolo 😀  ", caret: "#  Titolo 😀  ".utf16.count)?.title == "Titolo 😀")
        let promoted = NoteText.promoteTitle(in: "#Nuovo\r\nCorpo già presente: 漢字", caret: 6)
        #expect(promoted?.title == "Nuovo" && promoted?.body == "Corpo già presente: 漢字")
        #expect(NoteText.promoteTitle(in: "#Nuovo", caret: 3) == nil)
        #expect(NoteText.promoteTitle(in: "#", caret: 1) == nil)
    }

    @Test func titleDialogInput() {
        #expect(NoteText.title(fromInput: "  Titolo dal menu  ") == "Titolo dal menu")
        #expect(NoteText.title(fromInput: " \t ") == nil)
        #expect(NoteText.title(fromInput: "Prima\r\nseconda") == "Prima")
    }

    @Test func checklistMarkers() {
        #expect(NoteText.todoMarker("\u{2610} Primo") == NoteText.todoOpen)
        #expect(NoteText.todoMarker("\u{2611} Fatto") == NoteText.todoDone)
        #expect(NoteText.todoMarker("\u{2610}") == nil)
        #expect(NoteText.todoMarker("* item") == nil)
    }
}

@Suite struct PaletteTests {
    @Test func colorsMatchColorsH() {
        #expect(Palette.pastel.card(0) == NoteColor(0xffee97))
        #expect(Palette.yellowOnly.card(3) == NoteColor(0xfada80))
        #expect(Palette.blackAndWhite.ink(1) == NoteColor(0xffffff))
        #expect(Palette.blackAndWhite.ink(2) == NoteColor(0x000000))
        #expect(Palette.pastel.bar(0) == NoteColor(0xefdf8d))   // 255,238,151 at 94%
        #expect(Palette.pastel.card(99) == Palette.pastel.card(0))
    }
}
