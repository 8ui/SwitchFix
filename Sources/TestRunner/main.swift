import Foundation
import Core

// Simple test runner — no XCTest dependency required
var passed = 0
var failed = 0

func assert(_ condition: Bool, _ message: String, file: String = #file, line: Int = #line) {
    if condition {
        passed += 1
    } else {
        failed += 1
        print("  FAIL: \(message) (\(file):\(line))")
    }
}

func assertEqual<T: Equatable>(_ a: T, _ b: T, _ message: String = "", file: String = #file, line: Int = #line) {
    if a == b {
        passed += 1
    } else {
        failed += 1
        print("  FAIL: expected \(b), got \(a). \(message) (\(file):\(line))")
    }
}

func runSuite(_ name: String, _ block: () -> Void) {
    print("--- \(name) ---")
    block()
}

// `--threshold-sweep`: report-only threshold/sensitivity calibration (plan/005 §4.6).
if CommandLine.arguments.contains("--threshold-sweep") {
    runThresholdSweep()
    exit(0)
}

// `--layout-eval-only`: run just the real-text layout-detection eval (plan/005).
if CommandLine.arguments.contains("--layout-eval-only") {
    runLayoutEvalSuites()
    print("\n========================================")
    print("Results: \(passed) passed, \(failed) failed")
    exit(failed > 0 ? 1 : 0)
}

// =============================================================================
// LayoutMapper Tests
// =============================================================================

runSuite("LayoutMapper: EN → RU") {
    assertEqual(LayoutMapper.convert("ghbdtn", from: .english, to: .russian), "привет")
    assertEqual(LayoutMapper.convert("hello", from: .english, to: .russian), "руддщ")
    assertEqual(LayoutMapper.convert("Ghbdtn", from: .english, to: .russian), "Привет")
}

runSuite("LayoutMapper: RU → EN") {
    assertEqual(LayoutMapper.convert("руддщ", from: .russian, to: .english), "hello")
    assertEqual(LayoutMapper.convert("привет", from: .russian, to: .english), "ghbdtn")
}

runSuite("LayoutMapper: EN → UK") {
    assertEqual(LayoutMapper.convert("ghbdsn", from: .english, to: .ukrainian), "привіт")
}

runSuite("LayoutMapper: UK → EN") {
    assertEqual(LayoutMapper.convert("привіт", from: .ukrainian, to: .english), "ghbdsn")
    assertEqual(LayoutMapper.convert("пшерги", from: .ukrainian, to: .english), "github")
}

runSuite("LayoutMapper: codex EN ↔ UK") {
    assertEqual(LayoutMapper.convert("codex", from: .english, to: .ukrainian), "сщвуч")
    assertEqual(LayoutMapper.convert("сщвуч", from: .ukrainian, to: .english), "codex")
}

runSuite("LayoutMapper: Same layout") {
    assertEqual(LayoutMapper.convert("hello", from: .english, to: .english), "hello")
}

runKeyTableTests()

runSuite("Layout: input source ID matching") {
    func layout(_ id: String) -> Layout? { Layout.allCases.first { $0.matches(sourceID: id) } }
    for id in ["US", "ABC", "British", "British-PC", "Australian", "Canadian", "Irish", "IrishExtended"] {
        assertEqual(layout("com.apple.keylayout.\(id)"), .english, "\(id) is an English QWERTY layout")
    }
    assertEqual(layout("com.apple.keylayout.RussianWin"), .russian)
    assertEqual(layout("com.apple.keylayout.Ukrainian-PC"), .ukrainian)
    // Non-QWERTY Latin layouts put letters on other keys; LayoutMapper would mistranslate them.
    assertEqual(layout("com.apple.keylayout.German"), nil)
    assertEqual(layout("com.apple.keylayout.French"), nil)
    assertEqual(layout("com.apple.keylayout.Canadian-CSA"), nil, "French Canadian must not match the Canadian suffix")
}

runSuite("LayoutMapper: Alternatives") {
    let results = LayoutMapper.convertToAlternatives("ghbdtn", from: .english)
    assert(results.contains(where: { $0.0 == .russian && $0.1 == "привет" }), "alternatives should include russian 'привет'")
}

runSuite("LayoutMapper: Special chars EN→RU") {
    assertEqual(LayoutMapper.convert(";", from: .english, to: .russian), "ж")
    assertEqual(LayoutMapper.convert("'", from: .english, to: .russian), "э")
    assertEqual(LayoutMapper.convert("`", from: .english, to: .russian), "ё")
}

