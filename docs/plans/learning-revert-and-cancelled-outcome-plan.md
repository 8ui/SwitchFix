# Learning gaps — implementation plan

> **For agentic workers:** execute task by task (executing-plans). Steps use checkboxes.

**Goal:** (a) reverting a hotkey correction made by a learned "always correct" rule forgets the rule;
(b) a detected correction that never reached the field (cancelled after detection) stops counting as
"corrected" in the detector's context and gives back the layout-switch confirmation it consumed.

**Architecture:** (a) is one case in `InputEngine.learnFromReverted`. (b) gives every detector-produced
`DetectionResult` a `detectionID` (non-zero), carried into `CorrectionPlan`; the engine calls
`LayoutDetector.noteCorrectionNotApplied(_:)` (on the detection queue) at every point where a detected
correction is dropped. The detector tags its recent-outcome entries with the id and keeps the switch state
from before the correction, restoring it only when no detection ran since.

**Tech stack:** Swift package; executables `TestRunner` (detector) and `InputPipelineTestRunner` (engine).

**Task:** `docs/tasks/2026-10-02-learning-revert-and-cancelled-outcome.md`.

## Global constraints

- `PersonalLexicon` `manual` entries are never changed by learning (`forgetAccepted` already only removes
  `learnedFromHotkey`; `learnedFromRevert` "never correct" is not touched by (a)).
- The detector is touched only on `InputEngine.detectionQueue`.
- No change to detection decisions for corrections that were applied: LayoutEval and the threshold sweep
  must stay byte-identical (they never cancel).
- Results built by the engine (forced hotkey alternatives) and by `exactDetection` in tests have id 0 and
  are ignored by the hook.
- Swift is not available in cloud sessions: verification is the CI run on `claude/**`.

---

### Task 1: Hotkey revert forgets a learned rule

**Files:** `Sources/Core/InputEngine.swift` (`isLearnable`, `learnFromReverted`), `CLAUDE.md` (item 7 "Known gap"),
test in `Sources/InputPipelineTestRunner/main.swift`.

- [ ] Test (a forced conversion is `hotkeyForced`, already handled; the gap is a rule applied by the
  hotkey): `lexicon.recordAccepted(word: "rehk", sourceLayout: .english, target: .russian)`
  (origin `learnedFromHotkey`), type `rehk` with no boundary, press the hotkey (the detector applies the rule
  → provenance `.hotkey`), press revert → `lexicon.rule(for: "rehk", sourceLayout: .english) == nil`.
  Same with a `manual` rule → the rule stays.
- [ ] `isLearnable`: `.hotkey` becomes learnable (single token rule as today); `learnFromApplied` keeps doing
  nothing for `.hotkey`; `learnFromReverted` `.hotkey` → `lexicon.forgetAccepted(word:sourceLayout:)`. The
  detector checks the lexicon before anything else, so a learned rule for the word is what produced it.
- [ ] CLAUDE.md item 7: replace the "Known gap" sentence.
- [ ] Commit `fix(engine): reverting a hotkey correction forgets the learned rule`.

### Task 2: Detection ids and the detector hook

**Files:** `Sources/Core/LayoutDetector.swift`, `Sources/Core/TextCorrector.swift` (`CorrectionPlan`),
test in `Sources/TestRunner/NgramDetectorTests.swift`.

- [ ] `DetectionResult.detectionID: UInt64` (public, init parameter `detectionID: UInt64 = 0`).
- [ ] `LayoutDetector`: `private var lastDetectionID: UInt64 = 0`, `private var detectionSerial: UInt64 = 0`
  (incremented at the start of every `checkBuffer`). `recentOutcomes` becomes `[(outcome: RecentOutcome,
  id: UInt64)]`; `recordOutcome(_:id: UInt64 = 0)`; `hasStrongCurrentContext` reads `.outcome`.
- [ ] Every path that returns a correction result (`finishCorrection`, `finishLexiconCorrection`,
  `finishAcronymFallback`) builds it with a fresh id, records `.corrected` with that id and stores
  `lastCorrection = (id, serial: detectionSerial, switchBefore: (pendingSwitchLayout, pendingSwitchCount))`
  where `switchBefore` is captured before `shouldSwitchLayout` mutated it.
  Paths that record `.corrected` but return nil (consecutive threshold not reached) keep id 0.
