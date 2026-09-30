import Foundation
import LanguageModel
import Utils

/// Represents a detection result — the target layout and converted word.
public struct DetectionResult {
    public let sourceLayout: Layout
    public let targetLayout: Layout
    public let convertedWord: String
    public let originalWord: String
    public let shouldSwitchLayout: Bool

    public init(
        sourceLayout: Layout,
        targetLayout: Layout,
        convertedWord: String,
        originalWord: String,
        shouldSwitchLayout: Bool
    ) {
        self.sourceLayout = sourceLayout
        self.targetLayout = targetLayout
        self.convertedWord = convertedWord
        self.originalWord = originalWord
        self.shouldSwitchLayout = shouldSwitchLayout
    }
}

/// State machine for layout detection.
public enum DetectorState {
    case idle
    case buffering
    case detecting
}

/// Delegate protocol for layout detection events.
public protocol LayoutDetectorDelegate: AnyObject {
    func layoutDetector(_ detector: LayoutDetector, didDetectWrongLayout result: DetectionResult, boundaryCharacter: String?)
}

public class LayoutDetector {
    public weak var delegate: LayoutDetectorDelegate?

    /// Minimum characters before triggering detection.
    public var detectionThreshold: Int = 3

    /// Require this many consecutive wrong-layout words before correcting.
    public var consecutiveThreshold: Int = 1
    public var lowConfidenceMaxLength: Int = 3
    public var lowConfidenceConfirmations: Int = 2
    /// Key tables for conversion; candidates of the source layout are tried in order.
    public var keyboardTables: KeyboardTables = .pc
    public var shortWordSuppressionLength: Int = 2
    /// Low-confidence words longer than `shortWordSuppressionLength` and up to this length
    /// are kept (not corrected, not deferred) inside a strong current-language context:
    /// `в нову еру` stays Ukrainian. Automatic detection only.
    public var contextKeepLength: Int = 3
    public var shortWordSuppressionMinValidContext: Int = 2
    public var shortWordSuppressionContextWindow: Int = 6

    private var wordBuffer: String = ""
    private var state: DetectorState = .idle
    private var consecutiveWrongCount: Int = 0
    private var lastDetectionResult: DetectionResult?
    private var pendingBoundaryCharacter: String?
    private var pendingSwitchLayout: Layout?
    private var pendingSwitchCount: Int = 0
    private var recentOutcomes: [RecentOutcome] = []
    private var pendingSuppressedShort: SuppressedShort?
    private var isOutOfSync: Bool = false

    /// Layouts that are allowed as correction targets (defaults to all).
    public var allowedLayouts: Set<Layout> = Set(Layout.allCases)

    private enum RecentOutcome {
        case validCurrent
        case corrected
        case unknown
    }

    private struct SuppressedShort {
        let originalWord: String
        let convertedWord: String
        let targetLayout: Layout
        let boundaryAfterWord: String
    }

    private static let boundaryCharacterSet: CharacterSet = {
        var set = CharacterSet.punctuationCharacters.union(.symbols)
        set.subtract(CharacterSet(charactersIn: "'’`-"))
        // Keep punctuation keys that may correspond to letters in other layouts.
        set.subtract(CharacterSet(charactersIn: ",.;'[]`<>:\"{}~"))
        return set
    }()

    private static let englishVowels = CharacterSet(charactersIn: "aeiouyAEIOUY")
    private static let ukrainianVowels = CharacterSet(charactersIn: "аеєиіїоуюяАЕЄИІЇОУЮЯ")
    private static let russianVowels = CharacterSet(charactersIn: "аеёиоуыэюяАЕЁИОУЫЭЮЯ")
    private static let latinLowercaseRange: ClosedRange<UInt32> = 0x0061...0x007A
    private static let latinUppercaseRange: ClosedRange<UInt32> = 0x0041...0x005A
    private static let cyrillicRange: ClosedRange<UInt32> = 0x0400...0x052F

