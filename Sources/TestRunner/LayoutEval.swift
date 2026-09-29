import Foundation
import Core

// Layout-detection eval on real text (plan/005, Phase 0).
//
// Report-only: prints recall / false-positive tables for the current detector so
// that any replacement (the n-gram model) can be compared on the same data. Data
// lives in Tests/LayoutEval (see README.md there); run from the repo root.
//
//   swift run -c release TestRunner --layout-eval-only

private let evalLanguages: [Layout] = [.english, .russian, .ukrainian]

private func evalCode(_ layout: Layout) -> String {
    switch layout {
    case .english: return "en"
    case .russian: return "ru"
    case .ukrainian: return "uk"
    }
}

private func evalLayout(code: String) -> Layout? {
    switch code {
    case "en": return .english
    case "ru": return .russian
    case "uk": return .ukrainian
    default: return nil
    }
}

/// Layouts a word of `language` can plausibly be mistyped on (other script only).
private func wrongLayouts(for language: Layout) -> [Layout] {
    language == .english ? [.russian, .ukrainian] : [.english]
}

private enum EvalConfig: CaseIterable {
    /// All three layouts installed (both Cyrillic layouts compete).
    case all
    /// Only English plus the Cyrillic layout involved.
    case pair

    var name: String {
        switch self {
        case .all: return "en+ru+uk"
        case .pair: return "en+one"
        }
    }

    func allowedLayouts(language: Layout, typedOn: Layout) -> Set<Layout> {
        switch self {
        case .all:
            return Set(Layout.allCases)
        case .pair:
            let cyrillic = language == .english ? typedOn : language
            return [.english, cyrillic]
        }
    }
}

private let lengthBuckets: [(name: String, range: ClosedRange<Int>)] = [
    ("1", 1...1),
    ("2-3", 2...3),
    ("4-5", 4...5),
    ("6+", 6...Int.max),
]

private func bucketIndex(for word: String) -> Int {
    let length = word.filter(\.isLetter).count
    return lengthBuckets.firstIndex { $0.range.contains(length) } ?? 0
}

private func isLatinLetter(_ scalar: Unicode.Scalar) -> Bool {
    (0x41...0x5A).contains(scalar.value) || (0x61...0x7A).contains(scalar.value)
}

private func isCyrillicLetter(_ scalar: Unicode.Scalar) -> Bool {
    (0x400...0x4FF).contains(scalar.value)
}

private func isLetter(_ character: Character, of language: Layout) -> Bool {
    guard character.unicodeScalars.count == 1, let scalar = character.unicodeScalars.first else {
        return false
    }
    return language == .english ? isLatinLetter(scalar) : isCyrillicLetter(scalar)
}

/// Words of the language's script: letter runs with inner apostrophes/hyphens.
/// Tokens touching other characters (digits, other scripts) are dropped.
private func tokenize(_ sentence: String, language: Layout) -> [String] {
    var tokens: [String] = []
    for chunk in sentence.split(whereSeparator: { $0.isWhitespace }) {
        var current = ""
        var tainted = false
        var chars = Array(chunk)
        // Strip surrounding punctuation.
        while let first = chars.first, !first.isLetter, !first.isNumber { chars.removeFirst() }
        while let last = chars.last, !last.isLetter, !last.isNumber { chars.removeLast() }
        for (index, ch) in chars.enumerated() {
            if isLetter(ch, of: language) {
                current.append(ch)
            } else if "'’-".contains(ch), !current.isEmpty, index + 1 < chars.count,
                      isLetter(chars[index + 1], of: language) {
                current.append(ch == "’" ? "'" : ch)
            } else {
                tainted = true
            }
        }
        if !tainted && !current.isEmpty {
            tokens.append(current)
        }
    }
    return tokens
}

private func loadSentences(_ language: Layout) -> [[String]] {
    let path = FileManager.default.currentDirectoryPath + "/Tests/LayoutEval/\(evalCode(language)).txt"
    guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
        print("  WARN: could not read eval sentences at \(path)")
        return []
    }
    return content
        .split(whereSeparator: \.isNewline)
        .map { tokenize(String($0), language: language) }
        .filter { !$0.isEmpty }
}