runSuite("LayoutMapper: Special chars RU→EN") {
    assertEqual(LayoutMapper.convert("ж", from: .russian, to: .english), ";")
    assertEqual(LayoutMapper.convert("э", from: .russian, to: .english), "'")
    assertEqual(LayoutMapper.convert("ё", from: .russian, to: .english), "`")
    assertEqual(LayoutMapper.convert("ЖЭЁ", from: .russian, to: .english), ":\"~")
}

runSuite("LayoutMapper: Special chars EN→UK") {
    assertEqual(LayoutMapper.convert("'", from: .english, to: .ukrainian), "є")
    assertEqual(LayoutMapper.convert("]", from: .english, to: .ukrainian), "ї")
    assertEqual(LayoutMapper.convert("`", from: .english, to: .ukrainian), "ґ")
}

runSuite("LayoutMapper: Unmapped chars preserved") {
    assertEqual(LayoutMapper.convert("hello123", from: .english, to: .russian), "руддщ123")
}

// =============================================================================
// LayoutDetector Tests
// =============================================================================

// Helper: Mock delegate that captures detection results
class MockDetectorDelegate: LayoutDetectorDelegate {
    var results: [DetectionResult] = []
    var boundaryCharacters: [String?] = []
    func layoutDetector(_ detector: LayoutDetector, didDetectWrongLayout result: DetectionResult, boundaryCharacter: String?) {
        results.append(result)
        boundaryCharacters.append(boundaryCharacter)
    }
}

runSuite("LayoutDetector: Detect EN→RU wrong layout") {
    let detector = LayoutDetector()
    let mockDelegate = MockDetectorDelegate()
    detector.delegate = mockDelegate
    detector.currentLayout = .english

    // Type "ghbdtn" (which is "привет" in wrong layout)
    for char in "ghbdtn" {
        detector.addCharacter(String(char))
    }
    detector.flushBuffer()

    assert(mockDelegate.results.count == 1, "should detect one wrong layout")
    if let result = mockDelegate.results.first {
        assertEqual(result.targetLayout, .russian, "target should be Russian")
        assertEqual(result.convertedWord, "привет", "converted should be 'привет'")
    }
}

runSuite("LayoutDetector: Unlikely word is not corrected") {
    let detector = LayoutDetector()
    let mockDelegate = MockDetectorDelegate()
    detector.delegate = mockDelegate
    detector.currentLayout = .english
    for char in "pdhdp" {
        detector.addCharacter(String(char))
    }
    detector.flushBuffer(boundaryCharacter: " ")

    assertEqual(mockDelegate.results.count, 0, "an unlikely word must not be corrected")
}

runSuite("LayoutDetector: Avoid aggressive EN→UK typo suggestion") {
    let detector = LayoutDetector()
    let mockDelegate = MockDetectorDelegate()
    detector.delegate = mockDelegate
    detector.currentLayout = .english
    for char in "fethc" {
        detector.addCharacter(String(char))
    }
    detector.flushBuffer(boundaryCharacter: " ")

    assertEqual(mockDelegate.results.count, 0, "should not auto-correct 'fethc' to unrelated Ukrainian word")
}

runSuite("LayoutDetector: Do not suggest for vowel-rich English words") {
    let detector = LayoutDetector()
    let mockDelegate = MockDetectorDelegate()
    detector.delegate = mockDelegate
    detector.currentLayout = .english

    for char in "only" {
        detector.addCharacter(String(char))
    }
    detector.flushBuffer(boundaryCharacter: " ")

    assertEqual(mockDelegate.results.count, 0, "should not auto-correct 'only' to Ukrainian suggestions")
}

runSuite("LayoutDetector: English 'after' stays") {
    let detector = LayoutDetector()
    let mockDelegate = MockDetectorDelegate()
    detector.delegate = mockDelegate
    detector.currentLayout = .english

    for char in "after" {
        detector.addCharacter(String(char))
    }
    detector.flushBuffer(boundaryCharacter: " ")

    assertEqual(mockDelegate.results.count, 0, "should not convert 'after' to Ukrainian")
}

runSuite("LayoutDetector: Convert English 'Ot' to Ukrainian 'Ще' short word") {
    let detector = LayoutDetector()
    let mockDelegate = MockDetectorDelegate()
    detector.delegate = mockDelegate
    detector.currentLayout = .english

    for char in "Ot" {
        detector.addCharacter(String(char))
    }
    detector.flushBuffer(boundaryCharacter: " ")

    assertEqual(mockDelegate.results.count, 1, "should convert short whitelisted Ukrainian word")
    if let result = mockDelegate.results.first {
        assertEqual(result.targetLayout, .ukrainian, "target should be Ukrainian")
        assertEqual(result.convertedWord, "Ще", "should convert to 'Ще'")
    }
}