    /// The currently active keyboard layout (set externally by InputSourceManager).
    public var currentLayout: Layout = .english {
        didSet {
            if currentLayout != .english { lastCyrillicLayout = currentLayout }
        }
    }

    /// Margin thresholds of the language-model decision (plan/005 §4.6).
    public var thresholds: DetectionThresholds = .default
    /// Source of the n-gram models (injectable for tests).
    public var languageModels: LanguageModelStore = .shared
    /// The user's word rules, checked before the model (nil: none).
    public var lexicon: PersonalLexicon?
    /// The Cyrillic layout the user typed on most recently: the target for Latin words
    /// when both Russian and Ukrainian are installed. Survives `reset()`.
    private var lastCyrillicLayout: Layout?

    /// The Cyrillic layout typed on most recently, if any.
    public var preferredCyrillicLayout: Layout? { lastCyrillicLayout }

    public init() {}

    /// Add a character to the word buffer.
    public func addCharacter(_ char: String) {
        wordBuffer += char
        state = .buffering
    }

    /// Called when a word boundary is detected (space, enter, tab, punctuation).
    /// This is the only point where detection fires and triggers correction.
    /// - Parameter boundaryCharacter: The character that triggered the flush (e.g. " ", "\n"), or nil for hotkey-triggered flush.
    @discardableResult
    public func flushBuffer(boundaryCharacter: String? = nil) -> DetectionResult? {
        guard !wordBuffer.isEmpty else {
            state = .idle
            isOutOfSync = false
            return nil
        }

        // Split trailing punctuation from the buffer (e.g. "hello," -> "hello" + ",")
        let (coreWord, trailingPunctuation) = splitTrailingBoundary(from: wordBuffer)
        wordBuffer = coreWord

        guard !wordBuffer.isEmpty else {
            state = .idle
            isOutOfSync = false
            return nil
        }

        // Store boundary string (trailing punctuation + explicit boundary like space/newline)
        let boundary = trailingPunctuation + (boundaryCharacter ?? "")
        pendingBoundaryCharacter = boundary.isEmpty ? nil : boundary

        // Check buffer at word boundaries (short words are handled by ShortWordTable)
        let result = isOutOfSync ? nil : checkBuffer()
        if let result {
            delegate?.layoutDetector(self, didDetectWrongLayout: result, boundaryCharacter: pendingBoundaryCharacter)
        }

        // Reset buffer
        pendingBoundaryCharacter = nil
        wordBuffer = ""
        state = .idle
        isOutOfSync = false
        return result
    }

    /// Called when backspace/delete is pressed — remove last character from buffer.
    public func deleteLastCharacter() {
        guard !wordBuffer.isEmpty else {
            isOutOfSync = true
            return
        }
        wordBuffer.removeLast()
        if wordBuffer.isEmpty {
            state = .idle
        }
    }

    /// Discard the current buffer without running detection (used in hotkey mode on word boundary).
    public func discardBuffer() {
        wordBuffer = ""
        state = .idle
        isOutOfSync = false
    }

    /// Mark the detector as out of sync (e.g. when navigation keys are pressed).
    public func invalidateSync() {
        wordBuffer = ""
        state = .idle
        isOutOfSync = true
    }

    /// Reset all state (e.g., when app loses focus).
    public func reset() {
        wordBuffer = ""
        state = .idle
        consecutiveWrongCount = 0
        lastDetectionResult = nil
        pendingSwitchLayout = nil
        pendingSwitchCount = 0
        recentOutcomes = []
        pendingSuppressedShort = nil
        isOutOfSync = false
    }

    /// The current word buffer contents.
    public var currentBuffer: String {
        return wordBuffer
    }

    // MARK: - Detection Logic