private func makeDetector(current: Layout, allowed: Set<Layout>) -> LayoutDetector {
    let detector = LayoutDetector()
    detector.currentLayout = current
    detector.allowedLayouts = allowed
    return detector
}

/// Mirrors `InputEngine.runDetection`: one word per flush, space as boundary.
private func detect(_ detector: LayoutDetector, word: String, current: Layout) -> DetectionResult? {
    detector.currentLayout = current
    detector.discardBuffer()
    detector.addCharacter(word)
    return detector.flushBuffer(boundaryCharacter: " ")
}

private func typedForm(of word: String, language: Layout, on layout: Layout) -> String {
    layout == language ? word : LayoutMapper.convert(word, from: language, to: layout)
}

/// A mistyping is only reachable when the key mapping round-trips.
private func isReachable(_ word: String, language: Layout, on layout: Layout) -> Bool {
    let typed = typedForm(of: word, language: language, on: layout)
    return typed != word && LayoutMapper.convert(typed, from: layout, to: language) == word
}

private func restores(_ result: DetectionResult, to word: String, language: Layout) -> Bool {
    result.targetLayout == language && result.convertedWord.lowercased() == word.lowercased()
}

private func pct(_ part: Int, _ total: Int) -> String {
    guard total > 0 else { return "—" }
    return String(format: "%.2f%%", Double(part) * 100 / Double(total))
}

private struct WrongTally {
    var total = 0
    var fixed = 0
    var wrongFix = 0
    var unreachable = 0
    var missed: Int { total - fixed - wrongFix }
}

private struct CorrectTally {
    var total = 0
    var falsePositives = 0
}

// MARK: - Isolated words

