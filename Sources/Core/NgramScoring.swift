import Foundation
import LanguageModel

/// Margin thresholds of the detector, by word length in letters (plan/005 §4.6).
///
/// A word typed on layout S is converted to layout T when
/// `log P_T(converted) − log P_S(typed) > max(minimumThreshold, threshold(length) + sensitivityOffset)`.
/// Words of 1–2 letters never use the model; they go through `ShortWordTable`.
/// Base values come from the threshold sweep (`plan/benchmarks/detector_005_phase2.md`,
/// `thresholds_005.md`); the Sensitivity slider picks one of `sensitivityOffsets`.
/// Retune them whenever the models are retrained.
public struct DetectionThresholds: Equatable, Sendable {
    public var threeLetters: Double = 12
    public var fourLetters: Double = 8
    public var fiveLetters: Double = 8
    public var sixLetters: Double = 8
    public var sevenPlusLetters: Double = 5
    /// Shifts every threshold: negative corrects more eagerly, positive more cautiously.
    public var sensitivityOffset: Double = 0
    /// Whether a short word whose conversion is a common short word (`ShortWordTable`)
    /// is corrected automatically. Off only at the most cautious position.
    public var convertsShortWords = true

    public static let `default` = DetectionThresholds()

    /// Slider positions: 0 = Cautious … 4 = Bold; 2 = the calibrated defaults.
    public static let sensitivityPositions = 0...4
    public static let defaultSensitivity = 2
    /// Threshold shift per position (index = position).
    public static let sensitivityOffsets: [Double] = [4, 2, 0, -2, -4]
    /// No position may make the model convert on a margin this small.
    public static let minimumThreshold: Double = 1

    public init() {}

    /// Thresholds for a Sensitivity slider position (clamped to 0…4).
    public static func forSensitivity(_ position: Int) -> DetectionThresholds {
        let clamped = min(max(position, sensitivityPositions.lowerBound), sensitivityPositions.upperBound)
        var thresholds = DetectionThresholds.default
        thresholds.sensitivityOffset = sensitivityOffsets[clamped]
        thresholds.convertsShortWords = clamped != sensitivityPositions.lowerBound
        return thresholds
    }

    public func threshold(forLetterCount letters: Int) -> Double? {
        let base: Double
        switch letters {
        case ..<3: return nil
        case 3: base = threeLetters
        case 4: base = fourLetters
        case 5: base = fiveLetters
        case 6: base = sixLetters
        default: base = sevenPlusLetters
        }
        return max(Self.minimumThreshold, base + sensitivityOffset)
    }
}

extension Layout {
    var modelLanguage: ModelLanguage {
        switch self {
        case .english: return .english
        case .russian: return .russian
        case .ukrainian: return .ukrainian
        }
    }
}

/// Words the automatic path never touches: numbers, URLs and e-mail addresses.
enum AutomaticCorrectionSkipRules {
    static func shouldSkip(_ word: String) -> Bool {
        if word.allSatisfy({ $0.isNumber }) { return true }
        let lower = word.lowercased()
        if lower.hasPrefix("http") || lower.hasPrefix("www.") || lower.hasPrefix("ftp") {
            return true
        }
        return word.contains("@") && word.contains(".")
    }

    /// A lowercase letter followed by an uppercase one ("camelCase"). The detector
    /// skips a token only when both the typed and the converted core look like this:
    /// a shifted punctuation key ('ершиЖ' → 'this:') is not an identifier.
    static func isCamelCase(_ word: String) -> Bool {
        var previousIsLower = false
        for character in word {
            if character.isUppercase {
                if previousIsLower { return true }
                previousIsLower = false
            } else {
                previousIsLower = character.isLowercase
            }
        }
        return false
    }
}

/// Log-probability margin between reading the keystrokes on another layout and
/// reading them as typed.
public struct NgramMarginScorer {
    public let store: LanguageModelStore

    public init(store: LanguageModelStore) {
        self.store = store
    }

    /// `log P_target(convertedCore) − log P_source(typedCore)`, or nil when a model
    /// is unavailable (automatic correction then stays off for that language).
    public func margin(typedCore: String, source: Layout, convertedCore: String, target: Layout) -> Double? {
        guard let sourceModel = store.model(for: source.modelLanguage),
              let targetModel = store.model(for: target.modelLanguage) else {
            return nil
        }
        return targetModel.logProbability(of: convertedCore) - sourceModel.logProbability(of: typedCore)
    }
}

/// Automatic correction readiness: the layout's model and the English model (the
/// other side of every automatic conversion) must load.
public enum LanguageModelReadiness {
    @discardableResult
    public static func prepare(_ layout: Layout, store: LanguageModelStore = .shared) -> Bool {
        store.model(for: layout.modelLanguage) != nil && store.model(for: .english) != nil
    }
}
