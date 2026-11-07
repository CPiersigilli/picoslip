import AppKit
import PicoKit

/// Converts between the editor's attributed text and the portable runs that
/// are written to, and read from, RTF companion files.
enum RichTextBridge {
    static func font(_ style: NoteStyle, bold: Bool, italic: Bool) -> NSFont {
        let base: NSFont = style == .mac
            ? .systemFont(ofSize: 13, weight: bold ? .bold : .regular)
            : .monospacedSystemFont(ofSize: 13, weight: bold ? .bold : .regular)
        return italic ? NSFontManager.shared.convert(base, toHaveTrait: .italicFontMask) : base
    }

    static func attributes(_ run: RichRun, style: NoteStyle, ink: NSColor) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font(style, bold: run.bold, italic: run.italic), .foregroundColor: ink
        ]
        if run.underline { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        if run.strike { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        return attributes
    }

    /// Effects of each stretch of the editor text.
    static func runs(_ text: NSAttributedString) -> [RichRun] {
        var runs: [RichRun] = []
        let string = text.string as NSString
        text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attributes, range, _ in
            runs.append(run(string.substring(with: range), attributes))
        }
        return RichTextWriter.merged(runs)
    }

    static func run(_ text: String, _ attributes: [NSAttributedString.Key: Any]) -> RichRun {
        let traits = (attributes[.font] as? NSFont)?.fontDescriptor.symbolicTraits ?? []
        return RichRun(text: text, bold: traits.contains(.bold), italic: traits.contains(.italic),
                       underline: (attributes[.underlineStyle] as? Int ?? 0) != 0,
                       strike: (attributes[.strikethroughStyle] as? Int ?? 0) != 0)
    }

    static func attributed(_ runs: [RichRun], style: NoteStyle, ink: NSColor) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for run in runs { result.append(NSAttributedString(string: run.text, attributes: attributes(run, style: style, ink: ink))) }
        return result
    }

    /// Runs from an RTF file, only when its text is exactly the TXT body:
    /// an older companion must never bring back an older text (load_rich()).
    static func read(_ data: Data, body: String) -> [RichRun]? {
        guard let parsed = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf],
                                                   documentAttributes: nil) else { return nil }
        var text = NSAttributedString(attributedString: parsed)
        // Rich Edit ends its RTF with a final paragraph mark the body does not have.
        if text.string == body + "\n" { text = text.attributedSubstring(from: NSRange(location: 0, length: text.length - 1)) }
        return text.string == body ? runs(text) : nil
    }

    /// Rebuilds fonts and ink for another style or palette, keeping the effects.
    static func restyle(_ storage: NSTextStorage, style: NoteStyle, ink: NSColor) {
        let runs = runs(storage)
        storage.beginEditing()
        var location = 0
        for run in runs {
            let length = (run.text as NSString).length
            storage.setAttributes(attributes(run, style: style, ink: ink), range: NSRange(location: location, length: length))
            location += length
        }
        storage.endEditing()
    }
}
