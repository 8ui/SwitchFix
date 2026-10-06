import Foundation

public enum Layout: String, CaseIterable, Equatable, Codable, Sendable {
    case english
    case ukrainian
    case russian

    public var displayName: String {
        switch self {
        case .english: return "English"
        case .ukrainian: return "Ukrainian"
        case .russian: return "Russian"
        }
    }

    /// The primary macOS input source identifier for this layout.
    public var inputSourceID: String {
        return inputSourceIDs[0]
    }

    /// All known macOS input source identifiers that map to this layout.
    public var inputSourceIDs: [String] {
        switch self {
        case .english: return [
            "keylayout.US",
            "keylayout.USExtended",
            "keylayout.ABC",
            "keylayout.British",
            "keylayout.British-PC",
            "keylayout.Australian",
            "keylayout.Canadian",
            "keylayout.Irish",
            "keylayout.IrishExtended",
            "keylayout.USInternational-PC",
            "keylayout.Colemak",
            "keylayout.Dvorak",
        ]
        case .ukrainian: return [
            "keylayout.Ukrainian",
            "keylayout.Ukrainian-PC",
        ]
        case .russian: return [
            "keylayout.Russian",
            "keylayout.RussianWin",
            "keylayout.Russian-Phonetic",
        ]
        }
    }

    /// Check if a given input source ID matches this layout.
    public func matches(sourceID: String) -> Bool {
        return inputSourceIDs.contains(where: { sourceID.hasSuffix($0) })
    }
}

public class LayoutMapper {

    // MARK: - Static PC tables (lexicon validation only)

    private static let ruToEn: [Character: Character] = buildReverse(PCLayoutData.enToRu)
    private static let ukStandardToEn: [Character: Character] = buildReverse(PCLayoutData.enToUkStandard)
    private static let ukLegacyToEn: [Character: Character] = buildReverse(PCLayoutData.enToUkLegacy)

    private static func buildReverse(_ map: [Character: Character]) -> [Character: Character] {
        var result = [Character: Character]()
        for (k, v) in map {
            result[v] = k
        }
        return result
    }

    /// Whether every character of `text` is a key of `layout`: letters of its script,
    /// punctuation keys that are letters on another layout (',' → 'б'), apostrophes or
    /// hyphens (the detector keeps "rjt-xnj" / "кое-что" as one token).
    /// The tables already hold the shifted keys, so no case folding is needed.
    public static func canBeTyped(_ text: String, on layout: Layout) -> Bool {
        let keys: [Character: Character]
        switch layout {
        case .english: keys = PCLayoutData.enToRu.merging(PCLayoutData.enToUkStandard) { current, _ in current }
        case .russian: keys = ruToEn
        case .ukrainian: keys = ukStandardToEn.merging(ukLegacyToEn) { current, _ in current }
        }
        return text.contains(where: \.isLetter)
            && text.allSatisfy { keys[$0] != nil || $0 == "'" || $0 == "’" || $0 == "-" }
    }

    /// What the backslash key, typed on the English layout, types on `layout`'s primary table:
    /// the apostrophe ʼ on Ukrainian-PC, ґ on the old Apple Ukrainian layout, `\` on RussianWin.
    public static func backslashKey(on layout: Layout, tables: KeyboardTables = .pc) -> Character? {
        convert("\\", from: .english, to: layout, tables: tables).first
    }

    public static func isApostrophe(_ character: Character?) -> Bool {
        character == "ʼ" || character == "'" || character == "’"
    }

    /// Whether the backslash key between `before` and `after`, typed on the English layout,
    /// is the Ukrainian apostrophe: the Ukrainian table types an apostrophe on it, a letter key
    /// is before it (comma → б counts) and я, ю, є or ї after it, the only letters that follow
    /// ʼ (`g\znybwz` → пʼятниця). Paths and escapes (`C:\Users`, `dir\file`, `\n`) do not
    /// match; the rare ones that do (`it\'s`) are left to the model.
    public static func isUkrainianApostropheJoin(before: Character, after: Character, tables: KeyboardTables = .pc) -> Bool {
        func ukrainian(_ character: Character) -> Character? {
            convert(String(character), from: .english, to: .ukrainian, tables: tables).first
        }
        guard isApostrophe(backslashKey(on: .ukrainian, tables: tables)),
              before != "\\",
              before.isLetter || ukrainian(before)?.isLetter == true,
              let next = ukrainian(after)?.lowercased().first else { return false }
        return "яюєї".contains(next)
    }

    /// Convert through the physical key: `from`'s key for each character, then the
    /// character of that key on `to`. Unmapped characters are left as-is.
    public static func convert(_ text: String, from: Layout, to: Layout, tables: KeyboardTables = .pc) -> String {
        guard from != to else { return text }
        return convert(text, from: tables.primary(for: from), to: tables.primary(for: to))
    }

    public static func convert(_ text: String, from source: KeyTable, to target: KeyTable) -> String {
        String(text.map { character in
            source.charToKey[character].flatMap { target.keyToChar[$0] } ?? character
        })
    }

    /// One conversion per source candidate table, deduplicated, in candidate order.
    public static func convertCandidates(_ text: String, from: Layout, to: Layout, tables: KeyboardTables = .pc) -> [String] {
        guard from != to else { return [text] }
        let target = tables.primary(for: to)
        var results: [String] = []
        for source in tables.candidates(for: from) {
            let converted = convert(text, from: source, to: target)
            if !results.contains(converted) { results.append(converted) }
        }
        return results
    }

    public static func convertToAlternatives(_ text: String, from: Layout, tables: KeyboardTables = .pc) -> [(Layout, String)] {
        Layout.allCases.compactMap { target in
            guard target != from else { return nil }
            let converted = convert(text, from: from, to: target, tables: tables)
            return converted == text ? nil : (target, converted)
        }
    }
}
