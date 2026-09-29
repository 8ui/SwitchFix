import Foundation
import Core

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
}