    private func checkBuffer() -> DetectionResult? {
        state = .detecting
        let suppressedShort = consumePendingSuppressedShort()

        let word = wordBuffer
        let sourceLayout = resolvedSourceLayout(for: word)

        // Skip if the word contains mixed scripts (both Latin and Cyrillic)
        if containsMixedScripts(word) {
            SwitchFixLog.detector.debug("mixed scripts, skipping '\(word)'")
            state = .buffering
            return nil
        }

        return checkLanguageModels(word: word, sourceLayout: sourceLayout, suppressedShort: suppressedShort)
    }

    // MARK: - Language-model decision

    /// Automatic detection (plan/005 §4.3): converts only between English and the
    /// native Cyrillic layout; short words go through `ShortWordTable`, longer ones
    /// through the language-model margin.
    private func checkLanguageModels(word: String, sourceLayout: Layout, suppressedShort: SuppressedShort?) -> DetectionResult? {
        let originalParts = splitTokenForValidation(word)
        let core = originalParts.core.isEmpty ? word : originalParts.core

        if AutomaticCorrectionSkipRules.shouldSkip(core) {
            markValidInCurrentLanguage()
            return nil
        }

        // The user's own rules beat every heuristic below.
        if let rule = lexicon?.rule(for: word, sourceLayout: sourceLayout) {
            switch rule {
            case .neverCorrect:
                SwitchFixLog.detector.debug("lexicon: keep (length \(word.count))")
                lexicon?.noteMatch(word: word, sourceLayout: sourceLayout)
                markValidInCurrentLanguage()
                return nil
            case .alwaysCorrect(let target):
                if let result = finishLexiconCorrection(word: word, sourceLayout: sourceLayout, target: target) {
                    SwitchFixLog.detector.debug("lexicon: convert to \(target.rawValue) (length \(word.count))")
                    return result
                }
            }
        }

        if shouldSkipAutomaticCommandLineFlag(word: word, sourceLayout: sourceLayout) {
            // Neutral: a flag is neither native-language context nor a correction
            // (checked before the acronym rule, which would count '-R' as context).
            consecutiveWrongCount = 0
            lastDetectionResult = nil
            pendingSwitchLayout = nil
            pendingSwitchCount = 0
            state = .buffering
            return nil
        }
        if shouldSkipAutomaticEnglishAcronymCorrection(word: word, sourceLayout: sourceLayout) {
            markValidInCurrentLanguage()
            return nil
        }
        let typedIsCamelCase = AutomaticCorrectionSkipRules.isCamelCase(core)

        let letterCount = core.filter(\.isLetter).count
        if letterCount <= ShortWordTable.maxLength,
           ShortWordTable.contains(core, language: sourceLayout.modelLanguage) {
            SwitchFixLog.detector.debug("model: common short word '\(word)' in \(sourceLayout.rawValue) — no correction")
            markValidInCurrentLanguage()
            return nil
        }

        let scorer = NgramMarginScorer(store: languageModels)
        var best: (target: Layout, recomposed: String, margin: Double, threshold: Double)?
        var highestMargin = -Double.infinity
        var firstConversion: (target: Layout, converted: String)?

        for target in automaticTargets(for: sourceLayout) {
            let conversions = LayoutMapper.convertCandidates(word, from: sourceLayout, to: target, tables: keyboardTables)
            if firstConversion == nil, let first = conversions.first {
                firstConversion = (target, first)
            }

            // Conversions are tried in candidate-table order (the source the user last
            // typed on first) and the first one that clears its threshold wins: a
            // fallback table must not beat the primary one on score alone
            // ('іукмшсу' → 'bervice').
            conversionLoop: for conversion in conversions {
                let parts = splitTokenForValidation(conversion)
                // A letter key that maps to punctuation at the start is a fake switch
                // ('бігу' → ',sue').
                if parts.prefix.count > originalParts.prefix.count { continue }
                let convertedCore = parts.core.isEmpty ? conversion : parts.core
                if typedIsCamelCase && AutomaticCorrectionSkipRules.isCamelCase(convertedCore) {
                    SwitchFixLog.detector.debug("camelCase identifier '\(word)' — skipping")
                    markValidInCurrentLanguage()
                    return nil
                }
                let recomposed = parts.prefix + convertedCore + parts.suffix
                // Letters typed on punctuation keys ('ws'']' → 'цієї') only count as
                // letters on the converted side.
                let letters = max(letterCount, convertedCore.filter(\.isLetter).count)

                if letters <= ShortWordTable.maxLength,
                   ShortWordTable.contains(convertedCore, language: target.modelLanguage) {
                    SwitchFixLog.detector.debug("model: '\(word)' → common short word '\(recomposed)' in \(target.rawValue)")
                    return finishCorrection(
                        word: word,
                        recomposedWord: recomposed,
                        sourceLayout: sourceLayout,
                        targetLayout: target,
                        suppressedShort: suppressedShort
                    )
                }

                guard let threshold = thresholds.threshold(forLetterCount: letters),
                      let margin = scorer.margin(
                        typedCore: core,
                        source: sourceLayout,
                        convertedCore: convertedCore,
                        target: target
                      ) else { continue }
                highestMargin = max(highestMargin, margin)
                if margin > threshold {
                    // Between targets (Russian vs Ukrainian without history) the
                    // larger margin wins.
                    if margin > (best?.margin ?? -.infinity) {
                        best = (target, recomposed, margin, threshold)
                    }
                    break conversionLoop
                }
            }
        }

        if let best {
            // Calibration data for thresholds (plan/005 §4.6.4); the word only at debug level.
            SwitchFixLog.detector.info(
                "model decision corrected=true margin=\(String(format: "%.1f", best.margin)) threshold=\(String(format: "%.1f", best.threshold)) letters=\(letterCount)"
            )
            SwitchFixLog.detector.debug(
                "model: '\(word)' → '\(best.recomposed)' margin=\(String(format: "%.1f", best.margin)) threshold=\(String(format: "%.1f", best.threshold)) letters=\(letterCount)"
            )
            return finishCorrection(
                word: word,
                recomposedWord: best.recomposed,
                sourceLayout: sourceLayout,
                targetLayout: best.target,
                suppressedShort: suppressedShort
            )
        }

        if let firstConversion,
           shouldAllowAcronymFallback(
            original: word,
            converted: firstConversion.converted,
            currentLayout: sourceLayout
           ) {
            return finishAcronymFallback(
                word: word,
                converted: firstConversion.converted,
                sourceLayout: sourceLayout,
                targetLayout: firstConversion.target
            )
        }

        if highestMargin.isFinite {
            SwitchFixLog.detector.info(
                "model decision corrected=false margin=\(String(format: "%.1f", highestMargin)) letters=\(letterCount)"
            )
        }
        if highestMargin.isFinite && highestMargin < 0 {
            // The keystrokes read better as typed: evidence for the current language.
            markValidInCurrentLanguage()
        } else {
            pendingSwitchLayout = nil
            pendingSwitchCount = 0
            recordOutcome(.unknown)
            state = .buffering
        }
        return nil
    }

