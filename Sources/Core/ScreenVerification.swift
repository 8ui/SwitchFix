import Foundation
import Utils

/// How the field-text check before a correction or a revert is applied (`SwitchFix_fieldTextCheck`).
public enum ScreenCheckMode: String, Sendable {
    /// No check: corrections and reverts delete what the buffer or the recorded correction says.
    case off
    /// Check and log the verdict, but correct as if it matched.
    case shadow
    /// Cancel corrections whose text is not what the field shows.
    case enforce
}

public enum ScreenVerdict: Equatable, Sendable {
    /// The field ends with the typed text: deleting it is safe.
    case match
    /// The field has not caught up yet (or the answer was transient): ask again.
    case retry
    /// The field changed the text (autocorrect, prediction) or holds a selection.
    case mismatch
    /// The field autocorrected the word when the boundary was typed: the last `deleteCount`
    /// characters (the field's word and the boundary) are deleted instead of the typed ones.
    case replaced(deleteCount: Int)
    /// The text cannot be read: correct as before (fail-open).
    case unknown
    /// The field ends with the typed text followed by a selected inline suggestion: one more
    /// Backspace than typed clears the suggestion first (`deleteCount` includes it).
    case matchBeforeSelection(deleteCount: Int)
}

/// What a correction does with a selection the field shows after the caret.
public enum ScreenSelectionHandling: Sendable {
    /// Cancel: Backspace would delete the selection (automatic corrections, reverts).
    case refuse
    /// Clear an inline suggestion that follows the typed text, else cancel (the hotkey and
    /// layout-switch mode: the user asked for this word to be converted). Without a selection
    /// the verdict is the same as for `refuse`.
    case accept
    /// As `accept`, and only a suggestion is accepted: the engine saw a selection while a word
    /// was buffered and ignored it, so a field that reads otherwise (unreadable, no selection)
    /// cannot be trusted with the deletion.
    case require
}

/// Decides whether the last characters of a field are the ones a correction is about to delete.
///
/// Deleting is only harmful when the field's last characters differ from the typed ones in
/// count or position; changes that keep the length (automatic capitalization, smart quotes,
/// a non-breaking space) are deleted just as well, so they match.
public enum ScreenVerification {
    /// - Parameters:
    ///   - word: the typed word (a merged pair includes its bridge).
    ///   - boundary: the typed boundary after it ("" for the hotkey).
    ///   - final: the retry deadline has passed; the verdict is never `retry`.
    ///   - selection: what a selection after the caret means (see `ScreenSelectionHandling`).
    public static func verdict(
        word: String,
        boundary: String,
        probe: FieldTextProbe,
        final: Bool,
        selection: ScreenSelectionHandling = .refuse
    ) -> ScreenVerdict {
        if selection == .require {
            // Only a suggestion is trusted: anything else cancels instead of failing open.
            let verdict = self.verdict(word: word, boundary: boundary, probe: probe, final: final, selection: .accept)
            switch verdict {
            case .matchBeforeSelection, .retry: return verdict
            default: return .mismatch
            }
        }
        switch probe {
        case .selection(_, let before, let atTextStart):
            guard selection == .accept else { return .mismatch }
            // The text before it may have been unreadable for now (a timeout).
            guard let before else { return final ? .mismatch : .retry }
            switch verdict(word: word, boundary: boundary, probe: .text(before: before, atTextStart: atTextStart), final: final) {
            case .match:
                // Only the exact text: a word missing its trailing space at the deadline would
                // make the extra Backspace delete the character before it.
                guard folded(before).hasSuffix(folded(word + boundary)) else { return .mismatch }
                return .matchBeforeSelection(deleteCount: word.count + boundary.count + 1)
            case .retry:
                return .retry
            default:
                // Unreadable or changed text before a suggestion is never deleted blindly.
                return .mismatch
            }
        case .unavailable(let transient):
            return transient && !final ? .retry : .unknown
        case .text(let before, let atTextStart):
            let field = folded(before)
            let expected = folded(word + boundary)
            if field.hasSuffix(expected) { return .match }
            // Nothing before the caret: the app has not handled the keys yet, or the element
            // is not the field (a container reporting an empty range). Never proof of a change.
            if field.isEmpty { return final ? .unknown : .retry }
            let lagging = (1..<max(expected.count, 1)).contains { missing in
                field.hasSuffix(expected.dropLast(missing))
            }
            guard lagging else {
                return autocorrected(word: word, boundary: boundary, field: field, atTextStart: atTextStart)
                    .map { .replaced(deleteCount: $0) } ?? .mismatch
            }
            guard final else { return .retry }
            // Some editors never expose a trailing space. A transform triggered by the space
            // (autocorrect, a prediction) would have changed the word by now.
            if !boundary.isEmpty, boundary.allSatisfy(\.isWhitespace),
               field.hasSuffix(folded(word)) {
                return .match
            }
            return .mismatch
        }
    }

