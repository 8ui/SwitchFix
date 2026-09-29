import Foundation
import Core

// Layout-detection eval on real text (plan/005, Phase 0).
//
// Report-only: prints recall / false-positive tables for the detector; the numbers of
// the removed dictionary engine are frozen in plan/benchmarks/baseline_005.md. Data
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
    /// Primary: English plus the user's native Cyrillic layout (the common setup).
    case pair
    /// Secondary: all three layouts installed (both Cyrillic layouts compete).
    case all

    var name: String {
        switch self {
        case .pair: return "en + native (primary)"
        case .all: return "en+ru+uk (secondary)"
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

private func makeDetector(
    current: Layout,
    allowed: Set<Layout>,
    thresholds: DetectionThresholds = .default
) -> LayoutDetector {
    let detector = LayoutDetector()
    detector.thresholds = thresholds
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
    runSuite("LayoutEval: sentences (context), layouts en + native") {
        print("")
        print("| case | words | restored | left wrong | wrong conversion | false positives after switch | sentences switched | avg words before switch |")
        print("|---|---|---|---|---|---|---|---|")

        for language in evalLanguages {
            let list = sentences[language, default: []]

            var correctWords = 0
            var falsePositives = 0
            let detector = makeDetector(
                current: language,
                allowed: EvalConfig.pair.allowedLayouts(language: language, typedOn: wrongLayouts(for: language)[0])
            )
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
                detector.allowedLayouts = EvalConfig.pair.allowedLayouts(language: language, typedOn: startLayout)
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

// MARK: - Mixed messages (native text with English words)

private struct MixedToken {
    let word: String
    let language: Layout
}

private func tokenizeMixed(_ sentence: String, native: Layout) -> [MixedToken] {
    var tokens: [MixedToken] = []
    for chunk in sentence.split(whereSeparator: { $0.isWhitespace }) {
        let text = String(chunk)
        if let word = tokenize(text, language: .english).first {
            tokens.append(MixedToken(word: word, language: .english))
        } else if let word = tokenize(text, language: native).first {
            tokens.append(MixedToken(word: word, language: native))
        }
    }
    return tokens
}

private func loadMixed(_ native: Layout) -> [[MixedToken]] {
    let path = FileManager.default.currentDirectoryPath + "/Tests/LayoutEval/mixed_\(evalCode(native)).txt"
    guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
        print("  WARN: could not read mixed messages at \(path)")
        return []
    }
    return content
        .split(whereSeparator: \.isNewline)
        .map { tokenizeMixed(String($0), native: native) }
        .filter { !$0.isEmpty }
}

private enum TypistModel: CaseIterable {
    /// Never switches the layout by hand; only SwitchFix switches it.
    case reliesOnApp
    /// Types the first word after a language change on the old layout, then
    /// switches by hand (unless SwitchFix already did).
    case switchesLate

    var name: String {
        switch self {
        case .reliesOnApp: return "relies on app"
        case .switchesLate: return "switches late"
        }
    }
}

private struct MixedMetrics {
    var messages = 0
    var fullyCorrect = 0
    var englishMistyped = 0
    var englishRestored = 0
    var nativeMistyped = 0
    var nativeRestored = 0
    var leftWrong = 0
    var wrongConversions = 0
    var falsePositives = 0
    var failures: [String] = []
}

/// Types every message as `model` would and tallies what the detector did.
private func mixedMetrics(
    _ messages: [[MixedToken]],
    native: Layout,
    model: TypistModel,
    thresholds: DetectionThresholds = .default
) -> MixedMetrics {
    let detector = makeDetector(current: native, allowed: [.english, native], thresholds: thresholds)
    var metrics = MixedMetrics()
    metrics.messages = messages.count

    for message in messages {
        detector.reset()
        var layout = native
        var previousLanguage: Layout?
        var messageOK = true
        var rendered: [String] = []

        for token in message {
            if model == .switchesLate, previousLanguage == token.language, layout != token.language {
                layout = token.language
            }
            previousLanguage = token.language

            if layout == token.language {
                if let result = detect(detector, word: token.word, current: layout) {
                    metrics.falsePositives += 1
                    messageOK = false
                    rendered.append("[\(token.word)→\(result.convertedWord)]")
                    if result.shouldSwitchLayout { layout = result.targetLayout }
                } else {
                    rendered.append(token.word)
                }
                continue
            }

            let isEnglish = token.language == .english
            if isEnglish { metrics.englishMistyped += 1 } else { metrics.nativeMistyped += 1 }
            let typed = typedForm(of: token.word, language: token.language, on: layout)
            guard let result = detect(detector, word: typed, current: layout) else {
                metrics.leftWrong += 1
                messageOK = false
                rendered.append("[\(typed)]")
                continue
            }
            if restores(result, to: token.word, language: token.language) {
                if isEnglish { metrics.englishRestored += 1 } else { metrics.nativeRestored += 1 }
                rendered.append(token.word)
            } else {
                metrics.wrongConversions += 1
                messageOK = false
                rendered.append("[\(typed)→\(result.convertedWord)]")
            }
            if result.shouldSwitchLayout { layout = result.targetLayout }
        }

        if messageOK {
            metrics.fullyCorrect += 1
        } else if metrics.failures.count < 8 {
            metrics.failures.append(rendered.joined(separator: " "))
        }
    }
    return metrics
}

/// The main user scenario: native-language messages with English words
/// ("создай новую worktree"), typed starting on the native layout.
private func runMixedEval() {
    runSuite("LayoutEval: mixed native + English messages, layouts en + native") {
        print("")
        print("| messages | typist | fully correct | English words mistyped → restored | native words mistyped → restored | left wrong | wrong conversion | false positives |")
        print("|---|---|---|---|---|---|---|---|")

        for native in [Layout.russian, .ukrainian] {
            let messages = loadMixed(native)
            let englishCount = messages.reduce(0) { count, message in
                count + message.filter { $0.language == .english }.count
            }
            assert(messages.count > 50, "mixed \(evalCode(native)) messages should load")
            assert(englishCount > 50, "mixed \(evalCode(native)) messages should contain English words")

            for model in TypistModel.allCases {
                let m = mixedMetrics(messages, native: native, model: model)
                print("| \(evalCode(native)) (\(m.messages)) | \(model.name) | \(m.fullyCorrect) (\(pct(m.fullyCorrect, m.messages))) | \(m.englishRestored)/\(m.englishMistyped) (\(pct(m.englishRestored, m.englishMistyped))) | \(m.nativeRestored)/\(m.nativeMistyped) (\(pct(m.nativeRestored, m.nativeMistyped))) | \(m.leftWrong) | \(m.wrongConversions) | \(m.falsePositives) |")
                for failure in m.failures {
                    print("|   ↳ \(failure) | | | | | | | |")
                }
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
    // Dictionary-engine reference numbers are frozen in plan/benchmarks/baseline_005.md.
    runMixedEval()
    runIsolatedEval(sentences: sentences)
    runSentenceEval(sentences: sentences)
    runEdgeCaseEval()
}

// MARK: - Threshold sweep (plan/005 §4.6, §12.10)
//
//   swift run -c release TestRunner --threshold-sweep
//
// Report-only. Machine-readable rows start with "SWEEP\t" (grep them from the CI log):
// per length bucket for a base threshold T (every bucket set to T at once — words of
// different lengths are independent), then per sensitivity offset and slider position.
// Results are recorded in plan/benchmarks/thresholds_005.md.

private let sweepBucketNames = ["1-2", "3", "4", "5", "6", "7+"]

private func sweepBucket(_ word: String) -> Int {
    switch word.filter(\.isLetter).count {
    case ..<3: return 0
    case 3: return 1
    case 4: return 2
    case 5: return 3
    case 6: return 4
    default: return 5
    }
}

private struct IsolatedMetrics {
    var correct = Array(repeating: 0, count: 6)
    var falsePositives = Array(repeating: 0, count: 6)
    var wrong = Array(repeating: 0, count: 6)
    var fixed = Array(repeating: 0, count: 6)

    func fpRate(_ buckets: ClosedRange<Int>) -> Double {
        rate(buckets.reduce(0) { $0 + falsePositives[$1] }, buckets.reduce(0) { $0 + correct[$1] })
    }

    func recall(_ buckets: ClosedRange<Int>) -> Double {
        rate(buckets.reduce(0) { $0 + fixed[$1] }, buckets.reduce(0) { $0 + wrong[$1] })
    }
}

private func rate(_ part: Int, _ total: Int) -> Double {
    total > 0 ? Double(part) * 100 / Double(total) : 0
}

private func format(_ value: Double) -> String {
    String(format: "%.2f", value)
}

/// Isolated words, primary configuration (English + the native layout).
private func isolatedMetrics(_ sentences: [Layout: [[String]]], thresholds: DetectionThresholds) -> IsolatedMetrics {
    var metrics = IsolatedMetrics()
    for language in evalLanguages {
        let words = sentences[language, default: []].flatMap { $0 }
        let correctDetector = makeDetector(
            current: language,
            allowed: EvalConfig.pair.allowedLayouts(language: language, typedOn: wrongLayouts(for: language)[0]),
            thresholds: thresholds
        )
        for word in words {
            correctDetector.reset()
            let bucket = sweepBucket(word)
            metrics.correct[bucket] += 1
            if detect(correctDetector, word: word, current: language) != nil {
                metrics.falsePositives[bucket] += 1
            }
        }
        for layout in wrongLayouts(for: language) {
            let detector = makeDetector(
                current: layout,
                allowed: EvalConfig.pair.allowedLayouts(language: language, typedOn: layout),
                thresholds: thresholds
            )
            for word in words where isReachable(word, language: language, on: layout) {
                detector.reset()
                let bucket = sweepBucket(word)
                metrics.wrong[bucket] += 1
                let typed = typedForm(of: word, language: language, on: layout)
                if let result = detect(detector, word: typed, current: layout),
                   restores(result, to: word, language: language) {
                    metrics.fixed[bucket] += 1
                }
            }
        }
    }
    return metrics
}

func runThresholdSweep() {
    var sentences: [Layout: [[String]]] = [:]
    for language in evalLanguages {
        sentences[language] = loadSentences(language)
    }
    let mixed = [Layout.russian, .ukrainian].map { ($0, loadMixed($0)) }

    print("SWEEP\tbucket\tT\tfp%\tfp\tcorrect\trecall%\tfixed\twrong")
    var recommended: [Int: Double] = [:]
    for step in 2...28 {
        let base = Double(step) / 2
        var thresholds = DetectionThresholds.default
        thresholds.threeLetters = base
        thresholds.fourLetters = base
        thresholds.fiveLetters = base
        thresholds.sixLetters = base
        thresholds.sevenPlusLetters = base
        let metrics = isolatedMetrics(sentences, thresholds: thresholds)
        for bucket in 1...5 {
            let fp = metrics.fpRate(bucket...bucket)
            print("SWEEP\t\(sweepBucketNames[bucket])\t\(format(base))\t\(format(fp))\t\(metrics.falsePositives[bucket])\t\(metrics.correct[bucket])\t\(format(metrics.recall(bucket...bucket)))\t\(metrics.fixed[bucket])\t\(metrics.wrong[bucket])")
            // Rule §4.6.2: the smallest threshold whose false positives meet the target.
            let target = bucket == 1 ? 0.5 : 0.1
            if recommended[bucket] == nil, fp <= target {
                recommended[bucket] = base
            }
        }
    }
    for bucket in 1...5 {
        print("SWEEP\trecommend\t\(sweepBucketNames[bucket])\t\(recommended[bucket].map(format) ?? "none")")
    }

    print("SWEEP\tconfig\toffset\tfp1-3%\tfp4+%\trecall1-3%\trecall4-5%\trecall6+%\tmixedFP\tmixedWrong\tfullyCorrectLate%\tfullyCorrectRelies%")
    func sweepRow(_ label: String, _ thresholds: DetectionThresholds) {
        let isolated = isolatedMetrics(sentences, thresholds: thresholds)
        var falsePositives = 0
        var wrongConversions = 0
        var late = (full: 0, total: 0)
        var relies = (full: 0, total: 0)
        for (native, messages) in mixed {
            for model in TypistModel.allCases {
                let metrics = mixedMetrics(messages, native: native, model: model, thresholds: thresholds)
                falsePositives += metrics.falsePositives
                wrongConversions += metrics.wrongConversions
                if model == .switchesLate {
                    late.full += metrics.fullyCorrect
                    late.total += metrics.messages
                } else {
                    relies.full += metrics.fullyCorrect
                    relies.total += metrics.messages
                }
            }
        }
        print("SWEEP\t\(label)\t\(format(thresholds.sensitivityOffset))\t\(format(isolated.fpRate(0...1)))\t\(format(isolated.fpRate(2...5)))\t\(format(isolated.recall(0...1)))\t\(format(isolated.recall(2...3)))\t\(format(isolated.recall(4...5)))\t\(falsePositives)\t\(wrongConversions)\t\(format(rate(late.full, late.total)))\t\(format(rate(relies.full, relies.total)))")
    }
    for step in -12...12 {
        var thresholds = DetectionThresholds.default
        thresholds.sensitivityOffset = Double(step) / 2
        sweepRow("offset", thresholds)
    }
    for position in DetectionThresholds.sensitivityPositions {
        sweepRow("position\(position)", .forSensitivity(position))
    }
}