- [ ] `public func noteCorrectionNotApplied(_ id: UInt64)`: `guard id != 0`; the outcome entry with that id
  (if still in the window) becomes `.unknown`; if `lastCorrection?.id == id && lastCorrection.serial ==
  detectionSerial` (no detection since) restore `pendingSwitchLayout/Count` from `switchBefore`; clear
  `lastCorrection` when it matches.
- [ ] Tests (TestRunner, detector only):
  - current `.russian`, words `сейчас`, `на` (valid), then `рудщ` (→ `hello`, corrected, id ≠ 0), then
    `noteCorrectionNotApplied(id)`, then `ше` → no result (suppressed in strong context, as without the
    correction). Control without the hook: `ше` is corrected (existing behaviour).
  - current `.english`: `yf` → result with `shouldSwitchLayout == false`; `yf` → `true` (confirmation
    consumed); `noteCorrectionNotApplied(second.id)`; `yf` → `true` again (confirmation given back).
    Control: without the hook the third `yf` is `false`.
  - a stale id (another detection ran since) changes the outcome but not the switch state.
- [ ] Commit `feat(detector): ids for detected corrections and a not-applied hook`.

### Task 3: Engine calls the hook

**Files:** `Sources/Core/InputEngine.swift`, `Sources/Core/TextCorrector.swift` (`CorrectionPlan.detectionID`,
copied by `deleting`; `inversePlan` uses 0), test in `Sources/InputPipelineTestRunner/main.swift`.

- [ ] `CorrectionPlan.detectionID: UInt64` (init parameter default 0); `prepareCorrection` passes
  `result.detectionID`.
- [ ] `private func noteNotApplied(_ id: UInt64)` → `guard id != 0`, `detectionQueue.async { detector.noteCorrectionNotApplied(id) }`.
  Called from: every `cancelReason` exit in `prepareCorrection`; `ScreenCheck` for corrections — `reject`
  and every cancel return (stale before/after a read, replacement unconfirmed, unreadable after replacement);
  `emit` when `isEligible` fails or `apply` returns false. (A `ScreenCheck.cancelled: () -> Void` closure,
  called on every cancel return, `reject` keeps its meaning for the revert.)
- [ ] Engine test (real detector, `LearningHarness`): Russian context `сейчас на` then `рудщ` ended by Enter
  (cancelled `word-ended-by-enter`), then `ше ` → not corrected (strong context kept). Control in the same
  suite: `рудщ` ended by a space (applied) → `ше ` is corrected.
- [ ] Commit `fix(engine): cancelled corrections no longer count as corrected`.

### Task 4: Docs, debts, review

- [ ] Close the debt in `2026-09-30-automatic-correction-retypes-the-enter-that-ended-the-word`.
- [ ] Reviewer subagent, CI evidence.

---

## Rev. 2 — plan-review findings (override the tasks above where they differ)

- Test word `цщклы` (→ `world`), not `рудщ` (→ `helo`, not known to be corrected).
- `reset()` clears the stored correction (a hook after a context reset must not restore anything).
- No `CorrectionPlan` field: `prepareCorrection` captures `result.detectionID` in the `ScreenCheck` closures
  (`cancelled`, called on every cancel return) and passes it to `emit(_:detectionID:)`.
- id = `detectionSerial` (incremented per `checkBuffer`); "nothing detected since" = `id == detectionSerial`.
  Tagging happens once in `checkBuffer` after a non-nil result (the finish paths stay untouched).
- `pendingSuppressedShort` is never given back (the merged pair stays on screen; a later merge would
  delete the wrong length). `consecutiveWrongCount`, `lastDetectionResult`, `lastCyrillicLayout` untouched.
- `.hotkey` revert forgets only when `rule == .alwaysCorrect(to: plan.targetLayout)`.
- Engine tests wait and drain between the cancelled word and the short word; a screen-refusal variant.
