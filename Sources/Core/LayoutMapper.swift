import Foundation

public enum UkrainianKeyboardVariant: String {
    case standard
    case legacy
}

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

    // MARK: - Mapping tables

    // RU → UK mapping for characters that differ between Russian and Ukrainian layouts.
    private static let ruToUkStandard: [Character: Character] = [
        "ы": "і", "э": "є", "ъ": "ї", "ё": "ґ",
        "Ы": "І", "Э": "Є", "Ъ": "Ї", "Ё": "Ґ",
    ]

    private static let ruToUkLegacy: [Character: Character] = [
        "ы": "и", "и": "і", "э": "є", "ъ": "ї", "ё": "ґ",
        "Ы": "И", "И": "І", "Э": "Є", "Ъ": "Ї", "Ё": "Ґ",
    ]

    // Pre-built reverse mappings
    private static let ruToEn: [Character: Character] = buildReverse(PCLayoutData.enToRu)
    private static let ukStandardToEn: [Character: Character] = buildReverse(PCLayoutData.enToUkStandard)
    private static let ukLegacyToEn: [Character: Character] = buildReverse(PCLayoutData.enToUkLegacy)
    private static let ukStandardToRu: [Character: Character] = buildReverse(ruToUkStandard)
    private static let ukLegacyToRu: [Character: Character] = buildReverse(ruToUkLegacy)

    private static func buildReverse(_ map: [Character: Character]) -> [Character: Character] {
        var result = [Character: Character]()
        for (k, v) in map {
            result[v] = k
        }
        return result
    }

    /// Get the mapping table for converting from one layout to another.
    private static func mappingTable(
        from: Layout,
        to: Layout,
        ukrainianFromVariant: UkrainianKeyboardVariant,
        ukrainianToVariant: UkrainianKeyboardVariant
    ) -> [Character: Character]? {
        switch (from, to) {
        case (.english, .russian):   return PCLayoutData.enToRu
        case (.english, .ukrainian):
            return ukrainianToVariant == .legacy ? PCLayoutData.enToUkLegacy : PCLayoutData.enToUkStandard
        case (.russian, .english):   return ruToEn
        case (.ukrainian, .english):
            return ukrainianFromVariant == .legacy ? ukLegacyToEn : ukStandardToEn
        case (.russian, .ukrainian):
            return ukrainianToVariant == .legacy ? ruToUkLegacy : ruToUkStandard
        case (.ukrainian, .russian):
            return ukrainianFromVariant == .legacy ? ukLegacyToRu : ukStandardToRu
        default: return nil
        }
    }

    /// Whether every character of `text` is a key of `layout`: letters of its script,
    /// punctuation keys that are letters on another layout (',' → 'б'), apostrophes or
    /// hyphens (the detector keeps "rjt-xnj" / "кое-что" as one token).
    /// The tables already hold the shifted keys, so no case folding is needed.
    public static func canBeTyped(_ text: String, on layout: Layout) -> Bool {
        let keys: [Character: Character]
        switch layout {
        case .english: keys = PCLayoutData.enToRu
        case .russian: keys = ruToEn
        case .ukrainian: keys = ukStandardToEn.merging(ukLegacyToEn) { current, _ in current }
        }
        return text.contains(where: \.isLetter)
            && text.allSatisfy { keys[$0] != nil || $0 == "'" || $0 == "’" || $0 == "-" }
    }

    /// Convert text from one layout to another.
    /// Characters without a mapping are left as-is.
    public static func convert(_ text: String, from: Layout, to: Layout) -> String {
        return convert(
            text,
            from: from,
            to: to,
            ukrainianFromVariant: .standard,
            ukrainianToVariant: .standard
        )
    }

    /// Convert text from one layout to another with explicit Ukrainian variant selection.
    public static func convert(
        _ text: String,
        from: Layout,
        to: Layout,
        ukrainianFromVariant: UkrainianKeyboardVariant,
        ukrainianToVariant: UkrainianKeyboardVariant
    ) -> String {
        guard from != to,
              let table = mappingTable(
                from: from,
                to: to,
                ukrainianFromVariant: ukrainianFromVariant,
                ukrainianToVariant: ukrainianToVariant
              ) else {
            return text
        }
        return String(text.map { table[$0] ?? $0 })
    }

    /// Convert through the physical key: `from`'s key for each character, then the
    /// character of that key on `to`. Unmapped characters are left as-is.
    public static func convert(_ text: String, from: Layout, to: Layout, tables: KeyboardTables) -> String {
        guard from != to else { return text }
        return convert(text, from: tables.primary(for: from), to: tables.primary(for: to))
    }

    public static func convert(_ text: String, from source: KeyTable, to target: KeyTable) -> String {
        String(text.map { character in
            source.charToKey[character].flatMap { target.keyToChar[$0] } ?? character
        })
    }

    /// One conversion per source candidate table, deduplicated, in candidate order.
    public static func convertCandidates(_ text: String, from: Layout, to: Layout, tables: KeyboardTables) -> [String] {
        guard from != to else { return [text] }
        let target = tables.primary(for: to)
        var results: [String] = []
        for source in tables.candidates(for: from) {
            let converted = convert(text, from: source, to: target)
            if !results.contains(converted) { results.append(converted) }
        }
        return results
    }

    public static func convertToAlternatives(_ text: String, from: Layout, tables: KeyboardTables) -> [(Layout, String)] {
        Layout.allCases.compactMap { target in
            guard target != from else { return nil }
            let converted = convert(text, from: from, to: target, tables: tables)
            return converted == text ? nil : (target, converted)
        }
    }

    /// Try converting text from the given layout to all other layouts,
    /// returning each (Layout, convertedText) pair.
    public static func convertToAlternatives(_ text: String, from: Layout) -> [(Layout, String)] {
        return convertToAlternatives(
            text,
            from: from,
            ukrainianFromVariant: .standard,
            ukrainianToVariant: .standard
        )
    }

    /// Try converting text to all alternative layouts with explicit Ukrainian variant selection.
    public static func convertToAlternatives(
        _ text: String,
        from: Layout,
        ukrainianFromVariant: UkrainianKeyboardVariant,
        ukrainianToVariant: UkrainianKeyboardVariant
    ) -> [(Layout, String)] {
        var results = [(Layout, String)]()
        for target in Layout.allCases where target != from {
            let converted = convert(
                text,
                from: from,
                to: target,
                ukrainianFromVariant: ukrainianFromVariant,
                ukrainianToVariant: ukrainianToVariant
            )
            if converted != text {
                results.append((target, converted))
            }
        }
        return results
    }
}
