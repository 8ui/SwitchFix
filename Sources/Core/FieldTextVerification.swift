import Foundation
import Utils

public enum FieldTextVerdict: Equatable, Sendable {
    /// The text before the caret ends with the word and its boundary.
    case matches
    /// The boundary (or the word's tail) has not reached the field's AX text yet; the
    /// correction's events queue behind it.
    case lagging
    /// The field changed the text (autocorrect, replacement, inline suggestion): deleting
    /// would remove the wrong characters.
    case mismatch(String)
    /// Nothing to compare against: proceed as without verification.
    case unknown
}

/// Compares what a correction is about to delete with the text the field shows before the caret.
public enum FieldTextVerification {
    /// UTF-16 length to read before the caret (AX ranges are UTF-16).
    public static func window(word: String, boundary: String) -> Int {
        (word + boundary).utf16.count
    }

    public static func verdict(_ snapshot: FieldTextSnapshot, word: String, boundary: String) -> FieldTextVerdict {
        switch snapshot {
        case .unavailable:
            return .unknown
        case .selection:
            // An inline completion selected after the caret, or text the field selected itself.
            return .mismatch("selection")
        case .before(let raw):
            let before = normalized(raw)
            let typed = normalized(word)
            let shownBoundary = normalized(boundary)
            if !shownBoundary.isEmpty, before.hasSuffix(shownBoundary) {
                // The field processed the boundary: this is where autocorrect and
                // replacements show up, so the whole deleted text must be there.
                return before.hasSuffix(typed + shownBoundary) ? .matches : .mismatch("changed")
            }
            if before.hasSuffix(typed) {
                return shownBoundary.isEmpty ? .matches : .lagging
            }
            // Chromium's AX text can lag behind typing: a prefix of the word, at least half of it
            // (one letter alone matches too much).
            let shortest = max(1, typed.count / 2)
            var prefix = typed
            while prefix.count > shortest {
                prefix.removeLast()
                if before.hasSuffix(prefix) { return .lagging }
            }
            return .mismatch("changed")
        }
    }

    /// Case and typography changes replace characters one for one, so the delete count
    /// stays right: autocapitalization and smart quotes must not cancel a correction.
    static func normalized(_ text: String) -> String {
        String(text.lowercased().map { character -> Character in
            switch character {
            case "\u{201C}", "\u{201D}", "\u{201E}", "\u{201F}", "\u{00AB}", "\u{00BB}": return "\""
            case "\u{2018}", "\u{2019}", "\u{201A}", "\u{201B}": return "'"
            case "\u{2013}", "\u{2014}": return "-"
            default: return character
            }
        })
    }
}