    /// Layouts a word typed on `source` may be converted to automatically: only
    /// English ↔ Cyrillic, never Russian ↔ Ukrainian (plan/005 «Целевой сценарий»).
    private func automaticTargets(for source: Layout) -> [Layout] {
        if source != .english {
            return allowedLayouts.contains(.english) ? [.english] : []
        }
        let cyrillic = [Layout.russian, .ukrainian].filter { allowedLayouts.contains($0) }
        if cyrillic.count > 1, let last = lastCyrillicLayout, cyrillic.contains(last) {
            return [last]
        }
        return cyrillic
    }

    private func markValidInCurrentLanguage() {
        consecutiveWrongCount = 0
        lastDetectionResult = nil
        pendingSwitchLayout = nil
        pendingSwitchCount = 0
        recordOutcome(.validCurrent)
        state = .buffering
    }

    /// Shared tail of a detected correction: case restoration, low-confidence
    /// confirmation and suppression, merging a deferred short word, and the
    /// consecutive-word threshold.
    private func finishCorrection(
        word: String,
        recomposedWord: String,
        sourceLayout: Layout,
        targetLayout: Layout,
        suppressedShort: SuppressedShort?
    ) -> DetectionResult? {
        var finalWord = applyCase(from: word, to: recomposedWord)
        var originalForCorrection = word
        let isLowConfidence = word.count <= lowConfidenceMaxLength
        let shouldSwitch = shouldSwitchLayout(isLowConfidence: isLowConfidence, targetLayout: targetLayout)

        if isLowConfidence, !shouldSwitch, pendingBoundaryCharacter != nil,
           targetLayout != sourceLayout,
           word.count > shortWordSuppressionLength, word.count <= contextKeepLength,
           hasStrongCurrentContext() {
            SwitchFixLog.detector.info("kept short word '\(word)' -> '\(finalWord)' (strong current context)")
            consecutiveWrongCount = 0
            lastDetectionResult = nil
            // The kept word must not count toward the next word's layout switch.
            pendingSwitchLayout = nil
            pendingSwitchCount = 0
            recordOutcome(.unknown)
            state = .buffering
            return nil
        }

        if shouldSuppressLowConfidenceCorrection(
            original: word,
            converted: finalWord,
            targetLayout: targetLayout,
            sourceLayout: sourceLayout,
            isLowConfidence: isLowConfidence,
            shouldSwitch: shouldSwitch
        ) {
            SwitchFixLog.detector.info("suppressed short word '\(word)' -> '\(finalWord)' (weak evidence, deferring)")
            consecutiveWrongCount = 0
            lastDetectionResult = nil
            if let boundary = pendingBoundaryCharacter, !boundary.isEmpty {
                pendingSuppressedShort = SuppressedShort(
                    originalWord: word,
                    convertedWord: finalWord,
                    targetLayout: targetLayout,
                    boundaryAfterWord: boundary
                )
            }
            recordOutcome(.unknown)
            state = .buffering
            return nil
        }

        if let merged = mergeSuppressedShort(
            suppressedShort,
            currentOriginal: word,
            currentConverted: finalWord,
            targetLayout: targetLayout,
            isLowConfidence: isLowConfidence,
            shouldSwitch: shouldSwitch
        ) {
            originalForCorrection = merged.original
            finalWord = merged.converted
        }

        consecutiveWrongCount += 1
        lastDetectionResult = DetectionResult(
            sourceLayout: sourceLayout,
            targetLayout: targetLayout,
            convertedWord: finalWord,
            originalWord: originalForCorrection,
            shouldSwitchLayout: shouldSwitch
        )

        if consecutiveWrongCount >= consecutiveThreshold {
            let result = lastDetectionResult
            consecutiveWrongCount = 0
            recordOutcome(.corrected)
            state = .buffering
            return result
        }

        recordOutcome(.corrected)
        state = .buffering
        return nil
    }