private func runIsolatedEval(sentences: [Layout: [[String]]]) {
    for config in EvalConfig.allCases {
        runSuite("LayoutEval: isolated words, layouts \(config.name)") {
            var timings: [Double] = []
            print("")
            print("| case | " + lengthBuckets.map(\.name).joined(separator: " | ") + " | all |")
            print("|---|" + String(repeating: "---|", count: lengthBuckets.count + 1))

            for language in evalLanguages {
                let words = sentences[language, default: []].flatMap { $0 }

                // Correctly typed words must stay untouched.
                var correct = Array(repeating: CorrectTally(), count: lengthBuckets.count)
                var correctSamples: [String] = []
                let correctAllowed = config == .all
                    ? Set(Layout.allCases)
                    : config.allowedLayouts(language: language, typedOn: wrongLayouts(for: language)[0])
                let correctDetector = makeDetector(current: language, allowed: correctAllowed)
                for word in words {
                    correctDetector.reset()
                    let start = ContinuousClock.now
                    let result = detect(correctDetector, word: word, current: language)
                    let elapsed = start.duration(to: .now)
                    timings.append(Double(elapsed.components.attoseconds) / 1e12)
                    let bucket = bucketIndex(for: word)
                    correct[bucket].total += 1
                    if let result {
                        correct[bucket].falsePositives += 1
                        if correctSamples.count < 12 {
                            correctSamples.append("\(word)→\(result.convertedWord)")
                        }
                    }
                }
                let correctTotal = correct.reduce(CorrectTally()) {
                    CorrectTally(total: $0.total + $1.total, falsePositives: $0.falsePositives + $1.falsePositives)
                }
                let fpCells = correct.map { "\(pct($0.falsePositives, $0.total)) (\($0.falsePositives)/\($0.total))" }
                print("| \(evalCode(language)) typed correctly — false positives | " + fpCells.joined(separator: " | ")
                      + " | \(pct(correctTotal.falsePositives, correctTotal.total)) |")
                if !correctSamples.isEmpty {
                    print("|   ↳ e.g. " + correctSamples.joined(separator: ", ") + " | | | | | |")
                }

                // Words typed on the wrong layout must be restored.
                for layout in wrongLayouts(for: language) {
                    var wrong = Array(repeating: WrongTally(), count: lengthBuckets.count)
                    var missedSamples: [String] = []
                    let detector = makeDetector(
                        current: layout,
                        allowed: config.allowedLayouts(language: language, typedOn: layout)
                    )
                    for word in words {
                        let bucket = bucketIndex(for: word)
                        guard isReachable(word, language: language, on: layout) else {
                            wrong[bucket].unreachable += 1
                            continue
                        }
                        detector.reset()
                        let typed = typedForm(of: word, language: language, on: layout)
                        let result = detect(detector, word: typed, current: layout)
                        wrong[bucket].total += 1
                        if let result {
                            if restores(result, to: word, language: language) {
                                wrong[bucket].fixed += 1
                            } else {
                                wrong[bucket].wrongFix += 1
                            }
                        } else if word.count >= 4, missedSamples.count < 12 {
                            missedSamples.append(word)
                        }
                    }
                    let fixed = wrong.reduce(0) { $0 + $1.fixed }
                    let total = wrong.reduce(0) { $0 + $1.total }
                    let recallCells = wrong.map { "\(pct($0.fixed, $0.total)) (\($0.fixed)/\($0.total))" }
                    print("| \(evalCode(language)) typed on \(evalCode(layout)) — restored | " + recallCells.joined(separator: " | ")
                          + " | \(pct(fixed, total)) |")
                    let wrongFixCells = wrong.map { "\($0.wrongFix)" }
                    let unreachable = wrong.reduce(0) { $0 + $1.unreachable }
                    print("|   ↳ wrong conversion / unreachable=\(unreachable) | " + wrongFixCells.joined(separator: " | ")
                          + " | \(wrong.reduce(0) { $0 + $1.wrongFix }) |")
                    if !missedSamples.isEmpty {
                        print("|   ↳ missed e.g. " + missedSamples.joined(separator: ", ") + " | | | | | |")
                    }
                    assert(total > 1000, "eval should have enough reachable \(evalCode(language))→\(evalCode(layout)) words")
                }
                assert(correctTotal.total > 3000, "eval should have enough \(evalCode(language)) words")
            }

            let sorted = timings.sorted()
            if !sorted.isEmpty {
                let p50 = sorted[sorted.count / 2]
                let p99 = sorted[Int(Double(sorted.count - 1) * 0.99)]
                print("")
                print("  detection time per word: p50=\(String(format: "%.1f", p50))µs p99=\(String(format: "%.1f", p99))µs (n=\(sorted.count))")
            }
        }
    }
}

// MARK: - Sentences

