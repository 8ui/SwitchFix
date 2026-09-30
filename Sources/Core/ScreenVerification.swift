import Foundation
import Utils

/// How the field-text check before a correction is applied (`SwitchFix_fieldTextCheck`).
public enum ScreenCheckMode: String, Sendable {
    /// No check: corrections delete what the buffer says.
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
    /// The text cannot be read: correct as before (fail-open).
    case unknown
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
    public static func verdict(word: String, boundary: String, probe: FieldTextProbe, final: Bool) -> ScreenVerdict {
        switch probe {
        case .selection:
            return .mismatch
        case .unavailable(let transient):
            return transient && !final ? .retry : .unknown
        case .text(let before):
            let field = folded(before)
            let expected = folded(word + boundary)
            if field.hasSuffix(expected) { return .match }
            let lagging = (1..<max(expected.count, 1)).contains { missing in
                field.hasSuffix(expected.dropLast(missing))
            }
            guard lagging else { return .mismatch }
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