    /// A user rule is an explicit decision: no low-confidence confirmation, no short-word
    /// suppression or merging; the layout switches at once. English ↔ Cyrillic only.
    private func finishLexiconCorrection(word: String, sourceLayout: Layout, target: Layout) -> DetectionResult? {
        guard (sourceLayout == .english) != (target == .english), allowedLayouts.contains(target) else {
            return nil
        }
        let converted = LayoutMapper.convert(word, from: sourceLayout, to: target, tables: keyboardTables)
        guard converted != word else { return nil }
        let result = DetectionResult(
            sourceLayout: sourceLayout,
            targetLayout: target,
            convertedWord: applyCase(from: word, to: converted),
            originalWord: word,
            shouldSwitchLayout: true
        )
        consecutiveWrongCount = 0
        lastDetectionResult = result
        pendingSwitchLayout = nil
        pendingSwitchCount = 0
        recordOutcome(.corrected)
        state = .buffering
        return result
    }

    /// Shared tail of the uppercase-acronym fallback ("СШ" → "CI").
    private func finishAcronymFallback(
        word: String,
        converted: String,
        sourceLayout: Layout,
        targetLayout: Layout
    ) -> DetectionResult? {
        let finalWord = applyCase(from: word, to: converted)
        let shouldSwitch = shouldSwitchLayout(isLowConfidence: true, targetLayout: targetLayout)

        if shouldSuppressAcronymFallback(
            targetLayout: targetLayout,
            sourceLayout: sourceLayout,
            shouldSwitch: shouldSwitch
        ) {
            consecutiveWrongCount = 0
            lastDetectionResult = nil
            recordOutcome(.unknown)
            state = .buffering
            return nil
        }

        consecutiveWrongCount += 1
        lastDetectionResult = DetectionResult(
            sourceLayout: sourceLayout,
            targetLayout: targetLayout,
            convertedWord: finalWord,
            originalWord: word,
            shouldSwitchLayout: shouldSwitch
        )

        if consecutiveWrongCount >= consecutiveThreshold {
            let result = lastDetectionResult
            consecutiveWrongCount = 0
            recordOutcome(.corrected)
            state = .buffering
            return result
        }

        recordOutcome(.corrected)
        state = .buffering
        return nil
    }

