import Foundation

/// A notes folder on disk: `<id>.txt`, optional `<id>.rtf` and `notes.ini`,
/// the same layout the Windows app reads and writes.
public struct ArchiveFolder: Sendable, Hashable {
    public let url: URL

    public init(url: URL) { self.url = url.standardizedFileURL }

    public var settingsURL: URL { url.appending(path: "notes.ini") }
    public func textURL(_ id: String) -> URL { url.appending(path: id + ".txt") }
    public func richURL(_ id: String) -> URL { url.appending(path: id + ".rtf") }

    public func create() throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    /// IDs of every note file the Windows app would restore, oldest first.
    public func noteIDs() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: url.path)
            .compactMap(NoteID.fromFileName)
            .sorted()
    }

    public func exists(_ id: String) -> Bool { FileManager.default.fileExists(atPath: textURL(id).path) }

    public func readText(_ id: String) throws -> String {
        let data = try Data(contentsOf: textURL(id))
        guard let text = NoteText.decode(data) else { throw ArchiveError.invalidText(id) }
        return text
    }

    public func readRich(_ id: String) -> Data? { try? Data(contentsOf: richURL(id)) }

    /// TXT and RTF are each replaced atomically; the RTF goes first so a crash
    /// leaves at worst an RTF that no longer matches, which readers ignore.
    public func write(_ id: String, text: Data, rich: Data?) throws {
        if let rich { try rich.write(to: richURL(id), options: .atomic) }
        try text.write(to: textURL(id), options: .atomic)
    }

    public func writeRich(_ id: String, _ rich: Data) throws {
        try rich.write(to: richURL(id), options: .atomic)
    }

    public func remove(_ id: String) throws {
        for file in [textURL(id), richURL(id)] where FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.removeItem(at: file)
        }
    }

    /// A missing notes.ini is an empty one, as for GetPrivateProfile*.
    public func loadSettings() throws -> IniFile {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return IniFile() }
        guard let ini = IniFile(data: try Data(contentsOf: settingsURL)) else { throw ArchiveError.invalidSettings }
        return ini
    }

    public func saveSettings(_ ini: IniFile) throws {
        guard let data = ini.data() else { throw ArchiveError.invalidSettings }
        try data.write(to: settingsURL, options: .atomic)
    }

    /// Modification date, used to notice edits made by other programs.
    public func modificationDate(of file: URL) -> Date? {
        (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }
}

public enum ArchiveError: LocalizedError, Equatable {
    case invalidText(String)
    case invalidSettings
    case targetNotEmpty
    case copyMismatch(String)

    public var errorDescription: String? {
        switch self {
        case .invalidText(let id): "The note \(id) is not valid UTF-8 text."
        case .invalidSettings: "notes.ini could not be read or written."
        case .targetNotEmpty: "Choose an empty folder to move the archive into."
        case .copyMismatch(let name): "The copy of \(name) does not match the original."
        }
    }
}

/// Moving or switching the notes folder, like src/location.c.
public enum ArchiveLocation {
    /// Copies every file, verifies each copy, and only then deletes the
    /// originals. Never overwrites: the target must be empty.
    public static func move(_ source: ArchiveFolder, to target: ArchiveFolder) throws {
        let manager = FileManager.default
        try target.create()
        let existing = try manager.contentsOfDirectory(atPath: target.url.path).filter { $0 != ".DS_Store" }
        guard existing.isEmpty else { throw ArchiveError.targetNotEmpty }
        let names = try manager.contentsOfDirectory(atPath: source.url.path).filter { name in
            var directory: ObjCBool = false
            manager.fileExists(atPath: source.url.appending(path: name).path, isDirectory: &directory)
            return !directory.boolValue && name != ".DS_Store"
        }
        var copied: [URL] = []
        do {
            for name in names {
                let from = source.url.appending(path: name), to = target.url.appending(path: name)
                try manager.copyItem(at: from, to: to)
                copied.append(to)
                guard try Data(contentsOf: from) == Data(contentsOf: to) else { throw ArchiveError.copyMismatch(name) }
            }
        } catch {
            for file in copied { try? manager.removeItem(at: file) }
            throw error
        }
        for name in names { try? manager.removeItem(at: source.url.appending(path: name)) }
    }
}