runSuite("LayoutDetector: Convert Ukrainian 'фаеук' to English 'after'") {
    let detector = LayoutDetector()
    let mockDelegate = MockDetectorDelegate()
    detector.delegate = mockDelegate
    detector.currentLayout = .ukrainian

    for char in "фаеук" {
        detector.addCharacter(String(char))
    }
    detector.flushBuffer(boundaryCharacter: " ")

    assertEqual(mockDelegate.results.count, 1, "should convert wrong-layout Ukrainian buffer to English")
    if let result = mockDelegate.results.first {
        assertEqual(result.targetLayout, .english, "target should be English")
        assertEqual(result.convertedWord, "after", "should convert to 'after'")
    }
}

runSuite("LayoutDetector: Convert English 'gjlsdsvjcm' to Ukrainian 'подивимось'") {
    let detector = LayoutDetector()
    let mockDelegate = MockDetectorDelegate()
    detector.delegate = mockDelegate
    detector.currentLayout = .english
    detector.keyboardTables = .pc.with(.ukrainian, [.pcUkrainianLegacy, .pcUkrainian])

    for char in "gjlsdsvjcm" {
        detector.addCharacter(String(char))
    }
    detector.flushBuffer(boundaryCharacter: " ")

    assertEqual(mockDelegate.results.count, 1, "should convert to 'подивимось'")
    if let result = mockDelegate.results.first {
        assertEqual(result.targetLayout, .ukrainian, "target should be Ukrainian")
        assertEqual(result.convertedWord, "подивимось", "should convert to 'подивимось'")
    }
}

runSuite("LayoutDetector: Convert Ukrainian 'учзусеув' to English 'expected'") {
    let detector = LayoutDetector()
    let mockDelegate = MockDetectorDelegate()
    detector.delegate = mockDelegate
    detector.currentLayout = .ukrainian

    for char in "учзусеув" {
        detector.addCharacter(String(char))
    }
    detector.flushBuffer(boundaryCharacter: " ")

    assertEqual(mockDelegate.results.count, 1, "should convert to 'expected'")
    if let result = mockDelegate.results.first {
        assertEqual(result.targetLayout, .english, "target should be English")
        assertEqual(result.convertedWord, "expected", "should convert to 'expected'")
    }
}

runSuite("LayoutDetector: Convert Ukrainian 'сщвуч' to English 'codex'") {
    let detector = LayoutDetector()
    let mockDelegate = MockDetectorDelegate()
    detector.delegate = mockDelegate
    detector.currentLayout = .ukrainian

    for char in "сщвуч" {
        detector.addCharacter(String(char))
    }
    detector.flushBuffer(boundaryCharacter: " ")

    assertEqual(mockDelegate.results.count, 1, "should convert to 'codex'")
    if let result = mockDelegate.results.first {
        assertEqual(result.targetLayout, .english, "target should be English")
        assertEqual(result.convertedWord, "codex", "should convert to 'codex'")
    }
}

runSuite("LayoutDetector: Convert Ukrainian 'ершиЖ' to English 'this:'") {
    let detector = LayoutDetector()
    let mockDelegate = MockDetectorDelegate()
    detector.delegate = mockDelegate
    detector.currentLayout = .ukrainian
    // Legacy Ukrainian: 'ерши' is 'this'; shifted 'Ж' is the colon key, not part of an identifier.
    detector.keyboardTables = .pc.with(.ukrainian, [.pcUkrainianLegacy, .pcUkrainian])

    for char in "ершиЖ" {
        detector.addCharacter(String(char))
    }
    detector.flushBuffer(boundaryCharacter: " ")

    assertEqual(mockDelegate.results.count, 1, "should convert legacy Ukrainian typed 'this:'")
    if let result = mockDelegate.results.first {
        assertEqual(result.targetLayout, .english, "target should be English")
        assertEqual(result.convertedWord, "this:", "should preserve trailing colon")
    }
}