    private func shouldSwitchLayout(isLowConfidence: Bool, targetLayout: Layout) -> Bool {
        if !isLowConfidence {
            pendingSwitchLayout = nil
            pendingSwitchCount = 0
            return true
        }

        if pendingSwitchLayout == targetLayout {
            pendingSwitchCount += 1
        } else {
            pendingSwitchLayout = targetLayout
            pendingSwitchCount = 1
        }

        if pendingSwitchCount >= lowConfidenceConfirmations {
            pendingSwitchLayout = nil
            pendingSwitchCount = 0
            return true
        }

        return false
    }

    private func shouldSuppressLowConfidenceCorrection(
        original: String,
        converted: String,
        targetLayout: Layout,
        sourceLayout: Layout,
        isLowConfidence: Bool,
        shouldSwitch: Bool
    ) -> Bool {
        guard isLowConfidence else { return false }
        guard original.count <= shortWordSuppressionLength else { return false }
        guard !shouldSwitch else { return false }
        guard targetLayout != sourceLayout else { return false }
        guard !converted.isEmpty else { return false }
        return hasStrongCurrentContext()
    }

    private func shouldSuppressAcronymFallback(
        targetLayout: Layout,
        sourceLayout: Layout,
        shouldSwitch: Bool
    ) -> Bool {
        guard targetLayout != sourceLayout else { return false }
        guard !shouldSwitch else { return false }
        return hasStrongCurrentContext()
    }

    private func consumePendingSuppressedShort() -> SuppressedShort? {
        let value = pendingSuppressedShort
        pendingSuppressedShort = nil
        return value
    }

    private func mergeSuppressedShort(
        _ suppressed: SuppressedShort?,
        currentOriginal: String,
        currentConverted: String,
        targetLayout: Layout,
        isLowConfidence: Bool,
        shouldSwitch: Bool
    ) -> (original: String, converted: String)? {
        guard let suppressed else { return nil }
        guard suppressed.targetLayout == targetLayout else { return nil }

        // Merge only when the current word provides stronger evidence than the suppressed short word.
        let hasStrongCurrentSignal = currentOriginal.count > shortWordSuppressionLength || shouldSwitch || !isLowConfidence
        guard hasStrongCurrentSignal else { return nil }

        let bridge = suppressed.boundaryAfterWord
        guard !bridge.isEmpty else { return nil }

        return (
            original: suppressed.originalWord + bridge + currentOriginal,
            converted: suppressed.convertedWord + bridge + currentConverted
        )
    }

    private func hasStrongCurrentContext() -> Bool {
        let window = max(1, shortWordSuppressionContextWindow)
        let recent = recentOutcomes.suffix(window)
        let validCount = recent.reduce(0) { partial, outcome in
            if case .validCurrent = outcome {
                return partial + 1
            }
            return partial
        }
        let hasRecentCorrection = recent.contains { outcome in
            if case .corrected = outcome { return true }
            return false
        }
        return validCount >= shortWordSuppressionMinValidContext && !hasRecentCorrection
    }

