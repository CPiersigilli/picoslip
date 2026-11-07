import Foundation

/// A tag name and how many notes carry it.
public struct TagCount: Sendable, Hashable {
    public let name: String
    public let uses: Int

    public init(name: String, uses: Int) {
        self.name = name
        self.uses = uses
    }
}

/// Tag rules from src/tags.c. Stored tags are canonical names joined by ";".
public enum Tags {
    public static let nameCapacity = 63
    public static let maximum = 24
    public static let totalCapacity = 2047

    /// Canonical list for user input: names split on ";", trimmed, one leading
    /// "#" removed, NFC + lowercase, duplicates merged, sorted. "" means no
    /// tags; nil means the input is not allowed (quotes, control characters,
    /// "#" inside a name, a name of 64+ units, more than 24 names).
    public static func normalize(_ input: String) -> String? {
        var names: [String] = []
        for part in input.split(separator: ";", omittingEmptySubsequences: false) {
            var name = Substring(part).trimmingPrefix(while: isSpace)
            if name.first == "#" { name = name.dropFirst() }
            let trimmed = String(name.reversed().drop(while: { isSpace($0) }).reversed())
            guard !trimmed.isEmpty else { continue }
            guard trimmed.utf16.count < 64 else { return nil }
            guard !trimmed.unicodeScalars.contains(where: { $0.value < 0x20 || $0 == "\"" || $0 == "#" }) else { return nil }
            let canonical = trimmed.allSatisfy(\.isASCII)
                ? trimmed.lowercased()
                : trimmed.precomposedStringWithCanonicalMapping.lowercased()
            guard canonical.utf16.count < 64 else { return nil }
            if names.contains(where: { compare($0, canonical) == .orderedSame }) { continue }
            guard names.count < maximum else { return nil }
            names.append(canonical)
        }
        names.sort { compare($0, $1) == .orderedAscending }
        let joined = names.joined(separator: ";")
        return joined.utf16.count <= totalCapacity ? joined : nil
    }

    public static func names(_ tags: String) -> [String] {
        tags.split(separator: ";").map(String.init)
    }

    public static func contains(_ tags: String, _ name: String) -> Bool {
        names(tags).contains { compare($0, name) == .orderedSame }
    }

    /// CompareStringOrdinal(ignore case): code units uppercased one by one.
    public static func compare(_ a: String, _ b: String) -> ComparisonResult {
        let left = a.utf16.map(upper), right = b.utf16.map(upper)
        for (x, y) in zip(left, right) where x != y { return x < y ? .orderedAscending : .orderedDescending }
        return left.count == right.count ? .orderedSame : (left.count < right.count ? .orderedAscending : .orderedDescending)
    }

    /// Names starting with `prefix` (ignoring case) that are not assigned yet,
    /// most used first, then by name — tags_suggest().
    public static func suggest(_ catalog: [TagCount], prefix: String, assigned: [String], limit: Int) -> [TagCount] {
        let start = prefix.utf16.map(upper)
        return catalog
            .filter { item in
                let units = item.name.utf16.map(upper)
                return units.count >= start.count && Array(units.prefix(start.count)) == start
                    && !assigned.contains { compare($0, item.name) == .orderedSame }
            }
            .sorted { $0.uses != $1.uses ? $0.uses > $1.uses : compare($0.name, $1.name) == .orderedAscending }
            .prefix(limit)
            .map { $0 }
    }

    /// Every tag with its number of notes, sorted by name.
    public static func catalog(_ tagLists: some Sequence<String>) -> [TagCount] {
        var counts: [String: (name: String, uses: Int)] = [:]
        for list in tagLists {
            for name in names(list) {
                let key = String(decoding: name.utf16.map(upper), as: UTF16.self)
                counts[key, default: (name, 0)].uses += 1
            }
        }
        return counts.values
            .map { TagCount(name: $0.name, uses: $0.uses) }
            .sorted { compare($0.name, $1.name) == .orderedAscending }
    }

    public static func isSpace(_ character: Character) -> Bool { character.unicodeScalars.allSatisfy(\.properties.isWhitespace) }

    private static func upper(_ unit: UTF16.CodeUnit) -> UTF16.CodeUnit {
        guard let scalar = Unicode.Scalar(unit) else { return unit }
        let mapped = scalar.properties.uppercaseMapping.utf16
        return mapped.count == 1 ? mapped.first! : unit
    }
}