runSuite("LayoutDetector: Convert Ukrainian 'дуе' to English 'let'") {
    let detector = LayoutDetector()
    let mockDelegate = MockDetectorDelegate()
    detector.delegate = mockDelegate
    detector.currentLayout = .ukrainian

    for char in "дуе" {
        detector.addCharacter(String(char))
    }
    detector.flushBuffer(boundaryCharacter: " ")

    assertEqual(mockDelegate.results.count, 1, "should detect wrong layout for 'дуе'")
    if let result = mockDelegate.results.first {
        assertEqual(result.sourceLayout, .ukrainian, "source should be Ukrainian")
        assertEqual(result.targetLayout, .english, "target should be English")
        assertEqual(result.convertedWord, "let", "should convert 'дуе' to 'let'")
    }
}

runSuite("LayoutDetector: Legacy Ukrainian variant converts to English") {
    let detector = LayoutDetector()
    let mockDelegate = MockDetectorDelegate()
    detector.delegate = mockDelegate
    detector.currentLayout = .ukrainian
    // The user's own variant decides; the fallback variant must not beat the primary
    // one on score alone ('Иууьи' on standard reads as 'Beemb', see commit 592ea8c).
    detector.keyboardTables = .pc.with(.ukrainian, [.pcUkrainianLegacy, .pcUkrainian])

    for char in "Иууьи" {
        detector.addCharacter(String(char))
    }
    detector.flushBuffer(boundaryCharacter: " ")

    assertEqual(mockDelegate.results.count, 1, "legacy-variant word should convert")
    if let result = mockDelegate.results.first {
        assertEqual(result.targetLayout, .english, "target should be English")
        assertEqual(result.convertedWord, "Seems", "should convert to 'Seems'")
    }
}

runSuite("LayoutDetector: Acronym fallback preserves case") {
    let detector = LayoutDetector()
    let mockDelegate = MockDetectorDelegate()
    detector.delegate = mockDelegate
    detector.currentLayout = .english

    for char in "CR" {
        detector.addCharacter(String(char))
    }
    detector.flushBuffer()

    assert(mockDelegate.results.count == 1, "should detect acronym fallback")
    if let result = mockDelegate.results.first {
        assertEqual(result.convertedWord, "СК", "should preserve uppercase mapping")
    }
}

runSuite("LayoutDetector: All-caps English token is not auto-corrected") {
    let detector = LayoutDetector()
    let mockDelegate = MockDetectorDelegate()
    detector.delegate = mockDelegate
    detector.currentLayout = .english

    for char in "GDPR" {
        detector.addCharacter(String(char))
    }
    detector.flushBuffer(boundaryCharacter: " ")

    assertEqual(mockDelegate.results.count, 0, "all-caps English acronym should not auto-correct to Cyrillic")
}

runSuite("LayoutDetector: Acronym fallback suppressed in strong current context") {
    let detector = LayoutDetector()
    let mockDelegate = MockDetectorDelegate()
    detector.delegate = mockDelegate
    detector.currentLayout = .english

    func typeWord(_ word: String) {
        for char in word {
            detector.addCharacter(String(char))
        }
        detector.flushBuffer(boundaryCharacter: " ")
    }

    typeWord("another")
    typeWord("issue")
    typeWord("with")
    typeWord("DB")

    assertEqual(mockDelegate.results.count, 0, "acronym should not auto-correct inside strong English context")
}

runSuite("LayoutDetector: Valid word does not trigger") {
    let detector = LayoutDetector()
    let mockDelegate = MockDetectorDelegate()
    detector.delegate = mockDelegate
    detector.currentLayout = .english

    // Type "hello" (valid English word)
    for char in "hello" {
        detector.addCharacter(String(char))
    }
    detector.flushBuffer()

    assertEqual(mockDelegate.results.count, 0, "valid word should not trigger detection")
}

runSuite("LayoutDetector: Mixed scripts ignored") {
    let detector = LayoutDetector()
    let mockDelegate = MockDetectorDelegate()
    detector.delegate = mockDelegate
    detector.currentLayout = .english

    // Mixed Latin+Cyrillic should be ignored
    for char in "heллo" {
        detector.addCharacter(String(char))
    }
    detector.flushBuffer()

    assertEqual(mockDelegate.results.count, 0, "mixed scripts should not trigger detection")
}

runSuite("LayoutDetector: Delete removes from buffer") {
    let detector = LayoutDetector()

    for char in "hello" {
        detector.addCharacter(String(char))
    }
    assertEqual(detector.currentBuffer, "hello")
    detector.deleteLastCharacter()
    assertEqual(detector.currentBuffer, "hell")
    detector.deleteLastCharacter()
    assertEqual(detector.currentBuffer, "hel")
}

