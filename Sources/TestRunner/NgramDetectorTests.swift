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

    runSuite("NgramDetector: command-line flags stay") {
        for words in [["ls", "-r"], ["rm", "-r", "-f"], ["tar", "-c", "-z", "-f"], ["cp", "-r", "-d"], ["grep", "-r"], ["-r"], ["--x"], ["ls", "-R"],
                      // Longer flags are not a rule: the model keeps them.
                      ["rm", "-rf"], ["ls", "-la"], ["ls", "-ltr"], ["tar", "-xzf"], ["tar", "-xvzf"], ["rsync", "-avz"],
                      ["git", "commit", "--amend"], ["--force"], ["git", "push", "--force-with-lease"]] {
            let detector = ngramDetector(current: .english, allowed: [.english, .russian])
            let recorder = MockDetectorDelegate()
            detector.delegate = recorder
            for word in words {
                detector.addCharacter(word)
                detector.flushBuffer(boundaryCharacter: " ")
            }
            assert(recorder.results.isEmpty, "\(words.joined(separator: " ")) must stay, got \(recorder.results.map(\.convertedWord))")
        }
        // A bare letter is still corrected: a preposition at the start of a sentence.
        assertEqual(detectNgram("r", current: .english, allowed: [.english, .russian])?.convertedWord, "к")
        // A dash before a longer word is a dialogue line, not a flag.
        assertEqual(detectNgram("-ghbdtn", current: .english, allowed: [.english, .russian])?.convertedWord, "-привет")
        // The hotkey (no boundary) still converts a flag.
        let hotkey = ngramDetector(current: .english, allowed: [.english, .russian])
        hotkey.addCharacter("-r")
        assertEqual(hotkey.flushBuffer(boundaryCharacter: nil)?.convertedWord, "-к", "the hotkey converts a flag")
    }

    runSuite("NgramDetector: index expressions stay") {
        for words in [["obj[0]"], ["w[1]"], ["x[0]."], ["arr[12]"], ["m{1}"], ["print", "a[0],", "b[1]"], ["a[0]"]] {
            let detector = ngramDetector(current: .english, allowed: [.english, .russian])
            let recorder = MockDetectorDelegate()
            detector.delegate = recorder
            for word in words {
                detector.addCharacter(word)
                detector.flushBuffer(boundaryCharacter: " ")
            }
            assert(recorder.results.isEmpty, "\(words.joined(separator: " ")) must stay, got \(recorder.results.map(\.convertedWord))")
        }
        // Without a digit next to a bracket a word is still a word, bracket keys included.
        assertEqual(detectNgram("ghbdtn", current: .english, allowed: [.english, .russian])?.convertedWord, "привет")
        assertEqual(detectNgram("[jhjij", current: .english, allowed: [.english, .russian])?.convertedWord, "хорошо")
        // The hotkey (no boundary) still converts an index expression.
        let hotkey = ngramDetector(current: .english, allowed: [.english, .russian])
        hotkey.addCharacter("w[1]")
        assert(hotkey.flushBuffer(boundaryCharacter: nil) != nil, "the hotkey converts an index expression")

        // Transparent: a flag or an index between two short words keeps the switch confirmation.
        for neutral in ["-r", "w[1]", "-la", "-rf", "--force", "--force-with-lease"] {
            let detector = ngramDetector(current: .english, allowed: [.english, .russian])
            func flush(_ word: String) -> DetectionResult? {
                detector.addCharacter(word)
                return detector.flushBuffer(boundaryCharacter: " ")
            }
            assertEqual(flush("yf")?.shouldSwitchLayout, false, "the first short word waits for a confirmation")
            assert(flush(neutral) == nil, "\(neutral) stays")
            assertEqual(flush("yf")?.shouldSwitchLayout, true, "\(neutral) does not spend the confirmation")

            // A switch cancelled after the neutral word was flushed still gives the confirmation back.
            let late = ngramDetector(current: .english, allowed: [.english, .russian])
            func flushLate(_ word: String) -> DetectionResult? {
                late.addCharacter(word)
                return late.flushBuffer(boundaryCharacter: " ")
            }
            _ = flushLate("yf")
            let second = flushLate("yf")
            assertEqual(second?.shouldSwitchLayout, true, "the second short word confirms the switch")
            assert(flushLate(neutral) == nil, "\(neutral) stays")
            if let second { late.noteCorrectionNotApplied(second.detectionID) }
            assertEqual(flushLate("yf")?.shouldSwitchLayout, true, "after \(neutral) the cancelled switch is restored")
        }
    }

    runSuite("NgramDetector: a correction that never reached the field") {
        func flush(_ detector: LayoutDetector, _ word: String) -> DetectionResult? {
            detector.addCharacter(word)
            return detector.flushBuffer(boundaryCharacter: " ")
        }
        // Context: a cancelled correction no longer counts as corrected.
        func shortWordAfterCorrection(notApplied: Bool) -> DetectionResult? {
            let detector = ngramDetector(current: .russian, allowed: [.english, .russian])
            _ = flush(detector, "сейчас")
            _ = flush(detector, "на")
            let corrected = flush(detector, "цщклы")
            assert(corrected != nil && corrected?.detectionID != 0, "цщклы is corrected with an id")
            if notApplied, let corrected { detector.noteCorrectionNotApplied(corrected.detectionID) }
            return flush(detector, "ше")
        }
        assert(shortWordAfterCorrection(notApplied: false) != nil, "after a correction the short word is corrected")
        assert(shortWordAfterCorrection(notApplied: true) == nil, "after a cancelled one it is kept by the context")

        // Layout switch: a consumed confirmation is given back when nothing was detected since.
        func thirdSwitches(_ between: (LayoutDetector, DetectionResult) -> Void) -> Bool? {
            let detector = ngramDetector(current: .english, allowed: [.english, .russian])
            let first = flush(detector, "yf")
            assert(first?.shouldSwitchLayout == false, "the first short word waits for a confirmation")
            guard let second = flush(detector, "yf") else { return nil }
            assert(second.shouldSwitchLayout, "the second one confirms the switch")
            between(detector, second)
            return flush(detector, "yf")?.shouldSwitchLayout
        }
        assertEqual(thirdSwitches { _, _ in }, false, "without the hook the confirmation is spent")
        assertEqual(thirdSwitches { detector, second in detector.noteCorrectionNotApplied(second.detectionID) }, true,
                    "a cancelled switch gives the confirmation back")
        assertEqual(thirdSwitches { detector, second in
            _ = flush(detector, "hello")
            detector.noteCorrectionNotApplied(second.detectionID)
        }, false, "a later detection makes the switch state current: nothing is restored")
        assertEqual(thirdSwitches { detector, second in
            detector.reset()
            detector.noteCorrectionNotApplied(second.detectionID)
        }, false, "a reset detector is not restored")
        assertEqual(thirdSwitches { detector, _ in detector.noteCorrectionNotApplied(0) }, false, "id 0 is ignored")
    }

    runSuite("NgramDetector: a deferred short word merges only with an adjacent word after a space") {
        func merged(boundary: String, continues: Bool) -> [String] {
            let detector = ngramDetector(current: .russian, allowed: [.english, .russian])
            let recorder = MockDetectorDelegate()
            detector.delegate = recorder
            for word in ["сейчас", "на"] {
                detector.addCharacter(word)
                detector.flushBuffer(boundaryCharacter: " ")
            }
            detector.addCharacter("ше")
            detector.flushBuffer(boundaryCharacter: boundary)
            detector.addCharacter("цщклы")
            detector.flushBuffer(boundaryCharacter: " ", continuesPreviousWord: continues)
            return recorder.results.map(\.originalWord)
        }
        assertEqual(merged(boundary: " ", continues: true), ["ше цщклы"], "typed right after, one space")
        assertEqual(merged(boundary: " ", continues: false), ["цщклы"], "not adjacent: only the current word")
        assertEqual(merged(boundary: "\n", continues: true), ["цщклы"], "Enter is never a bridge")

        // A flush with no letters in between (symbols only) still consumes the deferred word.
        let detector = ngramDetector(current: .russian, allowed: [.english, .russian])
        let recorder = MockDetectorDelegate()
        detector.delegate = recorder
        for word in ["сейчас", "на", "ше", "^!", "цщклы"] {
            detector.addCharacter(word)
            detector.flushBuffer(boundaryCharacter: " ")
        }
        assertEqual(recorder.results.map(\.originalWord), ["цщклы"], "no merge across a symbols-only flush")
    }

    runSuite("NgramDetector: 3-letter word stays in a strong native context") {
        func results(_ words: [String], boundary: String? = " ") -> [DetectionResult] {
            let detector = ngramDetector(current: .ukrainian, allowed: [.english, .ukrainian])
            let recorder = MockDetectorDelegate()
            detector.delegate = recorder
            for (index, word) in words.enumerated() {
                detector.addCharacter(word)
                detector.flushBuffer(boundaryCharacter: index == words.count - 1 ? boundary : " ")
            }
            return recorder.results
        }
        assert(results(["в", "нову", "еру"]).isEmpty, "'еру' after Ukrainian words stays")
        assert(results(["в", "нову", "еру", "фтв"]).isEmpty, "a kept word does not count toward the next word's switch")
        // Edge punctuation does not make a short word long ('(еру)' is as short as 'еру').
        assert(results(["в", "нову", "(еру)"]).isEmpty, "'(еру)' after Ukrainian words stays")
        assertEqual(results(["(еру)"]).first?.convertedWord, "(the", "isolated '(еру)' is still corrected")
        assert(results(["на", "еру"]).count == 1, "one short context word is not strong context")
        assertEqual(results(["еру"]).first?.convertedWord, "the", "isolated 'еру' is still corrected")
        assertEqual(results(["в", "нову", "еру"], boundary: nil).first?.convertedWord, "the", "the hotkey still converts")
    }

    // English words with a stray edge symbol: markdown split into words ('[click', 'here]'),
    // inline code ('`git', '`code`,'), elisions ("'em"), HTML ('div>'), indices ('list[').
    runSuite("NgramDetector: English words with an edge symbol stay") {
        guard let text = try? String(contentsOfFile: "Tests/LayoutEval/en.txt", encoding: .utf8) else {
            assert(false, "Tests/LayoutEval/en.txt must be readable (run from the repo root)")
            return
        }
        var seen = Set<String>()
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init).filter {
            $0.allSatisfy { $0.isASCII && $0.isLetter } && seen.insert($0).inserted
        }
        let forms: [(String, (String) -> String)] = [
            ("w[", { $0 + "[" }), ("w]", { $0 + "]" }), ("[w", { "[" + $0 }), ("`w", { "`" + $0 }),
            ("w`", { $0 + "`" }), ("'w", { "'" + $0 }), ("w>", { $0 + ">" }), ("w']", { $0 + "']" }),
            ("`w`,", { "`" + $0 + "`," }), ("[w].", { "[" + $0 + "]." }), ("'w'", { "'" + $0 + "'" }),
            ("[[w]]", { "[[" + $0 + "]]" }),
        ]
        // 'to`' is 'ещё' on the Russian layout: inline code ending in 'to' loses to the
        // most common word it collides with.
        let expected: Set<String> = ["to`"]
        for native in [Layout.russian, .ukrainian] {
            var converted = 0, total = 0
            var examples: [String] = []
            for (_, form) in forms {
                for word in words {
                    total += 1
                    let token = form(word)
                    if let result = detectNgram(token, current: .english, allowed: [.english, native]),
                       !expected.contains(token) {
                        converted += 1
                        if examples.count < 8 { examples.append("\(token)→\(result.convertedWord)") }
                    }
                }
            }
            assert(converted == 0, "English words with an edge symbol converted on \(native.rawValue): \(converted)/\(total), e.g. \(examples.joined(separator: ", "))")
        }
    }

    // х ъ ж э б ю ё (ї є і ґ) sit on , . ; ' [ ] ` \ — the keys English uses for punctuation.
    runSuite("NgramDetector: letters on punctuation keys at word edges") {
        for (typed, expected, layout) in [
            ("yfib[", "наших", Layout.russian), ("to`", "ещё", .russian), ("dc`", "всё", .russian),
            ("pyf.", "знаю", .russian), ("ltkf.", "делаю", .russian), ("uhb,", "гриб", .russian),
            (",eltn", "будет", .russian), ("'nb[", "этих", .russian), (";tyf", "жена", .russian),
            ("[jhjij", "хорошо", .russian), ("`krf", "ёлка", .russian), (".hbcn", "юрист", .russian),
            ("gjl]tpl", "подъезд", .russian),
            ("rhf]", "краї", .ukrainian), ("cdj'", "своє", .ukrainian), ("ljhjuj.", "дорогою", .ukrainian),
        ] {
            let result = detectNgram(typed, current: .english, allowed: [.english, layout])
            assertEqual(result?.convertedWord, expected, "\(typed) → \(layout.rawValue)")
        }
        for (word, layout) in [
            ("hello.", Layout.russian), ("hello,", .russian), ("done;", .russian), ("items[", .russian),
            ("don't", .russian), ("it's", .ukrainian), ("world.", .ukrainian), ("thanks,", .ukrainian),
            ("to.", .russian), ("to,", .russian), ("in:", .russian), ("(to", .russian), ("\"to\"", .russian),
            (".env", .russian), (".gitignore", .russian), ("'hello'", .russian), ("[link]", .russian), ("`code`", .russian), ("{key}", .russian), ("<tag>", .russian),
            ("here]", .russian), ("here]", .ukrainian), ("[click", .russian), ("list[", .russian), ("`git", .russian),
            ("status`", .ukrainian), ("'em", .russian), ("'til", .russian), ("div>", .russian), ("see[1]", .russian), ("see[1]", .ukrainian), ("fig[1]", .russian),
            ("fig[1]", .ukrainian), ("page[2]", .ukrainian), ("f(x)", .russian),
            ("`code`,", .russian), ("[link].", .russian), ("'word'.", .russian), ("to!", .russian),
        ] {
            let result = detectNgram(word, current: .english, allowed: [.english, layout])
            assert(result == nil, "\(word) must stay, got \(result?.convertedWord ?? "")")
        }
    }
}