/// Simulates typing whole sentences. A correction that switches the layout makes
/// the rest of the sentence typed on the new layout, as in the real app.
private func runSentenceEval(sentences: [Layout: [[String]]]) {
    runSuite("LayoutEval: sentences (context), layouts en+ru+uk") {
        print("")
        print("| case | words | restored | left wrong | wrong conversion | false positives after switch | sentences switched | avg words before switch |")
        print("|---|---|---|---|---|---|---|---|")
        let allowed = Set(Layout.allCases)

        for language in evalLanguages {
            let list = sentences[language, default: []]

            var correctWords = 0
            var falsePositives = 0
            let detector = makeDetector(current: language, allowed: allowed)
            for sentence in list {
                detector.reset()
                for word in sentence {
                    correctWords += 1
                    if detect(detector, word: word, current: language) != nil {
                        falsePositives += 1
                    }
                }
            }
            print("| \(evalCode(language)) typed correctly | \(correctWords) | — | — | — | \(falsePositives) (\(pct(falsePositives, correctWords))) | — | — |")

            for startLayout in wrongLayouts(for: language) {
                var wrongWords = 0
                var restored = 0
                var wrongConversions = 0
                var leftWrong = 0
                var fpAfterSwitch = 0
                var switched = 0
                var wordsBeforeSwitch = 0
                for sentence in list {
                    detector.reset()
                    var layout = startLayout
                    var didSwitch = false
                    for (index, word) in sentence.enumerated() {
                        if layout == language {
                            if detect(detector, word: word, current: layout) != nil {
                                fpAfterSwitch += 1
                            }
                            continue
                        }
                        wrongWords += 1
                        let typed = typedForm(of: word, language: language, on: layout)
                        guard let result = detect(detector, word: typed, current: layout) else {
                            leftWrong += 1
                            continue
                        }
                        if restores(result, to: word, language: language) {
                            restored += 1
                        } else {
                            wrongConversions += 1
                        }
                        if result.shouldSwitchLayout {
                            if !didSwitch {
                                didSwitch = true
                                switched += 1
                                wordsBeforeSwitch += index
                            }
                            layout = result.targetLayout
                        }
                    }
                }
                let avg = switched > 0 ? String(format: "%.2f", Double(wordsBeforeSwitch) / Double(switched)) : "—"
                print("| \(evalCode(language)) started on \(evalCode(startLayout)) | \(wrongWords) | \(restored) (\(pct(restored, wrongWords))) | \(leftWrong) (\(pct(leftWrong, wrongWords))) | \(wrongConversions) | \(fpAfterSwitch) | \(switched)/\(list.count) (\(pct(switched, list.count))) | \(avg) |")
            }
        }
    }
}

// MARK: - Edge cases

private func runEdgeCaseEval() {
    runSuite("LayoutEval: edge cases (Tests/LayoutEval/edge_cases.tsv)") {
        let path = FileManager.default.currentDirectoryPath + "/Tests/LayoutEval/edge_cases.tsv"
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            print("  WARN: could not read \(path)")
            assert(false, "edge cases file should be readable")
            return
        }

        struct Group {
            var total = 0
            var passed = 0
            var failures: [String] = []
        }
        var groups: [String: Group] = [:]
        var order: [String] = []

        for line in content.split(whereSeparator: \.isNewline) where !line.hasPrefix("#") {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 5, let typedOn = evalLayout(code: fields[1]) else { continue }
            let expect = fields[0]
            let word = fields[3]
            let key = "\(expect) \(fields[1])←\(fields[2]) \(fields[4])"
            if groups[key] == nil { order.append(key) }

            let passedCase: Bool
            let detail: String
            if expect == "keep" {
                let detector = makeDetector(current: typedOn, allowed: Set(Layout.allCases))
                let result = detect(detector, word: word, current: typedOn)
                passedCase = result == nil
                detail = result.map { "\(word)→\($0.convertedWord)" } ?? word
            } else {
                guard let language = evalLayout(code: fields[2]) else { continue }
                let typed = typedForm(of: word, language: language, on: typedOn)
                let detector = makeDetector(current: typedOn, allowed: Set(Layout.allCases))
                let result = detect(detector, word: typed, current: typedOn)
                passedCase = result.map { restores($0, to: word, language: language) } ?? false
                detail = result.map { "\(typed)→\($0.convertedWord) (want \(word))" } ?? "\(typed) (want \(word))"
            }

            groups[key, default: Group()].total += 1
            if passedCase {
                groups[key, default: Group()].passed += 1
            } else {
                groups[key, default: Group()].failures.append(detail)
            }
        }

        print("")
        print("| group | passed | failures |")
        print("|---|---|---|")
        for key in order {
            let group = groups[key, default: Group()]
            print("| \(key) | \(group.passed)/\(group.total) | \(group.failures.joined(separator: ", ")) |")
        }
        assert(!order.isEmpty, "edge cases should not be empty")
    }
}

func runLayoutEvalSuites() {
    var sentences: [Layout: [[String]]] = [:]
    for language in evalLanguages {
        sentences[language] = loadSentences(language)
    }
    runIsolatedEval(sentences: sentences)
    runSentenceEval(sentences: sentences)
    runEdgeCaseEval()
}