    private func recordOutcome(_ outcome: RecentOutcome) {
        recentOutcomes.append(outcome)
        let window = max(1, shortWordSuppressionContextWindow)
        if recentOutcomes.count > window {
            recentOutcomes.removeFirst(recentOutcomes.count - window)
        }
    }

    private func applyCase(from original: String, to word: String) -> String {
        guard !word.isEmpty else { return word }
        if isAllUppercase(original) {
            return word.uppercased()
        }
        if isCapitalized(original) {
            return word.prefix(1).uppercased() + word.dropFirst().lowercased()
        }
        return word
    }

    private func isAllUppercase(_ word: String) -> Bool {
        var hasLetters = false
        for char in word {
            if char.isLetter {
                hasLetters = true
                if !char.isUppercase {
                    return false
                }
            }
        }
        return hasLetters
    }

    private func isCapitalized(_ word: String) -> Bool {
        var chars = Array(word)
        while let first = chars.first, !first.isLetter {
            chars.removeFirst()
        }
        guard let first = chars.first, first.isUppercase else { return false }
        for c in chars.dropFirst() where c.isLetter {
            if !c.isLowercase { return false }
        }
        return true
    }

    private func shouldAllowAcronymFallback(original: String, converted: String, currentLayout: Layout) -> Bool {
        guard original.count >= 2 else { return false }
        guard original.count <= 3 else { return false }
        guard isAllUppercase(original) else { return false }
        if containsVowel(original, layout: currentLayout) { return false }
        if containsMixedScripts(converted) { return false }
        return true
    }

    private func shouldSkipAutomaticEnglishAcronymCorrection(word: String, sourceLayout: Layout) -> Bool {
        guard sourceLayout == .english else { return false }
        // Keep manual/hotkey correction available; suppress only automatic boundary-triggered rewrites.
        guard pendingBoundaryCharacter != nil else { return false }
        guard word.count >= 2 else { return false }
        return isAllUppercase(word)
    }

    /// A Latin command-line flag (`-r`, `--x`) is never rewritten automatically:
    /// `ls -r` must not become `ls -к`. Longer flags go through the model as usual.
    private func shouldSkipAutomaticCommandLineFlag(word: String, sourceLayout: Layout) -> Bool {
        guard sourceLayout == .english else { return false }
        // Keep manual/hotkey correction available; suppress only automatic boundary-triggered rewrites.
        guard pendingBoundaryCharacter != nil else { return false }
        let parts = splitTokenForValidation(word)
        guard parts.suffix.isEmpty, (1...2).contains(parts.prefix.count),
              parts.prefix.allSatisfy({ $0 == "-" }) else { return false }
        return parts.core.count == 1 && parts.core.allSatisfy(\.isLetter)
    }

    private func containsVowel(_ text: String, layout: Layout) -> Bool {
        let vowels: CharacterSet
        switch layout {
        case .english: vowels = LayoutDetector.englishVowels
        case .ukrainian: vowels = LayoutDetector.ukrainianVowels
        case .russian: vowels = LayoutDetector.russianVowels
        }
        for scalar in text.unicodeScalars where vowels.contains(scalar) {
            return true
        }
        return false
    }

    /// Check if a string contains both Latin and Cyrillic characters.
    private func containsMixedScripts(_ text: String) -> Bool {
        var hasLatin = false
        var hasCyrillic = false
        for char in text {
            for scalar in char.unicodeScalars {
                if (scalar.value >= 0x0041 && scalar.value <= 0x005A) || (scalar.value >= 0x0061 && scalar.value <= 0x007A) {
                    hasLatin = true
                } else if (scalar.value >= 0x0400 && scalar.value <= 0x04FF) {
                    hasCyrillic = true
                }
            }
            if hasLatin && hasCyrillic { return true }
        }
        return false
    }

