import Foundation
import Testing
@testable import PicoKit

@Suite struct IniFileTests {
    @Test func readsWindowsSettingsAndKeepsUnknownLines() throws {
        let source = "[app]\r\nnext_color=2\r\n\r\n[note-1]\r\nx=10\r\n y = \"20\" \r\nfuture=keep\r\n"
        let ini = try #require(IniFile(data: Data(source.utf8)))
        #expect(!ini.isUnicode)
        #expect(ini.int("NOTE-1", "Y", default: 0) == 20)
        #expect(ini.int("note-1", "missing", default: 7) == 7)
        ini.set("note-1", "x", 15)
        ini.set("note-2", "open", 0)
        let data = try #require(ini.data())
        let text = try #require(String(data: data, encoding: .isoLatin1))
        #expect(text == "[app]\r\nnext_color=2\r\n\r\n[note-1]\r\nx=15\r\n y = \"20\" \r\nfuture=keep\r\n[note-2]\r\nopen=0\r\n")
        #expect(ini.sectionNames == ["app", "note-1", "note-2"])
    }

    @Test func tagsMoveTheFileToUTF16() throws {
        let ini = IniFile()
        ini.set("note-1", "x", 1)
        ini.makeUnicode()
        ini.set("note-1", "tags", "città;漢字")
        let data = try #require(ini.data())
        #expect(data.prefix(2) == Data([0xFF, 0xFE]))
        let again = try #require(IniFile(data: data))
        #expect(again.isUnicode && again.string("note-1", "tags") == "città;漢字")
        again.set("note-1", "tags", nil)
        #expect(again.string("note-1", "tags") == nil)
        again.removeSection("note-1")
        #expect(again.sectionNames.isEmpty)
    }

    @Test func rejectsOddUTF16() { #expect(IniFile(data: Data([0xFF, 0xFE, 0x41])) == nil) }
}

@Suite struct TagTests {
    @Test func normalizesLikeTagsC() {
        #expect(Tags.normalize("Lavoro; project alpha; Città; #Work; ÉTÉ; work") == "città;lavoro;project alpha;work;été")
        #expect(Tags.normalize("  ") == "")
        #expect(Tags.normalize("a;;b; ;c") == "a;b;c")
        #expect(Tags.normalize("tag\"quoted") == nil)
        #expect(Tags.normalize("a#b") == nil)
        #expect(Tags.normalize(String(repeating: "x", count: 63)) != nil)
        #expect(Tags.normalize(String(repeating: "x", count: 64)) == nil)
        #expect(Tags.normalize((1...24).map(String.init).joined(separator: ";")) != nil)
        #expect(Tags.normalize((1...25).map(String.init).joined(separator: ";")) == nil)
    }

    @Test func suggestsMostUsedFirst() {
        let catalog = Tags.catalog(["lavoro;viaggi", "lavoro", "lettura", "lavoro;lettura"])
        #expect(catalog.map(\.name) == ["lavoro", "lettura", "viaggi"])
        let names = Tags.suggest(catalog, prefix: "L", assigned: [], limit: 8).map(\.name)
        #expect(names == ["lavoro", "lettura"])
        #expect(Tags.suggest(catalog, prefix: "", assigned: ["LAVORO"], limit: 8).map(\.name) == ["lettura", "viaggi"])
    }
}

@Suite struct SearchTests {
    let notes: [(text: String, tags: String)] = [
        ("Caffè, perché, € e 😀\r\nSeconda riga", ""),
        ("Riunione di progetto con il cliente", "città;lavoro;project alpha"),
        ("riunione settimanale\r\nrelease plan per luglio", "personale")
    ]

    func hits(_ query: String) -> [Int]? {
        guard let parsed = SearchQuery(query) else { return nil }
        return notes.indices.filter { parsed.match(text: notes[$0].text, tags: notes[$0].tags).matches }
    }

    @Test func wordsIgnoreCaseAndAccents() {
        #expect(hits("CAFFE") == [0])
        #expect(hits("perche") == [0])
        #expect(hits("riunione") == [1, 2])
        #expect(hits("riunione lavoro") == [1])          // plain words also search tags
    }

