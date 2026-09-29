import Foundation
import Core

private func makeLexicon(
    _ storage: InMemoryLexiconStorage = InMemoryLexiconStorage(),
    saveDelay: TimeInterval = 0,
    clock: @escaping () -> Date = Date.init
) -> PersonalLexicon {
    PersonalLexicon(storage: storage, saveDelay: saveDelay, now: clock)
}

func runPersonalLexiconSuites() {
    runSuite("PersonalLexicon: normalization") {
        assertEqual(LexiconKey.normalize("Ghbdtn"), "ghbdtn")
        assertEqual(LexiconKey.normalize("П’ятниця"), "п'ятниця")
        assertEqual(LexiconKey(word: "Hf,jnftn", sourceLayout: .english), LexiconKey(word: "hf,jnftn", sourceLayout: .english))
    }

    runSuite("PersonalLexicon: validation") {
        assertEqual(PersonalLexicon.validate(word: "", sourceLayout: .english, rule: .neverCorrect), .empty)
        assertEqual(PersonalLexicon.validate(word: String(repeating: "a", count: 65), sourceLayout: .english, rule: .neverCorrect), .tooLong)
        assertEqual(PersonalLexicon.validate(word: "привет", sourceLayout: .english, rule: .neverCorrect), .notTypable)
        assertEqual(PersonalLexicon.validate(word: "ghbdtn", sourceLayout: .english, rule: .alwaysCorrect(to: .english)), .sameLayoutTarget)
        assertEqual(PersonalLexicon.validate(word: "было", sourceLayout: .russian, rule: .alwaysCorrect(to: .ukrainian)), .unsupportedPair, "no ru ↔ uk rules")
        assert(PersonalLexicon.validate(word: ",erdf", sourceLayout: .english, rule: .alwaysCorrect(to: .russian)) == nil, "punctuation keys are letters on the other layout")
        assert(PersonalLexicon.validate(word: "п'ятниця", sourceLayout: .ukrainian, rule: .neverCorrect) == nil, "apostrophe is allowed")
    }

    runSuite("PersonalLexicon: CRUD") {
        let lexicon = makeLexicon()
        guard case .added(let entry) = lexicon.add(word: "Kubectl", sourceLayout: .english, rule: .neverCorrect) else {
            return assert(false, "add should succeed")
        }
        assertEqual(entry.word, "kubectl")
        assertEqual(entry.origin, .manual)
        assertEqual(lexicon.rule(for: "KUBECTL", sourceLayout: .english), .neverCorrect)
        if case .duplicate(let existing) = lexicon.add(word: "kubectl", sourceLayout: .english, rule: .alwaysCorrect(to: .russian)) {
            assertEqual(existing.id, entry.id, "duplicate points at the existing entry")
        } else {
            assert(false, "same word + layout must be reported as duplicate")
        }
        var edited = entry
        edited.rule = .alwaysCorrect(to: .russian)
        assert(lexicon.update(edited) == nil, "update should succeed")
        assertEqual(lexicon.rule(for: "kubectl", sourceLayout: .english), .alwaysCorrect(to: .russian))
        lexicon.remove(ids: [entry.id])
        assert(lexicon.rule(for: "kubectl", sourceLayout: .english) == nil, "removed")
    }

    runSuite("PersonalLexicon: learning never overrides manual entries") {
        let lexicon = makeLexicon()
        _ = lexicon.add(word: "ghbdtn", sourceLayout: .english, rule: .alwaysCorrect(to: .russian))
        lexicon.recordRejected(word: "ghbdtn", sourceLayout: .english)
        assertEqual(lexicon.rule(for: "ghbdtn", sourceLayout: .english), .alwaysCorrect(to: .russian))
        lexicon.forgetAccepted(word: "ghbdtn", sourceLayout: .english)
        assertEqual(lexicon.rule(for: "ghbdtn", sourceLayout: .english), .alwaysCorrect(to: .russian))
    }

    runSuite("PersonalLexicon: the latest automatic lesson wins") {
        let lexicon = makeLexicon()
        lexicon.recordAccepted(word: "rehk", sourceLayout: .english, target: .russian)
        assertEqual(lexicon.rule(for: "rehk", sourceLayout: .english), .alwaysCorrect(to: .russian))
        assertEqual(lexicon.entries.first?.origin, .learnedFromHotkey)
        lexicon.recordRejected(word: "rehk", sourceLayout: .english)
        assertEqual(lexicon.rule(for: "rehk", sourceLayout: .english), .neverCorrect)
        assertEqual(lexicon.entries.count, 1, "one entry per word + layout")
        lexicon.forgetAccepted(word: "rehk", sourceLayout: .english)
        assertEqual(lexicon.rule(for: "rehk", sourceLayout: .english), .neverCorrect, "forget removes only hotkey lessons")
    }

    runSuite("PersonalLexicon: eviction keeps manual entries") {
        var tick = 0.0
        // Deferred save: 5000 synchronous JSON writes would dominate the run.
        let lexicon = makeLexicon(saveDelay: 3600, clock: { tick += 1; return Date(timeIntervalSince1970: tick) })
        _ = lexicon.add(word: "manual", sourceLayout: .english, rule: .neverCorrect)
        // Letters only: digits are not keys of the layout tables and would fail validation.
        func word(_ index: Int) -> String {
            let letters = Array("abcdefghijklmnopqrstuvwxyz")
            var value = index, result = "w"
            repeat { result.append(letters[value % 26]); value /= 26 } while value > 0
            return result
        }
        for index in 0..<(PersonalLexicon.maxLearnedEntries + 10) {
            lexicon.recordRejected(word: word(index), sourceLayout: .english)
        }
        assertEqual(lexicon.entries.filter { $0.origin != .manual }.count, PersonalLexicon.maxLearnedEntries)
        assert(lexicon.rule(for: "manual", sourceLayout: .english) != nil, "manual entry survives")
        assert(lexicon.rule(for: word(0), sourceLayout: .english) == nil, "oldest learned entry is evicted")
        assert(lexicon.rule(for: word(PersonalLexicon.maxLearnedEntries + 9), sourceLayout: .english) != nil, "newest stays")
    }

    runSuite("PersonalLexicon: persistence round-trip") {
        let storage = InMemoryLexiconStorage()
        let lexicon = makeLexicon(storage)
        lexicon.recordRejected(word: "ok", sourceLayout: .english)
        _ = lexicon.add(word: "сщвуч", sourceLayout: .ukrainian, rule: .alwaysCorrect(to: .english))
        lexicon.noteMatch(word: "сщвуч", sourceLayout: .ukrainian)
        lexicon.flush()
        let reloaded = makeLexicon(storage)
        assertEqual(reloaded.entries.count, 2)
        assertEqual(reloaded.rule(for: "сщвуч", sourceLayout: .ukrainian), .alwaysCorrect(to: .english))
        assertEqual(reloaded.entries.first { $0.word == "сщвуч" }?.matchCount, 1)
        lexicon.removeLearned()
        assertEqual(lexicon.entries.map(\.word), ["сщвуч"])
        lexicon.removeAll()
        assert(lexicon.entries.isEmpty, "all removed")
    }

    runSuite("PersonalLexicon: corrupt storage starts empty") {
        let storage = InMemoryLexiconStorage()
        storage.save(Data("not json".utf8))
        assert(makeLexicon(storage).entries.isEmpty, "corrupt data must not crash")
    }
}
