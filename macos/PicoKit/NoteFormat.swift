import Foundation
import PicoCore

/// Note identity, titles and file encoding, delegated to the shared C core so
/// macOS writes exactly what the Windows app writes.
public enum NoteID {
    /// `note-YYYY-MM-DD_HH-MM-SS-mmm-NNN` in the calendar's time zone.
    public static func make(date: Date = .now, calendar: Calendar = .current, suffix: Int) -> String? {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second, .nanosecond], from: date)
        var time = PCDateTime(
            year: Int32(parts.year ?? 0), month: Int32(parts.month ?? 0), day: Int32(parts.day ?? 0),
            hour: Int32(parts.hour ?? 0), minute: Int32(parts.minute ?? 0), second: Int32(parts.second ?? 0),
            millisecond: Int32((parts.nanosecond ?? 0) / 1_000_000))
        var id = [pc_char](repeating: 0, count: Int(PC_ID_CAP))
        let length = pc_note_id_format(&id, &time, Int32(suffix))
        return length > 0 ? String(decoding: id[..<length], as: UTF16.self) : nil
    }

    /// The note ID of a file the app restores (`note-…` or legacy `nota-…` `.txt`).
    public static func fromFileName(_ name: String) -> String? {
        let units = Array(name.utf16)
        var id = [pc_char](repeating: 0, count: Int(PC_ID_CAP))
        guard pc_note_id_from_file_name(units, units.count, &id) else { return nil }
        return String(decoding: id.prefix { $0 != 0 }, as: UTF16.self)
    }
}

public enum NoteText {
    public static let todoOpen: Character = "\u{2610}"
    public static let todoDone: Character = "\u{2611}"

    /// UTF-8 bytes of a TXT file; nil if the text cannot be saved.
    public static func encode(title: String?, body: String) -> Data? {
        let titleUnits = title.map { Array($0.utf16) }
        let bodyUnits = Array(body.utf16)
        let capacity = pc_txt_capacity(titleUnits?.count ?? 0, bodyUnits.count)
        var bytes = [CChar](repeating: 0, count: capacity)
        var written = 0
        let ok = bodyUnits.withUnsafeBufferPointer { bodyBuffer in
            withOptionalUnits(titleUnits) { titlePointer in
                pc_txt_encode(titlePointer, titleUnits?.count ?? 0, bodyBuffer.baseAddress, bodyUnits.count,
                              &bytes, capacity, &written)
            }
        }
        return ok ? Data(bytes: bytes, count: written) : nil
    }

    /// Text of a TXT file (BOM allowed); nil for invalid UTF-8.
    public static func decode(_ data: Data) -> String? {
        let bytes = [CChar](unsafeUninitializedCapacity: data.count) { buffer, count in
            count = data.copyBytes(to: buffer)
        }
        var length = 0
        guard pc_utf8_decode(bytes, bytes.count, nil, 0, &length) else { return nil }
        var units = [pc_char](repeating: 0, count: length)
        guard pc_utf8_decode(bytes, bytes.count, &units, units.count, &length) else { return nil }
        return String(decoding: units, as: UTF16.self)
    }

    /// Title and body of a TXT file, given its `has_title` setting.
    public static func split(_ text: String, hasTitleFlag: Bool) -> (title: String?, body: String) {
        let units = Array(text.utf16)
        let split = pc_title_split(units, units.count, hasTitleFlag)
        guard split.has_title else { return (nil, text) }
        let title = String(decoding: units[split.title_start..<split.title_start + split.title_length], as: UTF16.self)
        return (title, String(decoding: units[split.body_start...], as: UTF16.self))
    }

    /// Title from the title dialog: first line, trimmed; nil removes the title.
    public static func title(fromInput input: String) -> String? {
        let units = Array(input.utf16)
        var start = 0, length = 0
        guard pc_title_from_input(units, units.count, &start, &length) else { return nil }
        return String(decoding: units[start..<start + length], as: UTF16.self)
    }

    /// Enter at `caret` (UTF-16 offset) on a first line `#Title` makes it the title.
    public static func promoteTitle(in text: String, caret: Int) -> (title: String, body: String)? {
        let units = Array(text.utf16)
        var promotion = PCTitlePromotion()
        guard caret >= 0, pc_title_promotion(units, units.count, caret, &promotion) else { return nil }
        let title = String(decoding: units[promotion.title_start..<promotion.title_start + promotion.title_length],
                           as: UTF16.self)
        return (title, String(decoding: units[promotion.body_start...], as: UTF16.self))
    }

    /// TXT uses CRLF; the editor uses LF.
    public static func editorText(_ stored: String) -> String {
        stored.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }

    public static func storedText(_ editor: String) -> String {
        editorText(editor).replacingOccurrences(of: "\n", with: "\r\n")
    }

    /// Checklist marker opening a paragraph, if any.
    public static func todoMarker(_ paragraph: String) -> Character? {
        let units = Array(paragraph.utf16.prefix(2))
        let marker = pc_todo_marker(units, units.count)
        return marker == 0 ? nil : Character(Unicode.Scalar(marker)!)
    }

    private static func withOptionalUnits<R>(_ units: [pc_char]?, _ body: (UnsafePointer<pc_char>?) -> R) -> R {
        guard let units else { return body(nil) }
        // A present but empty title still needs a non-null pointer.
        return (units.isEmpty ? [0] : units).withUnsafeBufferPointer { body($0.baseAddress) }
    }
}
