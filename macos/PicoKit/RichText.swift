import Foundation

/// A stretch of text with the four character effects PicoSlip offers.
public struct RichRun: Sendable, Equatable {
    public var text: String
    public var bold = false, italic = false, underline = false, strike = false

    public init(text: String, bold: Bool = false, italic: Bool = false, underline: Bool = false, strike: Bool = false) {
        self.text = text
        self.bold = bold
        self.italic = italic
        self.underline = underline
        self.strike = strike
    }

    func sameStyle(as other: RichRun) -> Bool {
        bold == other.bold && italic == other.italic && underline == other.underline && strike == other.strike
    }
}

/// RTF companion files in the plain dialect Rich Edit itself writes: Consolas
/// 11 pt, \b \i \ul \strike, \par line breaks, \u escapes for non-ASCII. The
/// Windows app reads them as its own; the Mac reads either kind with AppKit.
public enum RichTextWriter {
    public static func rtf(_ runs: [RichRun]) -> Data {
        var out = "{\\rtf1\\ansi\\ansicpg1252\\deff0\\nouicompat{\\fonttbl{\\f0\\fmodern\\fcharset0 Consolas;}}\r\n"
        out += "\\uc1\\pard\\f0\\fs22 "
        var current = RichRun(text: "")
        for run in runs where !run.text.isEmpty {
            var words = ""
            if run.bold != current.bold { words += run.bold ? "\\b" : "\\b0" }
            if run.italic != current.italic { words += run.italic ? "\\i" : "\\i0" }
            if run.underline != current.underline { words += run.underline ? "\\ul" : "\\ulnone" }
            if run.strike != current.strike { words += run.strike ? "\\strike" : "\\strike0" }
            if !words.isEmpty { out += words + " " }
            current = run
            for unit in run.text.utf16 {
                switch unit {
                case 0x5c: out += "\\\\"
                case 0x7b: out += "\\{"
                case 0x7d: out += "\\}"
                case 0x0a: out += "\\par\r\n"
                case 0x0d: break
                case 0x09: out += "\\tab "
                case 0x20..<0x80: out.unicodeScalars.append(Unicode.Scalar(UInt8(unit)))
                case 0..<0x20: break
                default: out += "\\u\(Int16(bitPattern: unit))?"
                }
            }
        }
        out += "\r\n}\r\n"
        return Data(out.utf8)
    }

    /// Merges neighbours with the same effects so the output stays small.
    public static func merged(_ runs: [RichRun]) -> [RichRun] {
        var result: [RichRun] = []
        for run in runs where !run.text.isEmpty {
            if let last = result.last, last.sameStyle(as: run) { result[result.count - 1].text += run.text }
            else { result.append(run) }
        }
        return result
    }
}
