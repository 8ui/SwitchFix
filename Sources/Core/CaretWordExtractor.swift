import Foundation

/// Which typed characters end a word; shared by the event classifier and the caret-word reader.
enum WordBoundary {
    private static let boundaryCharacterSet: CharacterSet = {
        var set = CharacterSet.punctuationCharacters.union(.symbols)
        set.subtract(CharacterSet(charactersIn: "'’`-"))
        return set
    }()

    /// Punctuation that is a letter in a Cyrillic layout (б, ю, ж, э, х, ъ, …): stays in the word.
    private static let softBoundaryCharacterSet = CharacterSet(charactersIn: ",.;'[]`<>:\"{}~")

    /// True when a typed single-character text ends the word, as `KeyboardMonitor` classifies it.
    static func isPunctuationBoundary(_ text: String) -> Bool {
        guard text.count == 1, let scalar = text.unicodeScalars.first else { return false }
        return boundaryCharacterSet.contains(scalar) && !softBoundaryCharacterSet.contains(scalar)
    }
}

/// Reads the word right before the caret from text around it (e.g. from Accessibility),
/// with the same word boundaries the input buffer uses.
public enum CaretWordExtractor {
    public static let maxWordLength = 64

    /// - Parameters:
    ///   - prefix: text before the caret (a window; may not start at the beginning of the text).
    ///   - prefixStartsAtTextStart: false when the window was cut: a word reaching its start may be longer.
    ///   - next: the character right after the caret; a word character means the caret is inside a word.
    ///   - tables: every character must be typable on some layout, so one Backspace removes one character.
    /// - Returns: nil when there is no whole word to convert.
    public static func word(
        before prefix: String,
        prefixStartsAtTextStart: Bool,
        next: Character?,
        tables: KeyboardTables = .pc
    ) -> String? {
        if let next, isWordCharacter(next) { return nil }
        let characters = Array(prefix)
        var start = characters.count
        while start > 0, isWordCharacter(characters[start - 1]) {
            start -= 1
        }
        guard start < characters.count else { return nil }
        guard start > 0 || prefixStartsAtTextStart else { return nil }
        let word = characters[start...]
        guard word.count <= maxWordLength,
              word.contains(where: \.isLetter),
              word.allSatisfy({ isTypable($0, tables: tables) }) else { return nil }
        return String(word)
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        !character.isWhitespace && !character.isNewline && !WordBoundary.isPunctuationBoundary(String(character))
    }

    private static func isTypable(_ character: Character, tables: KeyboardTables) -> Bool {
        guard character.unicodeScalars.count == 1,
              let scalar = character.unicodeScalars.first,
              scalar.value <= 0xFFFF else { return false }
        return Layout.allCases.contains { layout in
            tables.candidates(for: layout).contains { $0.charToKey[character] != nil }
        }
    }
}
