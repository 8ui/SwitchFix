import Foundation

/// A language with its own character n-gram model.
///
/// The alphabet is part of the model contract: the trainer and the runtime both
/// read it from here, and the binary format stores it so a mismatch is rejected
/// at load time instead of silently scoring garbage.
public enum ModelLanguage: String, CaseIterable, Sendable {
    case english = "en"
    case russian = "ru"
    case ukrainian = "uk"

    /// Symbols the model predicts, excluding the word boundary (index 0).
    public var alphabet: [Unicode.Scalar] {
        let letters: String
        switch self {
        case .english:
            letters = "abcdefghijklmnopqrstuvwxyz'-"
        case .russian:
            letters = "абвгдеёжзийклмнопрстуфхцчшщъыьэюя-"
        case .ukrainian:
            letters = "абвгґдеєжзиіїйклмнопрстуфхцчшщьюя'-"
        }
        return Array(letters.unicodeScalars)
    }

    /// Letters that only this language (among ru/uk) uses. Used to drop lines of the
    /// other Cyrillic language from training corpora (OpenSubtitles "uk" is ~40% Russian).
    var exclusiveLetters: Set<Unicode.Scalar> {
        switch self {
        case .english: return []
        case .russian: return Set("ыэъё".unicodeScalars)
        case .ukrainian: return Set("іїєґ".unicodeScalars)
        }
    }

    var otherCyrillic: ModelLanguage? {
        switch self {
        case .english: return nil
        case .russian: return .ukrainian
        case .ukrainian: return .russian
        }
    }
}
