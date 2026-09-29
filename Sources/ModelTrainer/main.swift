import Foundation
import LanguageModel

// Trains the character n-gram models bundled with SwitchFix (plan/005, §5).
//
//   scripts/fetch-corpora.sh
//   swift run -c release ModelTrainer train [--corpus .build/corpora] [--out Sources/LanguageModel/Resources]
//                                          [--order 3] [--weighting token|log|type] [--balance]
//   swift run -c release ModelTrainer eval  [--models Sources/LanguageModel/Resources] [--eval Tests/LayoutEval]
//
// `eval` is a quick, platform-independent margin sweep over the eval set; the
// authoritative numbers come from `TestRunner` on macOS, which uses the real
// LayoutMapper and detector.

enum Weighting: String {
    /// Every occurrence counts (frequent words dominate).
    case token
    /// 1 + ln(frequency) per distinct word (dampens function words).
    case log
    /// Every distinct word counts once.
    case type
}

struct Options {
    var command = "train"
    var corpus = ".build/corpora"
    var out = "Sources/LanguageModel/Resources"
    var models = "Sources/LanguageModel/Resources"
    var eval = "Tests/LayoutEval"
    var order = 3
    var weighting = Weighting.token
    var balance = false
    var unknownLogProb: Float = -12

    init(_ arguments: [String]) {
        var args = arguments.dropFirst()
        if let first = args.first, !first.hasPrefix("--") {
            command = first
            args = args.dropFirst()
        }
        var iterator = args.makeIterator()
        while let flag = iterator.next() {
            func value() -> String {
                guard let v = iterator.next() else { fail("missing value for \(flag)") }
                return v
            }
            switch flag {
            case "--corpus": corpus = value()
            case "--out": out = value()
            case "--models": models = value()
            case "--eval": eval = value()
            case "--order": order = Int(value()) ?? 3
            case "--weighting":
                let raw = value()
                guard let parsed = Weighting(rawValue: raw) else { fail("unknown weighting \(raw)") }
                weighting = parsed
            case "--balance": balance = true
            case "--unknown": unknownLogProb = Float(value()) ?? -12
            default: fail("unknown flag \(flag)")
            }
        }
    }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

// MARK: - Train

func countWords(in file: URL, language: ModelLanguage) -> (counts: [String: Int], lines: Int, kept: Int) {
    guard let text = try? String(contentsOf: file, encoding: .utf8) else {
        fail("cannot read \(file.path)")
    }
    var counts: [String: Int] = [:]
    var lines = 0
    var kept = 0
    text.enumerateLines { line, _ in
        lines += 1
        guard TextNormalization.lineMatches(line, language: language) else { return }
        kept += 1
        for word in TextNormalization.words(in: line, language: language) {
            counts[word, default: 0] += 1
        }
    }
    return (counts, lines, kept)
}

func train(_ options: Options) {
    let fm = FileManager.default
    try? fm.createDirectory(atPath: options.out, withIntermediateDirectories: true)
    print("order=\(options.order) weighting=\(options.weighting.rawValue) balance=\(options.balance) unknown=\(options.unknownLogProb)")

    for language in ModelLanguage.allCases {
        let dir = URL(fileURLWithPath: options.corpus).appendingPathComponent(language.rawValue)
        let files = ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "txt" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !files.isEmpty else { fail("no corpus files in \(dir.path) — run scripts/fetch-corpora.sh") }

        var counter = NgramCounter(language: language, order: options.order)
        for file in files {
            let (counts, lines, kept) = countWords(in: file, language: language)
            let weights = counts.mapValues { count -> Double in
                switch options.weighting {
                case .token: return Double(count)
                case .log: return 1 + log(Double(count))
                case .type: return 1
                }
            }
            // --balance: every source file contributes the same total weight.
            let total = weights.values.reduce(0, +)
            let scale = options.balance && total > 0 ? 1_000_000 / total : 1
            for (word, weight) in weights {
                counter.add(word: word, weight: weight * scale)
            }
            let tokens = counts.values.reduce(0, +)
            print("  \(language.rawValue) \(file.lastPathComponent): lines \(lines), kept \(kept), tokens \(tokens), distinct \(counts.count)")
        }

        let model = counter.makeModel(unknownSymbolLogProb: options.unknownLogProb)
        let data = NgramBinaryFormat.encode(model)
        let url = URL(fileURLWithPath: options.out).appendingPathComponent("\(language.rawValue).sfng")
        do {
            try data.write(to: url)
        } catch {
            fail("cannot write \(url.path): \(error)")
        }
        print("  → \(url.path) (\(data.count) bytes)")
    }
}

// MARK: - Eval

/// QWERTY ↔ ЙЦУКЕН key positions (standard macOS layouts). Mirrors `LayoutMapper` for
/// lowercase letters only — enough for a model-level sweep.
let englishKeys = Array("qwertyuiop[]asdfghjkl;'zxcvbnm,.`".unicodeScalars)
let cyrillicKeys: [ModelLanguage: [Unicode.Scalar]] = [
    .russian: Array("йцукенгшщзхъфывапролджэячсмитьбюё".unicodeScalars),
    .ukrainian: Array("йцукенгшщзхїфівапролджєячсмитьбюґ".unicodeScalars),
]

func convert(_ word: String, from source: ModelLanguage, to target: ModelLanguage) -> String {
    let from = source == .english ? englishKeys : cyrillicKeys[source]!
    let to = target == .english ? englishKeys : cyrillicKeys[target]!
    var map: [Unicode.Scalar: Unicode.Scalar] = [:]
    for (a, b) in zip(from, to) { map[a] = b }
    var out = String.UnicodeScalarView()
    for scalar in word.unicodeScalars { out.append(map[scalar] ?? scalar) }
    return String(out)
}

func loadLines(_ path: String) -> [String] {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { fail("cannot read \(path)") }
    return text.split(whereSeparator: \.isNewline).map(String.init)
}

struct Sample {
    let word: String
    let language: ModelLanguage
}

func evaluate(_ options: Options) {
    var models: [ModelLanguage: CharNgramModel] = [:]
    for language in ModelLanguage.allCases {
        let url = URL(fileURLWithPath: options.models).appendingPathComponent("\(language.rawValue).sfng")
        do {
            models[language] = try LanguageModelStore.load(contentsOf: url)
        } catch {
            fail("cannot load \(url.path): \(error)")
        }
    }

    /// margin > 0 means "the other layout explains the keystrokes better".
    func margin(_ sample: Sample, typedOn layout: ModelLanguage, native: ModelLanguage) -> Double {
        let typed = sample.language == layout ? sample.word : convert(sample.word, from: sample.language, to: layout)
        let other: ModelLanguage = layout == .english ? native : .english
        let alternative = convert(typed, from: layout, to: other)
        return models[other]!.logProbability(of: alternative) - models[layout]!.logProbability(of: typed)
    }

    let buckets: [(String, ClosedRange<Int>)] = [("1", 1...1), ("2-3", 2...3), ("4-5", 4...5), ("6+", 6...99)]
    let thresholds: [Double] = [0, 2, 4, 6, 8, 10]

    func report(_ title: String, samples: [Sample], native: ModelLanguage,
                typedOn: (Sample) -> ModelLanguage, fires: Bool) {
        print("\n\(title) — \(fires ? "restored (higher is better)" : "false positives (lower is better)")")
        print("| T | " + buckets.map(\.0).joined(separator: " | ") + " |")
        print("|---|" + String(repeating: "---|", count: buckets.count))
        let margins = samples.map { (sample: $0, margin: margin($0, typedOn: typedOn($0), native: native)) }
        for threshold in thresholds {
            var cells: [String] = []
            for (_, range) in buckets {
                let inBucket = margins.filter { range.contains($0.sample.word.count) }
                let hits = inBucket.filter { $0.margin > threshold }.count
                cells.append(inBucket.isEmpty ? "—" : String(format: "%.2f%%", Double(hits) * 100 / Double(inBucket.count)))
            }
            print("| \(Int(threshold)) | " + cells.joined(separator: " | ") + " |")
        }
    }

    func words(_ file: String, _ language: ModelLanguage) -> [Sample] {
        loadLines("\(options.eval)/\(file)").flatMap { line in
            TextNormalization.words(in: line, language: language).map { Sample(word: $0, language: language) }
        }
    }

    for native in [ModelLanguage.russian, .ukrainian] {
        print("\n## en + \(native.rawValue)")
        let english = words("en.txt", .english)
        let nativeWords = words("\(native.rawValue).txt", native)
        let mixed = loadLines("\(options.eval)/mixed_\(native.rawValue).txt").flatMap { line in
            TextNormalization.words(in: line, language: .english).map { Sample(word: $0, language: .english) }
                + TextNormalization.words(in: line, language: native).map { Sample(word: $0, language: native) }
        }
        let mixedEnglish = mixed.filter { $0.language == .english }
        let mixedNative = mixed.filter { $0.language == native }

        report("mixed: English words typed on \(native.rawValue)", samples: mixedEnglish, native: native,
               typedOn: { _ in native }, fires: true)
        report("mixed: \(native.rawValue) words typed on en", samples: mixedNative, native: native,
               typedOn: { _ in .english }, fires: true)
        report("mixed: all words typed correctly", samples: mixed, native: native,
               typedOn: { $0.language }, fires: false)
        report("en words typed on \(native.rawValue)", samples: english, native: native,
               typedOn: { _ in native }, fires: true)
        report("en words typed correctly", samples: english, native: native,
               typedOn: { _ in .english }, fires: false)
        report("\(native.rawValue) words typed on en", samples: nativeWords, native: native,
               typedOn: { _ in .english }, fires: true)
        report("\(native.rawValue) words typed correctly", samples: nativeWords, native: native,
               typedOn: { _ in native }, fires: false)
    }
}

// MARK: - Score

/// `ModelTrainer score <en|ru|uk> <word>...` — prints each word's log-probability
/// under the bundled model (debugging aid).
func score(_ arguments: [String]) {
    guard arguments.count >= 2, let language = ModelLanguage(rawValue: arguments[0]) else {
        fail("usage: ModelTrainer score <en|ru|uk> <word>...")
    }
    let url = URL(fileURLWithPath: "Sources/LanguageModel/Resources/\(language.rawValue).sfng")
    guard let model = try? LanguageModelStore.load(contentsOf: url) else { fail("cannot load \(url.path)") }
    for word in arguments.dropFirst() {
        print("\(word)\t\(String(format: "%.2f", model.logProbability(of: word)))")
    }
}

if CommandLine.arguments.count > 1, CommandLine.arguments[1] == "score" {
    score(Array(CommandLine.arguments.dropFirst(2)))
    exit(0)
}

let options = Options(CommandLine.arguments)
switch options.command {
case "train": train(options)
case "eval": evaluate(options)
default: fail("unknown command \(options.command) (train | eval | score)")
}
