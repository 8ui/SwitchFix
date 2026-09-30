# Upstream develop edge cases — implementation plan (rev. 2)

> **For agentic workers:** execute task by task (superpowers:executing-plans). Steps use checkboxes.

**Goal:** fix three cases found by probing `upstream/develop` scenarios against the n-gram detector:
(A) CLI flags are rewritten (`ls -r` → `ls -к`, `rm -r -f` → `rm -к -а`), (B) a 3-letter word is
rewritten inside a strong native context (`в нову еру` → `в нову the`), (C) a fragment typed after an
arrow key inside a word is auto-corrected as a separate word.

**Architecture:** no new deferral/merge — rev. 1 widened `pendingSuppressedShort` merging, which deletes
`suppressed + bridge + current` without checking the screen (double space, `!`, Cmd+Z, Enter bridge) and
did not cover consecutive flags. Instead A and B are stateless "keep" rules on the automatic path only
(`pendingBoundaryCharacter != nil`, like `shouldSkipAutomaticEnglishAcronymCorrection`); the hotkey still
converts. C adds a flag to `InputStateMachine` set on `.navigation` and cleared only at a boundary, so
focus resolution (a context change after every arrow) cannot clear it; the buffer is kept for the hotkey.

**Tech stack:** Swift 5 package, plain executable test runners (`TestRunner`, `InputPipelineTestRunner`).

**Task:** `docs/tasks/2026-09-30-check-upstream-develop-edge-cases-against-the-n-gram.md`.

## Global constraints

- Governing rule (plan/003): physical input is never delayed; text is never mutated when context is stale.
- Upstream decision `1ad2692` stays: an isolated short word is still corrected at once (`ше` → `it`,
  `r` → `к`); `yf` → `на` and `Ot` → `Ще` suites stay unchanged.
- No retraining, no threshold changes (`DetectionThresholds.calibratedModelChecksums` stays valid).
- Hotkey behaviour unchanged: the new rules apply only to automatic (boundary-triggered) detection.
- `TestRunner` runs from the repo root. Code and comments in English.
- Baseline (recorded in the task): TestRunner 527/0, InputPipelineTestRunner 979/0, sentence eval
  ru-on-en 93.01%, uk-on-en 94.27%, en-on-ru 97.93%, en-on-uk 97.76%; edge cases code/cli 35/36.
  A and B only keep words, so restored % may drop only by kept words; any drop is explained in the Log.

---

### Task 1 (A): CLI flags are never auto-corrected

**Files:** `Sources/Core/LayoutDetector.swift` (`checkLanguageModels`, new helper next to
`shouldSkipAutomaticEnglishAcronymCorrection`); test `Sources/TestRunner/NgramDetectorTests.swift`.

- [ ] **Step 1: failing test** — append to `runNgramDetectorSuites()`:

```swift
    runSuite("NgramDetector: command-line flags stay") {
        for words in [["ls", "-r"], ["rm", "-r", "-f"], ["tar", "-c", "-z", "-f"], ["cp", "-r", "-d"], ["grep", "-r"], ["-r"], ["--x"]] {
            let detector = ngramDetector(current: .english, allowed: [.english, .russian])
            let recorder = MockDetectorDelegate()
            detector.delegate = recorder
            for word in words {
                detector.addCharacter(word)
                detector.flushBuffer(boundaryCharacter: " ")
            }
            assert(recorder.results.isEmpty, "\(words.joined(separator: " ")) must stay, got \(recorder.results.map(\.convertedWord))")
        }
        // Bare letters are still corrected (preposition at the start of a sentence).
        assertEqual(detectNgram("r", current: .english, allowed: [.english, .russian])?.convertedWord, "к")
        // The hotkey (no boundary) still converts a flag.
        let hotkey = ngramDetector(current: .english, allowed: [.english, .russian])
        hotkey.addCharacter("-r")
        assertEqual(hotkey.flushBuffer(boundaryCharacter: nil)?.convertedWord, "-к", "hotkey converts a flag")
    }
```

- [ ] **Step 2:** `swift run -c release TestRunner 2>&1 | grep -A6 "command-line flags"` → FAIL.
- [ ] **Step 3: implement** — in `checkLanguageModels`, right after the
  `shouldSkipAutomaticEnglishAcronymCorrection` block:

```swift
        if shouldSkipAutomaticCommandLineFlag(word: word, sourceLayout: sourceLayout) {
            // Neutral: a flag is neither native-language context nor a correction.
            consecutiveWrongCount = 0
            lastDetectionResult = nil
            pendingSwitchLayout = nil
            pendingSwitchCount = 0
            state = .buffering
            return nil
        }
```

  and the helper:

```swift
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
```

- [ ] **Step 4:** full `swift run -c release TestRunner` and `InputPipelineTestRunner` → green;
  `--layout-eval-only` compared with baseline (expected: no change except `keep en←en code/cli`).
- [ ] **Step 5:** commit `fix(detector): never auto-correct command-line flags`.

### Task 2 (B): 3-letter words stay inside a strong native context

**Files:** `Sources/Core/LayoutDetector.swift` (`finishCorrection`, new parameter near
`shortWordSuppressionLength`); `Sources/TestRunner/NgramDetectorTests.swift`.

- [ ] **Step 1: failing test**:

