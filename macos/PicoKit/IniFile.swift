import Foundation
import PicoCore

/// notes.ini through the shared C reader, so untouched lines, unknown keys and
/// the ANSI → UTF-16LE migration behave exactly as on Windows.
public final class IniFile {
    private let handle: OpaquePointer

    public init() {
        guard let handle = pc_ini_create() else { fatalError("Out of memory") }
        self.handle = handle
    }

    /// nil when the bytes are not a readable INI file.
    public init?(data: Data) {
        let parsed = data.withUnsafeBytes { raw in
            pc_ini_parse(raw.bindMemory(to: UInt8.self).baseAddress, raw.count)
        }
        guard let parsed else { return nil }
        handle = parsed
    }

    deinit { pc_ini_free(handle) }

    public var isUnicode: Bool { pc_ini_encoding(handle) == PC_INI_UTF16LE }

    /// tags_write() converts the file to UTF-16LE before storing any tag.
    public func makeUnicode() { pc_ini_set_encoding(handle, PC_INI_UTF16LE) }

    public func string(_ section: String, _ key: String) -> String? {
        var value: UnsafePointer<pc_char>?
        var length = 0
        let found = section.withUTF16CString { section in
            key.withUTF16CString { key in pc_ini_get(handle, section, key, &value, &length) }
        }
        guard found, let value else { return nil }
        return String(decoding: UnsafeBufferPointer(start: value, count: length), as: UTF16.self)
    }

    /// GetPrivateProfileInt: optional sign and leading digits; a missing key
    /// gives the fallback, text without digits gives 0.
    public func int(_ section: String, _ key: String, default fallback: Int) -> Int {
        guard let text = string(section, key) else { return fallback }
        var digits = Substring(text)
        let negative = digits.first == "-"
        if negative || digits.first == "+" { digits = digits.dropFirst() }
        let number = digits.prefix { $0.isASCII && $0.isNumber }
        let value = Int(number.prefix(10)) ?? 0
        return negative ? -value : value
    }

    /// nil deletes the key.
    public func set(_ section: String, _ key: String, _ value: String?) {
        let ok = section.withUTF16CString { section in
            key.withUTF16CString { key in
                if let value { return value.withUTF16CString { pc_ini_set(handle, section, key, $0) } }
                return pc_ini_set(handle, section, key, nil)
            }
        }
        if !ok { fatalError("Out of memory") }
    }

    public func set(_ section: String, _ key: String, _ value: Int) { set(section, key, String(value)) }

    public func removeSection(_ section: String) {
        _ = section.withUTF16CString { pc_ini_remove_section(handle, $0) }
    }

    public var sectionNames: [String] {
        (0..<pc_ini_section_count(handle)).compactMap { index in
            var name: UnsafePointer<pc_char>?
            var length = 0
            guard pc_ini_section_name(handle, index, &name, &length), let name else { return nil }
            return String(decoding: UnsafeBufferPointer(start: name, count: length), as: UTF16.self)
        }
    }

    public func data() -> Data? {
        var bytes: UnsafeMutablePointer<UInt8>?
        var size = 0
        guard pc_ini_serialize(handle, &bytes, &size), let bytes else { return nil }
        defer { pc_ini_free_bytes(bytes) }
        return Data(bytes: bytes, count: size)
    }
}

extension String {
    /// The string as NUL-terminated UTF-16 for the C core.
    func withUTF16CString<R>(_ body: (UnsafePointer<pc_char>) -> R) -> R {
        var units = Array(utf16)
        units.append(0)
        return units.withUnsafeBufferPointer { body($0.baseAddress!) }
    }
}
