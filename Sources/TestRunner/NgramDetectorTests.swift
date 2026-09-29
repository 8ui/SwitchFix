import Foundation
import Core
import LanguageModel

// LayoutDetector on the n-gram language models (plan/005).

private func ngramDetector(current: Layout, allowed: Set<Layout>) -> LayoutDetector {
    let detector = LayoutDetector()
    detector.allowedLayouts = allowed
    detector.currentLayout = current
    return detector
}

private func detectNgram(_ word: String, current: Layout, allowed: Set<Layout>) -> DetectionResult? {
    let detector = ngramDetector(current: current, allowed: allowed)
    detector.addCharacter(word)
    return detector.flushBuffer(boundaryCharacter: " ")
}

func runNgramDetectorSuites() {
    runSuite("NgramDetector: English words typed on the native layout") {
        for (typed, expected, layout) in [
            ("цщклекуу", "worktree", Layout.russian),
            ("куифыу", "rebase", .russian),
            ("вузутвутсшуі", "dependencies", .ukrainian),
            ("сщььшеі", "commits", .ukrainian),
        ] {
            let result = detectNgram(typed, current: layout, allowed: [.english, layout])
            assertEqual(result?.convertedWord, expected, "\(typed) on \(layout.rawValue)")
            assertEqual(result?.targetLayout, .english, "\(typed) target")
        }
    }

    runSuite("NgramDetector: native words typed on the English layout") {
        for (typed, expected, layout) in [
            ("hf,jnftn", "работает", Layout.russian),
            ("ghbdtn", "привет", .russian),
            ("phj,bkf", "зробила", .ukrainian),
            ("Ghbdtn", "Привет", .russian),
        ] {
            let result = detectNgram(typed, current: .english, allowed: [.english, layout])
            assertEqual(result?.convertedWord, expected, "\(typed) → \(layout.rawValue)")
        }
    }

    runSuite("NgramDetector: correctly typed words stay") {
        for (word, layout) in [
            ("hello", Layout.english), ("worktree", .english), ("deadline", .english),
            ("работает", .russian), ("было", .russian), ("пятницу", .russian),
            ("зробила", .ukrainian), ("дякую", .ukrainian),
        ] {
            let result = detectNgram(word, current: layout, allowed: Set(Layout.allCases))
            assert(result == nil, "\(word) on \(layout.rawValue) must not change, got \(result?.convertedWord ?? "")")
        }
    }

    runSuite("NgramDetector: no automatic Russian ↔ Ukrainian conversion") {
        for word in ["было", "были", "годы", "натуры"] {
            assert(detectNgram(word, current: .russian, allowed: Set(Layout.allCases)) == nil, "\(word) stays Russian")
        }
    }

    runSuite("NgramDetector: short words use the short-word table") {
        assertEqual(detectNgram("yf", current: .english, allowed: [.english, .russian])?.convertedWord, "на")
        assertEqual(detectNgram("ult", current: .english, allowed: [.english, .russian])?.convertedWord, "где")
        assert(detectNgram("go", current: .english, allowed: [.english, .russian]) == nil, "common English short word stays")
        assert(detectNgram("ok", current: .english, allowed: [.english, .ukrainian]) == nil, "ok stays")
        assert(detectNgram("та", current: .ukrainian, allowed: [.english, .ukrainian]) == nil, "common Ukrainian short word stays")
    }

    runSuite("NgramDetector: skipped tokens") {
        for word in ["https://example.com", "user@mail.com", "camelCase", "getValue", "12345", "API", "CI"] {
            assert(detectNgram(word, current: .english, allowed: [.english, .russian]) == nil, "\(word) is skipped")
        }
    }

    runSuite("NgramDetector: Latin target follows the last Cyrillic layout") {
        let detector = ngramDetector(current: .ukrainian, allowed: Set(Layout.allCases))
        detector.currentLayout = .english
        detector.addCharacter("ghbdsn")
        assertEqual(detector.flushBuffer(boundaryCharacter: " ")?.convertedWord, "привіт", "Ukrainian was used last")

        let russian = ngramDetector(current: .russian, allowed: Set(Layout.allCases))
        russian.currentLayout = .english
        russian.addCharacter("ghbdtn")
        assertEqual(russian.flushBuffer(boundaryCharacter: " ")?.convertedWord, "привет", "Russian was used last")
    }

    runSuite("NgramDetector: personal lexicon rules") {
        let lexicon = PersonalLexicon(storage: InMemoryLexiconStorage(), saveDelay: 0)
        func detect(_ word: String, current: Layout, allowed: Set<Layout> = [.english, .russian]) -> DetectionResult? {
            let detector = ngramDetector(current: current, allowed: allowed)
            detector.lexicon = lexicon
            detector.addCharacter(word)
            return detector.flushBuffer(boundaryCharacter: " ")
        }

        assertEqual(detect("ghbdtn", current: .english)?.convertedWord, "привет", "baseline: corrected")
        lexicon.recordRejected(word: "ghbdtn", sourceLayout: .english)
        assert(detect("Ghbdtn", current: .english) == nil, "neverCorrect wins, case-insensitive")

        assert(detect("rehk", current: .english) == nil, "baseline: the typo is not recognized")
        lexicon.recordAccepted(word: "rehk", sourceLayout: .english, target: .russian)
        let learned = detect("Rehk", current: .english)
        assertEqual(learned?.convertedWord, "Курл", "alwaysCorrect converts with case")
        assertEqual(learned?.shouldSwitchLayout, true, "user rule is confident: switch layout")

        _ = lexicon.add(word: "jr", sourceLayout: .english, rule: .alwaysCorrect(to: .russian))
        let short = detect("jr", current: .english)
        assertEqual(short?.convertedWord, "ок", "short words bypass the low-confidence path")
        assertEqual(short?.shouldSwitchLayout, true, "and switch immediately")

        _ = lexicon.add(word: "qwzx", sourceLayout: .english, rule: .alwaysCorrect(to: .ukrainian))
        assert(detect("qwzx", current: .english, allowed: [.english, .russian]) == nil, "target layout not installed → rule ignored")

        _ = lexicon.add(word: "API", sourceLayout: .english, rule: .alwaysCorrect(to: .russian))
        assertEqual(detect("API", current: .english)?.convertedWord, "ФЗШ", "user rule beats the ALLCAPS heuristic")
        assertEqual(lexicon.entries.first { $0.word == "ghbdtn" }?.matchCount, 1, "neverCorrect hits are counted")
    }

    runSuite("NgramDetector: sensitivity") {
        let scorer = NgramMarginScorer(store: .shared)
        // 'hf,jnftn' → 'работает', 8 letters: bucket 7+.
        guard let margin = scorer.margin(typedCore: "hf,jnftn", source: .english, convertedCore: "работает", target: .russian) else {
            return assert(false, "models must load")
        }
        func detect(offset: Double) -> DetectionResult? {
            let detector = ngramDetector(current: .english, allowed: [.english, .russian])
            var thresholds = DetectionThresholds.default
            thresholds.sensitivityOffset = offset
            detector.thresholds = thresholds
            detector.addCharacter("hf,jnftn")
            return detector.flushBuffer(boundaryCharacter: " ")
        }
        let base = DetectionThresholds.default.sevenPlusLetters
        assert(detect(offset: margin - base + 0.5) == nil, "threshold above the margin keeps the word")
        assert(detect(offset: margin - base - 0.5) != nil, "threshold below the margin corrects it")

        let cautious = DetectionThresholds.forSensitivity(0)
        let bold = DetectionThresholds.forSensitivity(4)
        assert(cautious.threshold(forLetterCount: 7)! > DetectionThresholds.forSensitivity(2).threshold(forLetterCount: 7)!, "cautious is stricter")
        assert(bold.threshold(forLetterCount: 7)! >= DetectionThresholds.minimumThreshold, "never below the floor")
        assertEqual(DetectionThresholds.forSensitivity(2), DetectionThresholds.default, "middle position = calibrated defaults")
        assertEqual(DetectionThresholds.forSensitivity(99), DetectionThresholds.forSensitivity(4), "out of range clamps")
    }

    runSuite("DetectionThresholds: calibrated for the bundled models") {
        for language in ModelLanguage.allCases {
            guard let url = LanguageModelStore.resourceURL(for: language),
                  let data = try? Data(contentsOf: url), data.count > 8 else {
                assert(false, "\(language.rawValue).sfng must be bundled")
                continue
            }
            // Each .sfng ends with the little-endian FNV-1a checksum of the bytes before it.
            let checksum = data.suffix(8).enumerated().reduce(UInt64(0)) { $0 | UInt64($1.element) << (8 * UInt64($1.offset)) }
            assertEqual(
                DetectionThresholds.calibratedModelChecksums[language], checksum,
                "\(language.rawValue).sfng changed: rerun `TestRunner --threshold-sweep`, update DetectionThresholds and plan/benchmarks/thresholds_005.md, then this checksum"
            )
        }
    }
}