```swift
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
        assert(results(["на", "еру"]).count == 1, "one short context word is not strong context")
        assertEqual(results(["еру"]).first?.convertedWord, "the", "isolated 'еру' is still corrected")
        assertEqual(results(["в", "нову", "еру"], boundary: nil).first?.convertedWord, "the", "the hotkey still converts")
    }
```

  (Step 2 confirms the second assert against the real context rule: if `на еру` is already strong
  context under `hasStrongCurrentContext`, replace it with the pair that the rule actually treats as weak
  and note it in the Log — do not change the rule. If `в нову еру` itself is not kept because
  `в нову` is weak context, stop and report to the user instead of swapping the phrase.)
- [ ] **Step 2:** run → FAIL on the first assert.
- [ ] **Step 3: implement** — new parameter:

```swift
    /// Low-confidence words longer than `shortWordSuppressionLength` and up to this length
    /// are kept (not corrected, not deferred) inside a strong current-language context:
    /// `в нову еру` stays Ukrainian. Automatic detection only.
    public var contextKeepLength: Int = 3
```

  in `finishCorrection`, before `shouldSuppressLowConfidenceCorrection(...)`:

```swift
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
```

- [ ] **Step 4:** full `TestRunner` + `InputPipelineTestRunner` green; eval compared with baseline, the
  difference (words kept that were restored before) written to the task Log.
- [ ] **Step 5:** commit `fix(detector): keep 3-letter words inside a strong native context`.

### Task 3 (C): no automatic correction for a word entered by arrow keys

**Files:** `Sources/Core/InputStateMachine.swift` (`.navigation`, `.boundary`);
`Sources/InputPipelineTestRunner/main.swift` (state-machine test after "ordered word", engine test next to
the `LearningHarness` hotkey tests).

- [ ] **Step 1: failing tests**:

```swift
run("navigation skips automatic correction of the word it lands in") {
    let current = context()
    var machine = automaticMachine(current)
    var sequence: UInt64 = 0
    func send(_ kind: CapturedInput.Kind) -> [InputStateCommand] {
        sequence += 1
        return machine.consume(input(sequence: sequence, kind: kind, context: current))
    }
    func flushed(_ commands: [InputStateCommand]) -> [String] {
        commands.compactMap { if case .flush(let word, _, _, _) = $0 { return word } else { return nil } }
    }
    for character in ["w", "o", "r"] { _ = send(.character(character)) }
    _ = send(.navigation)
    _ = send(.character("d"))
    _ = send(.character("s"))
    check(machine.currentBuffer == "ds", "keys after an arrow stay buffered for the hotkey")
    check(flushed(send(.boundary(" "))).isEmpty, "a fragment typed after an arrow is not auto-corrected")
    for character in ["g", "h", "b", "d", "t", "n"] { _ = send(.character(character)) }
    check(flushed(send(.boundary(" "))) == ["ghbdtn"], "the next word is corrected again")
}
```

```swift
run("arrow keys skip automatic correction, the hotkey still converts from the buffer") {
    var harness = LearningHarness()
    harness.caret.reply = .unavailable
    harness.send(.navigation)
    harness.resolveFocus()
    harness.type("ghbdtn")
    check(!waitUntil(0.3) { harness.emitted.count > 0 }, "the word after an arrow is not auto-corrected even after focus resolves")
    harness.type("ghbdtn")
    check(waitUntil { harness.emitted.count == 1 }, "the next word is corrected")
    harness.send(.navigation)
    harness.resolveFocus()
    harness.type("ghbdtn", boundary: nil)
    harness.send(.hotkey)
    check(waitUntil { harness.emitted.count == 2 }, "the hotkey converts the buffered word without Accessibility")
    check(harness.emitted.last?.originalText == "ghbdtn", "got \(harness.emitted.last?.originalText ?? "nil")")
}
```

- [ ] **Step 2:** `swift run -c release InputPipelineTestRunner 2>&1 | grep -B1 -A3 "arrow\|navigation skips"` → FAIL.
- [ ] **Step 3: implement**:

```swift
    /// Set by arrow keys and shortcuts: the caret may now be inside a word, so the
    /// characters typed until the next boundary are kept for the hotkey but never
    /// flushed for automatic correction. Cleared only at a boundary: focus resolution
    /// replaces the context after every arrow key and must not clear it.
    public private(set) var skipsAutomaticFlushUntilBoundary = false
```

  - `.navigation`: after `invalidate(untilBoundary: false)` add `skipsAutomaticFlushUntilBoundary = true`.
  - `.boundary`: add `skipsAutomaticFlushUntilBoundary = false` to the `defer`, and
    `guard !skipsAutomaticFlushUntilBoundary else { return [] }` after the
    `guard !isInvalidUntilBoundary, !currentBuffer.isEmpty` line.
- [ ] **Step 4:** full `InputPipelineTestRunner` + `TestRunner` green.
- [ ] **Step 5:** commit `fix(input): no automatic correction for a word entered by arrow keys`.

### Task 4: Review

- [ ] `rtp verify` with the `.rtp.json` checks, independent reviewer subagent on the diff.
- [ ] Debt: (1) the existing 2-letter `pendingSuppressedShort` merge deletes `suppressed + bridge +
  current` without checking the screen (double space, `!`, Cmd+Z, Enter bridge) — separate task;
  (2) C does not cover clicks mid-word; (3) `.navigation` also covers Cmd/Ctrl/Option chords (Cmd+V,
  Option symbols), so the word typed right after them is not auto-corrected.
