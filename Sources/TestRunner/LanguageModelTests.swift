import Foundation
import LanguageModel

// Tests for the character n-gram language model (plan/005, Phase 1).

func runLanguageModelSuites() {
    runSuite("LanguageModel: text normalization") {
        assertEqual(
            TextNormalization.words(in: "Создай новую worktree, пожалуйста!", language: .russian),
            ["создай", "новую", "пожалуйста"]
        )
        assertEqual(
            TextNormalization.words(in: "Создай новую worktree, пожалуйста!", language: .english),
            ["worktree"]
        )
        assertEqual(
            TextNormalization.words(in: "Don’t push to main-branch 2day", language: .english),
            ["don't", "push", "to", "main-branch"]
        )
        assertEqual(TextNormalization.words(in: "п’ять м'ячів", language: .ukrainian), ["п'ять", "м'ячів"])
        assertEqual(TextNormalization.words(in: "iPhone15 ok", language: .english), ["ok"])
        assert(TextNormalization.lineMatches("Это было вчера", language: .russian), "plain Russian line matches ru")
        assert(!TextNormalization.lineMatches("Він був учора вдома", language: .russian), "Ukrainian line rejected for ru")
        assert(TextNormalization.lineMatches("Він був учора вдома", language: .ukrainian), "Ukrainian line matches uk")
        assert(!TextNormalization.lineMatches("Этого я не говорил", language: .ukrainian), "Russian line rejected for uk")
        assert(!TextNormalization.lineMatches("Я не говорил", language: .ukrainian), "ambiguous line without uk letters rejected for uk")
    }

    runSuite("LanguageModel: binary format round-trip") {
        var counter = NgramCounter(language: .english, order: 3)
        for (word, weight) in [("hello", 5.0), ("help", 3.0), ("world", 2.0), ("worktree", 1.0)] {
            counter.add(word: word, weight: weight)
        }
        let model = counter.makeModel()
        let data = NgramBinaryFormat.encode(model)
        guard let decoded = try? NgramBinaryFormat.decode(data) else {
            assert(false, "encoded model should decode")
            return
        }
        for word in ["hello", "help", "world", "worktree", "xyzzy", "руддщ"] {
            assertEqual(decoded.logProbability(of: word), model.logProbability(of: word), "round-trip score for \(word)")
        }
        assert(model.logProbability(of: "hello") > model.logProbability(of: "xqzjv"), "seen word scores above noise")

        var corrupted = data
        corrupted[corrupted.count / 2] ^= 0xFF
        assert(decodeError(corrupted) == .checksumMismatch, "flipped table byte fails the checksum")
        assert(decodeError(data.prefix(data.count - 3)) != nil, "truncated file is rejected")
        var badMagic = data
        badMagic[0] = UInt8(ascii: "X")
        assert(decodeError(badMagic) == .badMagic, "wrong magic is rejected")
        assert(decodeError(data + Data([0])) != nil, "trailing bytes are rejected")
    }

    runSuite("LanguageModel: bundled models") {
        var models: [ModelLanguage: CharNgramModel] = [:]
        for language in ModelLanguage.allCases {
            let model = LanguageModelStore.shared.model(for: language)
            assert(model != nil, "bundled \(language.rawValue) model should load")
            models[language] = model
        }
        guard let en = models[.english], let ru = models[.russian], let uk = models[.ukrainian] else { return }
        assertEqual(en.order, 3)

        // Wrong-layout keystrokes must look much less plausible than the intended word.
        let pairs: [(String, CharNgramModel, String, CharNgramModel)] = [
            ("worktree", en, "цщклекуу", ru),
            ("rebase", en, "куифыу", ru),
            ("dependencies", en, "вузутвутсшуі", uk),
            ("работает", ru, "hf,jnftn", en),
            ("пятницу", ru, "gznybwe", en),
            ("зробила", uk, "phj,bkf", en),
        ]
        for (intended, intendedModel, typed, typedModel) in pairs {
            let margin = intendedModel.logProbability(of: intended) - typedModel.logProbability(of: typed)
            assert(margin > 8, "\(typed) → \(intended) margin \(String(format: "%.1f", margin)) should be large")
        }

        // Scoring speed: the detector scores a word under two models.
        let words = ["worktree", "цщклекуу", "работает", "hf,jnftn", "deadline", "пятницу", "kubernetes", "лгиуктуеуы"]
        var timings: [Double] = []
        for i in 0..<20_000 {
            let word = words[i % words.count]
            let start = ContinuousClock.now
            _ = en.logProbability(of: word) + ru.logProbability(of: word)
            timings.append(Double(start.duration(to: .now).components.attoseconds) / 1e12)
        }
        timings.sort()
        let p50 = timings[timings.count / 2]
        let p99 = timings[Int(Double(timings.count - 1) * 0.99)]
        print("  score two models per word: p50=\(String(format: "%.2f", p50))µs p99=\(String(format: "%.2f", p99))µs")
        assert(p99 < 50, "two-model scoring p99 should stay under 50µs")
    }
}

private func decodeError(_ data: Data) -> NgramBinaryFormat.DecodeError? {
    do {
        _ = try NgramBinaryFormat.decode(data)
        return nil
    } catch let error as NgramBinaryFormat.DecodeError {
        return error
    } catch {
        return nil
    }
}