    private enum ScriptKind {
        case latin
        case cyrillic
        case mixed
        case unknown
    }

    private func resolvedSourceLayout(for word: String) -> Layout {
        let script = scriptKind(for: word)
        switch script {
        case .latin:
            if allowedLayouts.contains(.english) {
                return .english
            }
            return currentLayout
        case .cyrillic:
            if currentLayout == .ukrainian || currentLayout == .russian {
                return currentLayout
            }
            return inferCyrillicLayout(for: word) ?? currentLayout
        case .mixed, .unknown:
            return currentLayout
        }
    }

    private func scriptKind(for text: String) -> ScriptKind {
        var hasLatin = false
        var hasCyrillic = false

        for scalar in text.unicodeScalars where scalar.properties.isAlphabetic {
            let value = scalar.value
            if LayoutDetector.latinLowercaseRange.contains(value) || LayoutDetector.latinUppercaseRange.contains(value) {
                hasLatin = true
            } else if LayoutDetector.cyrillicRange.contains(value) {
                hasCyrillic = true
            }
            if hasLatin && hasCyrillic {
                return .mixed
            }
        }

        if hasLatin { return .latin }
        if hasCyrillic { return .cyrillic }
        return .unknown
    }

    private func inferCyrillicLayout(for word: String) -> Layout? {
        let lower = word.lowercased()

        if containsAnyCharacter(from: "іїєґ", in: lower), allowedLayouts.contains(.ukrainian) {
            return .ukrainian
        }
        if containsAnyCharacter(from: "ыэёъ", in: lower), allowedLayouts.contains(.russian) {
            return .russian
        }

        let hasUkrainian = allowedLayouts.contains(.ukrainian)
        let hasRussian = allowedLayouts.contains(.russian)
        if hasUkrainian && !hasRussian { return .ukrainian }
        if hasRussian && !hasUkrainian { return .russian }
        if hasUkrainian { return .ukrainian }
        if hasRussian { return .russian }
        return nil
    }

    private func containsAnyCharacter(from candidates: String, in text: String) -> Bool {
        let set = Set(candidates)
        return text.contains { set.contains($0) }
    }

    private func splitTokenForValidation(_ token: String) -> (prefix: String, core: String, suffix: String) {
        let chars = Array(token)
        if chars.isEmpty {
            return ("", "", "")
        }

        var start = 0
        while start < chars.count {
            let ch = chars[start]
            if ch.isLetter || ch.isNumber {
                break
            }
            start += 1
        }

        var end = chars.count
        while end > start {
            let ch = chars[end - 1]
            if ch.isLetter || ch.isNumber {
                break
            }
            end -= 1
        }

        let prefix = start > 0 ? String(chars[0..<start]) : ""
        let core = start < end ? String(chars[start..<end]) : ""
        let suffix = end < chars.count ? String(chars[end..<chars.count]) : ""
        return (prefix, core, suffix)
    }

    /// The word the detector looks up in the personal lexicon for a flushed token: the
    /// token without trailing boundary punctuation ("ghbdtn!" → "ghbdtn").
    public static func lexiconWord(from token: String) -> String {
        splitTrailingBoundary(from: token).core
    }

    /// Split trailing punctuation/symbols from a word.
    private func splitTrailingBoundary(from text: String) -> (core: String, trailing: String) {
        Self.splitTrailingBoundary(from: text)
    }

    private static func splitTrailingBoundary(from text: String) -> (core: String, trailing: String) {
        var core = text
        var trailing = ""
        while let last = core.last, isBoundaryChar(last) {
            trailing.insert(last, at: trailing.startIndex)
            core.removeLast()
        }
        return (core, trailing)
    }

    private static func isBoundaryChar(_ char: Character) -> Bool {
        guard let scalar = char.unicodeScalars.first else { return false }
        return boundaryCharacterSet.contains(scalar)
    }
}
