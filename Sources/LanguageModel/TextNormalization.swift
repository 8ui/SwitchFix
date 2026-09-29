import Foundation

/// Text normalization shared by the trainer and the runtime scorer. Any change here
/// changes what the models mean — retrain the models after editing this file.
public enum TextNormalization {
    private static let apostrophes: Set<Unicode.Scalar> = ["\u{2019}", "\u{02BC}", "\u{2018}", "`"]
    private static let innerJoiners: Set<Unicode.Scalar> = ["'", "-"]

    /// Lowercases and maps typographic apostrophes to `'`.
    public static func normalize(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.lowercased().unicodeScalars {
            scalars.append(apostrophes.contains(scalar) ? "'" : scalar)
        }
        return String(scalars)
    }

    /// Whether a corpus line belongs to `language`. For Russian/Ukrainian this rejects
    /// lines containing letters exclusive to the other language; Ukrainian lines must
    /// also contain at least one Ukrainian-only letter, because mislabelled Russian
    /// lines without ы/э/ъ/ё would otherwise pass.
    public static func lineMatches(_ line: String, language: ModelLanguage) -> Bool {
        guard let other = language.otherCyrillic else { return true }
        let foreign = other.exclusiveLetters
        let own = language.exclusiveLetters
        var hasOwn = false
        for scalar in line.lowercased().unicodeScalars {
            if foreign.contains(scalar) { return false }
            if own.contains(scalar) { hasOwn = true }
        }
        return language == .ukrainian ? hasOwn : true
    }

    /// Words of `language` in a line: runs of the language's letters with inner
    /// apostrophes/hyphens. Tokens that mix in any other letter (another script,
    /// digits glued to letters) are dropped entirely rather than truncated.
    public static func words(in line: String, language: ModelLanguage) -> [String] {
        let alphabet = Set(language.alphabet)
        let joiners = innerJoiners.intersection(alphabet)
        let letters = alphabet.subtracting(joiners)
        var result: [String] = []
        var current = String.UnicodeScalarView()
        var tainted = false

        func flush() {
            // Trim joiners at the edges ("'hello", "word-").
            var scalars = Array(current)
            while let first = scalars.first, joiners.contains(first) { scalars.removeFirst() }
            while let last = scalars.last, joiners.contains(last) { scalars.removeLast() }
            if !tainted, !scalars.isEmpty {
                var word = String.UnicodeScalarView()
                word.append(contentsOf: scalars)
                result.append(String(word))
            }
            current = String.UnicodeScalarView()
            tainted = false
        }

        for scalar in normalize(line).unicodeScalars {
            if letters.contains(scalar) || joiners.contains(scalar) {
                current.append(scalar)
            } else if scalar.properties.isAlphabetic || ("0"..."9").contains(scalar) {
                current.append(scalar)
                tainted = true
            } else {
                flush()
            }
        }
        flush()
        return result
    }
}