    @Test func tagsPhrasesAndUntagged() {
        #expect(hits("#lavoro") == [1])
        #expect(hits("#\"project alpha\"") == [1])
        #expect(hits("#citta") == [])                   // exact tags keep accents
        #expect(hits("\"release plan\"") == [2])
        #expect(hits("-#") == [0])
        #expect(hits("-# riga") == [0])
    }

    @Test func invalidQueries() {
        #expect(SearchQuery("#") == nil)
        #expect(SearchQuery("\"\"") == nil)
        #expect(SearchQuery("#a;b") == nil)
        #expect(SearchQuery("a b c d e f g h i j k l m n o p") != nil)
        #expect(SearchQuery("a b c d e f g h i j k l m n o p q") == nil)
        #expect(SearchQuery("   ")?.terms.isEmpty == true)
    }
}

@Suite struct RichTextTests {
    @Test func writesRichEditStyleRTF() throws {
        let runs = [RichRun(text: "Città ", bold: true), RichRun(text: "{x}\\", italic: true), RichRun(text: "\n😀", strike: true)]
        let rtf = try #require(String(data: RichTextWriter.rtf(runs), encoding: .ascii))
        #expect(rtf.hasPrefix("{\\rtf1\\ansi"))
        #expect(rtf.contains("\\b Citt\\u224? "))
        #expect(rtf.contains("\\b0\\i \\{x\\}\\\\"))
        #expect(rtf.contains("\\i0\\strike \\par\r\n\\u-10179?\\u-8704?"))
    }

    @Test func mergesNeighbours() {
        let merged = RichTextWriter.merged([RichRun(text: "a"), RichRun(text: "b"), RichRun(text: "c", bold: true), RichRun(text: "")])
        #expect(merged == [RichRun(text: "ab"), RichRun(text: "c", bold: true)])
    }
}

@Suite struct ArchiveFolderTests {
    func temporaryFolder() throws -> ArchiveFolder {
        let folder = ArchiveFolder(url: FileManager.default.temporaryDirectory.appending(path: "picoslip-\(UUID().uuidString)"))
        try folder.create()
        return folder
    }

    @Test func writesReadsAndListsNotes() throws {
        let folder = try temporaryFolder()
        let text = try #require(NoteText.encode(title: "Titolo", body: "Corpo"))
        try folder.write("note-2026-01-01_00-00-00-000-000", text: text, rich: Data("{\\rtf1 x}".utf8))
        try Data("x".utf8).write(to: folder.url.appending(path: "other.txt"))
        #expect(try folder.noteIDs() == ["note-2026-01-01_00-00-00-000-000"])
        #expect(try folder.readText("note-2026-01-01_00-00-00-000-000") == "#Titolo\r\nCorpo")
        try folder.remove("note-2026-01-01_00-00-00-000-000")
        #expect(try folder.noteIDs().isEmpty && folder.readRich("note-2026-01-01_00-00-00-000-000") == nil)
    }

    @Test func movesOnlyIntoAnEmptyFolder() throws {
        let source = try temporaryFolder(), target = try temporaryFolder(), busy = try temporaryFolder()
        try Data("a".utf8).write(to: source.textURL("note-a"))
        try Data("[note-a]\r\nopen=1\r\n".utf8).write(to: source.settingsURL)
        try Data("b".utf8).write(to: busy.textURL("note-b"))
        #expect(throws: ArchiveError.targetNotEmpty) { try ArchiveLocation.move(source, to: busy) }
        try ArchiveLocation.move(source, to: target)
        #expect(try target.noteIDs() == ["note-a"] && FileManager.default.fileExists(atPath: target.settingsURL.path))
        #expect(try source.noteIDs().isEmpty)
    }

    @Test func editorLineBreaks() {
        #expect(NoteText.editorText("a\r\nb\rc") == "a\nb\nc")
        #expect(NoteText.storedText("a\nb\r\nc") == "a\r\nb\r\nc")
    }
}