runSuite("LayoutDetector: Reset clears state") {
    let detector = LayoutDetector()
    for char in "hello" {
        detector.addCharacter(String(char))
    }
    detector.reset()
    assertEqual(detector.currentBuffer, "", "buffer should be empty after reset")
}

runSuite("LayoutDetector: Suppress ambiguous short correction in Ukrainian context") {
    let detector = LayoutDetector()
    let mockDelegate = MockDetectorDelegate()
    detector.delegate = mockDelegate
    detector.currentLayout = .ukrainian

    func typeWord(_ word: String) {
        for char in word {
            detector.addCharacter(String(char))
        }
        detector.flushBuffer(boundaryCharacter: " ")
    }

    typeWord("зараз")
    typeWord("ссилка")
    typeWord("на")
    typeWord("мейл")
    typeWord("ше")

    assertEqual(mockDelegate.results.count, 0, "short ambiguous word should not be auto-corrected inside a strong Ukrainian context")
}

runSuite("LayoutDetector: Isolated ambiguous short word can still correct") {
    let detector = LayoutDetector()
    let mockDelegate = MockDetectorDelegate()
    detector.delegate = mockDelegate
    detector.currentLayout = .ukrainian

    for char in "ше" {
        detector.addCharacter(String(char))
    }
    detector.flushBuffer(boundaryCharacter: " ")

    assertEqual(mockDelegate.results.count, 1, "isolated short wrong-layout word should still be corrected")
    if let result = mockDelegate.results.first {
        assertEqual(result.convertedWord, "it", "expected keyboard-layout conversion to English")
    }
}

runSuite("LayoutDetector: Merge suppressed short word when next word confirms layout") {
    let detector = LayoutDetector()
    let mockDelegate = MockDetectorDelegate()
    detector.delegate = mockDelegate
    detector.currentLayout = .ukrainian
    detector.keyboardTables = .pc.with(.ukrainian, [.pcUkrainianLegacy, .pcUkrainian])

    func typeWord(_ word: String) {
        for char in word {
            detector.addCharacter(String(char))
        }
        detector.flushBuffer(boundaryCharacter: " ")
    }

    // Build a strong Ukrainian context first, so "ше" is suppressed as ambiguous.
    typeWord("зараз")
    typeWord("на")

    for char in "ше" {
        detector.addCharacter(String(char))
    }
    detector.flushBuffer(boundaryCharacter: " ")
    assertEqual(mockDelegate.results.count, 0, "first ambiguous short word should stay pending")

    for char in "цщкли" {
        detector.addCharacter(String(char))
    }
    detector.flushBuffer(boundaryCharacter: " ")

    assertEqual(mockDelegate.results.count, 1, "detector should emit a single merged correction")
    if let result = mockDelegate.results.first {
        assertEqual(result.originalWord, "ше цщкли", "should delete both words in one correction")
        assertEqual(result.convertedWord, "it works", "should restore intended English phrase")
    }
}

runSuite("LayoutDetector: Reset drops suppressed cross-context history") {
    let detector = LayoutDetector()
    let mockDelegate = MockDetectorDelegate()
    detector.delegate = mockDelegate
    detector.currentLayout = .ukrainian
    detector.keyboardTables = .pc.with(.ukrainian, [.pcUkrainianLegacy, .pcUkrainian])

    func typeWord(_ word: String) {
        for char in word {
            detector.addCharacter(String(char))
        }
        detector.flushBuffer(boundaryCharacter: " ")
    }

    typeWord("зараз")
    typeWord("на")
    typeWord("ше")
    assertEqual(mockDelegate.results.count, 0, "ambiguous short word should be pending before reset")

    detector.reset()
    typeWord("цщкли")

    assertEqual(mockDelegate.results.count, 1, "new context should correct only its own word")
    if let result = mockDelegate.results.first {
        assertEqual(result.originalWord, "цщкли", "reset must not merge text from an earlier context")
        assertEqual(result.convertedWord, "works", "current-context conversion should remain intact")
    }
}

// =============================================================================
// Character n-gram language model (plan/005)
// =============================================================================

runPersonalLexiconSuites()
runLanguageModelSuites()
runNgramDetectorSuites()

// =============================================================================
// Layout-detection eval on real text (report-only, see Tests/LayoutEval)
// =============================================================================

runLayoutEvalSuites()

// =============================================================================
// Summary
// =============================================================================

print("\n========================================")
print("Results: \(passed) passed, \(failed) failed")
if failed > 0 {
    print("TESTS FAILED")
    exit(1)
} else {
    print("ALL TESTS PASSED")
}
