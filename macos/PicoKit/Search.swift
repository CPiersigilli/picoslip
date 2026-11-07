import Foundation

/// The archive query language of src/search.c: words and "phrases" search
/// text and tags ignoring case and accents, #tag and #"tag name" require that
/// exact tag, -# requires no tags. All terms must match; at most 16.
public struct SearchQuery: Sendable, Equatable {
    public enum Term: Sendable, Equatable {
        case text(String)
        case tag(String)
        case untagged
    }

    public static let maximumTerms = 16
    public static let invalidMessage = "Use up to 16 words or phrases; write a tag after #."

    public let terms: [Term]

    public init?(_ input: String) {
        var terms: [Term] = []
        var characters = Substring(input)
        func skipSpaces() { characters = characters.drop(while: Tags.isSpace) }
        skipSpaces()
        while !characters.isEmpty {
            guard terms.count < Self.maximumTerms else { return nil }
            if characters.hasPrefix("-#") {
                let rest = characters.dropFirst(2)
                if rest.isEmpty || Tags.isSpace(rest.first!) {
                    terms.append(.untagged)
                    characters = rest
                    skipSpaces()
                    continue
                }
            }
            let isTag = characters.first == "#"
            if isTag { characters = characters.dropFirst() }
            var raw = ""
            if characters.first == "\"" {
                characters = characters.dropFirst()
                raw = String(characters.prefix { $0 != "\"" })
                characters = characters.dropFirst(raw.count)
                if characters.first == "\"" { characters = characters.dropFirst() }
            } else {
                raw = String(characters.prefix { !Tags.isSpace($0) })
                characters = characters.dropFirst(raw.count)
            }
            skipSpaces()
            guard !raw.isEmpty else { return nil }
            if isTag {
                guard let canonical = Tags.normalize(raw), !canonical.isEmpty, !canonical.contains(";") else { return nil }
                terms.append(.tag(canonical))
            } else {
                guard !Self.fold(raw).isEmpty else { return nil }
                terms.append(.text(raw))
            }
        }
        self.terms = terms
    }

    /// Case- and accent-insensitive form used for matching.
    public static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// Whether a note matches, and the first text hit (in `text`) for an excerpt.
    public func match(text: String, tags: String) -> (matches: Bool, hit: Range<String.Index>?) {
        var hit: Range<String.Index>?
        for term in terms {
            switch term {
            case .untagged:
                if !tags.isEmpty { return (false, nil) }
            case .tag(let name):
                if !Tags.contains(tags, name) { return (false, nil) }
            case .text(let raw):
                let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
                if let range = text.range(of: raw, options: options) {
                    if hit == nil { hit = range }
                } else if tags.range(of: raw, options: options) == nil {
                    return (false, nil)
                }
            }
        }
        return (true, hit)
    }
}

/// One archive entry as the browser and search see it.
public struct ArchivedNote: Sendable, Identifiable, Hashable {
    public let id: String
    public var text: String
    public var tags: String
    public var title: String?
    public var palette: Palette
    public var color: Int

    public init(id: String, text: String, tags: String, title: String?, palette: Palette, color: Int) {
        self.id = id
        self.text = text
        self.tags = tags
        self.title = title
        self.palette = palette
        self.color = color
    }

    /// Creation time encoded in the ID (local time).
    public var created: DateComponents? {
        let digits = id.dropFirst(5).split { !$0.isNumber }.compactMap { Int($0) }
        guard digits.count >= 3 else { return nil }
        return DateComponents(year: digits[0], month: digits[1], day: digits[2])
    }

    /// Body without the title line.
    public var body: String { title == nil ? text : NoteText.split(text, hasTitleFlag: true).body }
}

public enum ArchiveReader {
    /// Reads every note and its metadata, off the main thread.
    @concurrent
    public static func load(_ folder: ArchiveFolder) async throws -> [ArchivedNote] {
        let ini = try folder.loadSettings()
        return try folder.noteIDs().reversed().compactMap { id in
            guard let text = try? folder.readText(id) else { return nil }
            let tags = Tags.normalize(ini.string(id, "tags") ?? "") ?? ""
            let split = NoteText.split(text, hasTitleFlag: ini.int(id, "has_title", default: 0) != 0)
            return ArchivedNote(id: id, text: text, tags: tags, title: split.title,
                                palette: Palette(rawValue: ini.int(id, "palette", default: 0)) ?? .pastel,
                                color: ini.int(id, "color", default: 0))
        }
    }
}