    /// How many characters to delete when the field shows an autocorrection of `word`
    /// followed by the boundary, or nil when the change is not one.
    ///
    /// An autocorrection replaces one whole word with a close one in the same script that
    /// keeps its first letter; only such a word, bounded by a separator the field shows, is
    /// deleted. Anything else (a prediction, a pasted or reformatted text, a word with a
    /// soft-boundary letter such as `j,sxyj`) stays a mismatch.
    static func autocorrected(word: String, boundary: String, field: [String], atTextStart: Bool) -> Int? {
        let typed = folded(word)
        let tail = folded(boundary)
        guard typed.count >= minimumAutocorrectedLength, !tail.isEmpty,
              let typedScript = script(of: typed),
              field.hasSuffix(tail) else { return nil }
        let beforeBoundary = field.dropLast(tail.count)
        let shown = Array(beforeBoundary.reversed().prefix { !isSeparator($0) }.reversed())
        let separated = shown.count < beforeBoundary.count || atTextStart
        guard separated, !shown.isEmpty, shown != typed, shown.first == typed.first,
              script(of: shown) == typedScript,
              abs(shown.count - typed.count) <= maximumAutocorrectionDistance,
              editDistance(typed, shown) <= maximumAutocorrectionDistance else { return nil }
        return shown.count + tail.count
    }

    /// Shorter words are too easily within the distance of an unrelated one.
    private static let minimumAutocorrectedLength = 5
    private static let maximumAutocorrectionDistance = 2

    private enum Script { case latin, cyrillic }

    /// The script of a word made only of letters of one script; nil otherwise.
    private static func script(of word: [String]) -> Script? {
        var result: Script?
        for character in word {
            guard character.unicodeScalars.count == 1, let scalar = character.unicodeScalars.first,
                  scalar.properties.isAlphabetic else { return nil }
            let current: Script
            switch scalar.value {
            case 0x41...0x5A, 0x61...0x7A, 0xC0...0x24F: current = .latin
            case 0x400...0x4FF: current = .cyrillic
            default: return nil
            }
            if let result, result != current { return nil }
            result = current
        }
        return result
    }

    /// Whitespace or punctuation that ends a typed word; apostrophes, hyphens and the letters
    /// on punctuation keys stay inside it, as in `WordBoundary`.
    private static func isSeparator(_ character: String) -> Bool {
        character.allSatisfy { $0.isWhitespace || $0.isNewline } || WordBoundary.isPunctuationBoundary(character)
    }

    private static func editDistance(_ a: [String], _ b: [String]) -> Int {
        var previous = Array(0...b.count)
        for (i, x) in a.enumerated() {
            var current = [i + 1] + Array(repeating: 0, count: b.count)
            for (j, y) in b.enumerated() {
                current[j + 1] = min(previous[j + 1] + 1, current[j] + 1, previous[j] + (x == y ? 0 : 1))
            }
            previous = current
        }
        return previous[b.count]
    }

    private static let spaces: Set<Character> = [" ", "\u{00A0}", "\u{202F}", "\u{2007}"]
    private static let singleQuotes: Set<Character> = ["'", "\u{2018}", "\u{2019}", "\u{201A}", "\u{2039}", "\u{203A}"]
    private static let doubleQuotes: Set<Character> = ["\"", "\u{201C}", "\u{201D}", "\u{201E}", "\u{00AB}", "\u{00BB}"]

    /// One element per character, so equal counts mean equal Backspace counts.
    static func folded(_ text: String) -> [String] {
        text.map { character in
            if spaces.contains(character) { return " " }
            if singleQuotes.contains(character) { return "'" }
            if doubleQuotes.contains(character) { return "\"" }
            return character.lowercased()
        }
    }
}

private extension Array where Element: Equatable {
    func hasSuffix<S: Collection>(_ suffix: S) -> Bool where S.Element == Element {
        count >= suffix.count && zip(self[(count - suffix.count)...], suffix).allSatisfy { $0 == $1 }
    }
}
