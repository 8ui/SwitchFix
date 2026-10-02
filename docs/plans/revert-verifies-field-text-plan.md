# Revert verifies the field text — implementation plan

> **For agentic workers:** execute task by task (executing-plans). Steps use checkboxes.

**Goal:** the revert hotkey deletes the corrected word only when the field still ends with it, using the
same field-text check (`ScreenVerification`) as a direct correction.

**Architecture:** `TextCorrector.undo` is split into `prepareUndo` (staleness check, builds a `RevertPlan`
= recorded plan + inverse plan, posts nothing) and `applyUndo` (re-checks, posts, switches the layout).
`InputEngine.verifyScreen` is generalized from `(CorrectionPlan, DetectionRequest)` to a `ScreenCheck`
value (expected word/boundary, pid/epoch, staleness closure, proceed closure, whether an autocorrected
word may be deleted). The correction path builds a `ScreenCheck` exactly as today; the revert path builds
one for `correctedText + boundaryText` with `acceptsReplacement: false`. The test seam `revertEmission`
becomes two seams, `revertPreparation` and `revertEmission`.

**Tech stack:** Swift package; plain executable test runner `InputPipelineTestRunner`.

**Task:** `docs/tasks/2026-10-02-revert-verifies-field-text.md`.

## Global constraints

- plan/003: physical input is never delayed; text is never mutated when context is stale. The revert must
  re-check staleness before and after every field read (as corrections do) and right before posting.
- Screen-check modes keep their meaning: `off` — no read (today's revert); `shadow` — read once, log the
  verdict, revert anyway; `enforce` (default) — cancel on mismatch/selection.
- Fail-open: an unreadable field (`unknown`) reverts as before.
- A revert rejected by the field check does NOT fall back to "nothing to revert → convert the word".
  The fallback still runs when there is nothing recorded or the recorded plan is stale.
- A `.replaced` verdict (looks like an autocorrection) cancels a revert: the field changed our text, and
  deleting a different word blindly is exactly the bug.
- On a field-check rejection (mismatch/selection/replaced) the recorded undo is cleared: the field no
  longer shows the corrected text, so a later revert cannot be right either.
- Swift is not available in cloud sessions: verification is the CI run on `claude/**`.
- Code and comments in English; logs through `SwitchFixLog`, typed text only via `SwitchFixLog.text`.

---

### Task 1: Split `TextCorrector.undo` into prepare/apply

**Files:**
- Modify: `Sources/Core/TextCorrector.swift` (around `undo`, lines ~242-306)

**Interfaces — Produces:**
```swift
public struct RevertPlan: Equatable {
    /// The correction being reverted (what learning reads).
    public let recorded: CorrectionPlan
    /// Deletes `recorded.correctedText + boundaryText`, types `originalText + boundaryText`.
    public let inverse: CorrectionPlan
}
extension TextCorrector {
    public static func inversePlan(of recorded: CorrectionPlan, sequence: UInt64, latest: CaptureStateSnapshot) -> CorrectionPlan
    public func prepareUndo(sequence: UInt64, context: InputContextSnapshot, latestCaptureState: () -> CaptureStateSnapshot) -> RevertPlan?
    @discardableResult public func applyUndo(_ revert: RevertPlan, latestCaptureState: () -> CaptureStateSnapshot) -> Bool
    public func discardUndo(_ revert: RevertPlan)   // clears the undo state only if it still holds revert.recorded
    // unchanged signature, now prepareUndo + applyUndo:
    public func undo(sequence:context:latestCaptureState:) -> CorrectionPlan?
}
```

- [ ] **Step 1:** Add `RevertPlan` next to `CorrectionPlan`; move the inverse-plan construction from `undo`
  into `static func inversePlan(of:sequence:latest:)` (same fields as today).
- [ ] **Step 2:** `prepareUndo`: the current guard part of `undo` (no state → nil; `isUndoEligible` false →
  clear, nil), returns `RevertPlan(recorded: undo.plan, inverse: inversePlan(...))`.
- [ ] **Step 3:** `applyUndo`: only when the undo state still equals `revert.recorded`; build events, check
  `inverse.isEligible(latest)`, post, clear the state, log `revert APPLIED`, switch the layout as today;
  returns whether it posted.
- [ ] **Step 4:** `discardUndo`; `undo` = `prepareUndo` then `applyUndo` (returns `recorded` on success).
- [ ] **Step 5:** commit `refactor(corrector): split undo into prepare and apply`.

### Task 2: Generalize `verifyScreen` to a `ScreenCheck`

**Files:**
- Modify: `Sources/Core/InputEngine.swift` (`prepareCorrection` tail ~544-554, `verifyScreen` ~568-655)

**Interfaces — Produces (private):**
```swift
private struct ScreenCheck {
    /// "correction" or "revert"; used in log lines only.
    let kind: String
    let word: String
    let boundary: String
    let pid: pid_t
    let epoch: UInt64
    let provenance: CorrectionProvenance
    /// Whether a `.replaced` verdict may delete the field's word; otherwise it cancels.
    let acceptsReplacement: Bool
    /// Runs on the input queue before and after every read.
    let isCurrent: () -> Bool
    /// Runs on the input queue; nil — delete what was planned, a count — the field's word instead.
    let proceed: (Int?) -> Void
    /// Runs on the input queue when the field rejects the text (mismatch, selection, unaccepted
    /// replacement) in enforce mode; never on staleness.
    let reject: () -> Void
}
private func verifyScreen(_ check: ScreenCheck, query: @escaping ScreenTextRequest, startedAt: UInt64,
                          attempt: Int, replacedBefore: Int? = nil, sawReplacement: Bool = false)
```

- [ ] **Step 1:** Replace the body's uses of `plan`/`request` with `check` fields; window =
  `(check.word + check.boundary).utf16.count + 6`; log lines say `\(check.kind) cancelled reason=…`.
- [ ] **Step 2:** right after `ScreenVerification.verdict(...)`: when `!check.acceptsReplacement` and the
  verdict is `.replaced`, treat it as `.mismatch` (no retry, no second read).
- [ ] **Step 3:** correction call site builds `ScreenCheck(kind: "correction", word: plan.originalText,
  boundary: plan.boundaryText, pid: request.context.frontmostPID, epoch: request.context.epoch,
  provenance: plan.provenance, acceptsReplacement: true, isCurrent: { [unowned self] in
  self.isCurrent(request) }, proceed: { [unowned self] count in self.emit(count.map(plan.deleting) ?? plan) }, reject: {})`.
  No behaviour change: the existing screen-check suites must stay green.
- [ ] **Step 4:** commit `refactor(engine): field-text check takes a ScreenCheck`.

### Task 3: Revert goes through the field check

**Files:**
- Modify: `Sources/Core/InputEngine.swift` (`RevertEmission` typealias ~49, init ~103-116, `.requestRevert` ~371-401)
- Test: `Sources/InputPipelineTestRunner/main.swift` (`LearningHarness` ~1171-1210, new `run(...)` suites)

**Interfaces:**
```swift
/// Prepares the revert of the last correction (tests replace `TextCorrector.prepareUndo`).
public typealias RevertPreparation = (UInt64, InputContextSnapshot) -> RevertPlan?
/// Posts a prepared revert; returns whether it was applied (tests replace `TextCorrector.applyUndo`).
public typealias RevertEmission = (RevertPlan) -> Bool
// InputEngine.init gains `revertPreparation: RevertPreparation? = nil`; `revertEmission` changes type.
```

- [ ] **Step 1 (tests first):** in `LearningHarness` add `let reverted = EmissionLog()`; pass
  `revertPreparation: { sequence, _ in revertReturnsNothing ? nil : emitted.last.map { RevertPlan(recorded: $0,
  inverse: TextCorrector.inversePlan(of: $0, sequence: sequence, latest: store.snapshot())) } }` and
  `revertEmission: { plan in reverted.append(plan.recorded); return true }`. New suites (stub replies: first
  for the correction, the rest for the revert):
  ```swift
  run("revert: field still shows the correction → reverted and learned") {
      var h = LearningHarness(screen: ScreenStub(.text(before: "ghbdtn ", atTextStart: true), .text(before: "привет ", atTextStart: true)))
      h.type("ghbdtn")
      check(waitUntil { h.emitted.count == 1 }, "corrected")
      h.send(.revertHotkey)
      check(waitUntil { h.reverted.count == 1 }, "reverted")
      check(waitUntil { h.lexicon.rule(for: "ghbdtn", sourceLayout: .english) == .neverCorrect }, "learned")
      check(h.screen?.windows.last == "привет ".utf16.count + 6, "reads the corrected text's length")
  }
  run("revert: field changed the corrected text → nothing deleted, nothing converted") {
      // "приветствие " — a different word; selection; and an autocorrect-like "приветы "
      for reply in [FieldTextProbe.text(before: "приветствие ", atTextStart: true), .selection(length: 3),
                    .text(before: "приветы ", atTextStart: true)] {
          var h = LearningHarness(screen: ScreenStub(.text(before: "ghbdtn ", atTextStart: true), reply))
          h.type("ghbdtn")
          check(waitUntil { h.emitted.count == 1 }, "corrected")
          h.send(.revertHotkey)
          check(!waitUntil(0.3) { h.reverted.count > 0 }, "no revert for \(reply)")
          check(h.emitted.count == 1, "no fallback conversion for \(reply)")
          check(h.lexicon.entries.isEmpty, "nothing learned for \(reply)")
      }
  }
  run("revert: lagging field is re-read; unreadable field reverts (fail-open)") {
      var lag = LearningHarness(screen: ScreenStub(.text(before: "ghbdtn ", atTextStart: true),
          .text(before: "прив", atTextStart: true), .text(before: "привет ", atTextStart: true)))
      lag.type("ghbdtn"); check(waitUntil { lag.emitted.count == 1 }, "corrected")
      lag.send(.revertHotkey); check(waitUntil { lag.reverted.count == 1 }, "reverted after the field caught up")
      var blind = LearningHarness(screen: ScreenStub(.text(before: "ghbdtn ", atTextStart: true), .unavailable(transient: false)))
      blind.type("ghbdtn"); check(waitUntil { blind.emitted.count == 1 }, "corrected")
      blind.send(.revertHotkey); check(waitUntil { blind.reverted.count == 1 }, "unreadable field reverts as before")
  }
  run("revert: shadow mode logs and reverts; typing during the read cancels") {
      var shadow = LearningHarness(screen: ScreenStub(.text(before: "ghbdtn ", atTextStart: true),
          .text(before: "приветствие ", atTextStart: true)), screenCheckMode: .shadow)
      shadow.type("ghbdtn"); check(waitUntil { shadow.emitted.count == 1 }, "corrected")
      shadow.send(.revertHotkey); check(waitUntil { shadow.reverted.count == 1 }, "shadow reverts anyway")
      // stale: a key typed while the field is being read
      let stub = ScreenStub(.text(before: "ghbdtn ", atTextStart: true), .text(before: "привет ", atTextStart: true))
      var stale = LearningHarness(screen: stub)
      stale.type("ghbdtn"); check(waitUntil { stale.emitted.count == 1 }, "corrected")
      stub.beforeFirstReply = nil
      // typed right after the revert key: the revert's read sees a newer sequence
      stale.send(.revertHotkey); stale.send(.character("x"))
      check(!waitUntil(0.3) { stale.reverted.count > 0 }, "a key after the revert key cancels it")
  }
  ```
  (Exact `FieldTextProbe` case labels: read them from `Sources/Core` before writing; adjust names, not intent.
  The stale case may revert before `x` is processed on a fast machine — if so, make the stub delay its
  revert reply via a hook instead of relying on timing.)
- [ ] **Step 2:** `.requestRevert` in `InputEngine`: on the correction queue call
  `revertPreparation ?? corrector.prepareUndo`; nil → today's fallback (`requestManualCorrection(...,
  teaches: false)` on the input queue). Otherwise, without `screenTextRequest` → `apply(revert)`; with it →
  on the input queue `verifyScreen(ScreenCheck(kind: "revert", word: inverse.originalText, boundary:
  inverse.boundaryText, pid: inverse.targetPID, epoch: inverse.contextEpoch, provenance:
  revert.recorded.provenance, acceptsReplacement: false, isCurrent: { inverse.isEligible(using:
  captureState.snapshot()) }, proceed: { _ in correctionQueue.async { apply(revert) } }, reject: {
  correctionQueue.async { corrector.discardUndo(revert) } }))` — staleness does not discard. `apply(revert)` = `(revertEmission ?? corrector.applyUndo)(revert)`, then
  `learnFromReverted(revert.recorded)` when applied.
- [ ] **Step 3:** existing revert suites (`learning: …revert…`, `revert hotkey with nothing to undo…`)
  stay green; run the whole `InputPipelineTestRunner` via CI.
- [ ] **Step 4:** commit `fix(engine): revert checks the field text before deleting`.

### Task 4: Docs

- [ ] CLAUDE.md, input pipeline item 5: one sentence that the revert hotkey goes through the same check
  (a rejection does not convert instead). Commit with Task 3 or as `docs(claude): …`.

---

## Rev. 2 — plan-review findings (override the tasks above where they differ)

- **Mismatch retries until the deadline for a revert (B2).** A revert pressed right after a correction can read
  the field while the app still processes the correction's events (`ghbdtn `, `ghbd`): that is `.mismatch`,
  not lag. `ScreenCheck.retriesMismatch` (true for revert): while `!final`, `.mismatch` and an unaccepted
  `.replaced` become `.retry`; only a final verdict rejects. Test: replies `ghbdtn `, `ghbd`, `привет ` → reverted.
- **Real `TextCorrector` in the harness, one seam (B1, B3).** No `RevertPreparation`: `TextCorrector.recordUndo(_:)`
  (public) lets the harness's `correctionEmission` record the plan; the engine always uses the corrector's
  `prepareUndo` / `takeUndo`; only posting is seamed: `revertEmission: (RevertPlan) -> Bool` replaces
  `TextCorrector.postUndo`. Tests then cover `isUndoEligible`, the stale → fallback path and `discardUndo`.
  `RevertPlan` is built only inside Core (internal init).
- **Undo identity (S2, S5).** `UndoState` gets a monotonically increasing `id`; `RevertPlan.undoID` carries it.
  `takeUndo(revert)` = atomic compare-and-take (`id` matches → clear, true); `discardUndo(revert)` clears only on a
  matching `id`. `rebaseUndoContext` keeps the id (the epoch change already makes the inverse stale).
- **Apply order (S2).** Engine on the correction queue: `revert.inverse.isEligible(snapshot)` → `corrector.takeUndo`
  → `revertEmission ?? corrector.postUndo` → `learnFromReverted(recorded)` if posted. `postUndo` builds events,
  posts, logs and switches the layout as today. Not building events after the take loses the undo (logged) —
  accepted; today it fell back to converting, which the constraints forbid for a refused revert (S6).
- **`[weak self]`** in every `ScreenCheck` closure; `isCurrent` returns false without self (S1).
- **`ScreenCheck.kind`** is an enum (`correction` / `revert`), log reasons say `revert cancelled reason=…`.
  `inverse.provenance` stays `.automatic` with a comment: learning reads `recorded.provenance`.
- **Tests added:** `ScreenStub.beforeReply: ((Int) -> Void)?` (1-based query index); stale during the revert's read
  (capture a key in the hook at query 2 → `queries == 2`, no revert); stale capture of a non-edit key does not
  discard (a second revert press with a matching field reverts); rejection clears undo (second press → no revert,
  fallback finds an empty buffer, `emitted.count == 1`); revert of a hotkey correction (empty boundary, window
  `correctedText.utf16.count + 6`). Negative waits 0.5 s (rejection now waits for the deadline).
- **Docs:** CLAUDE.md item 5, `ScreenTextRequest` and `ScreenCheckMode` doc comments mention the revert.
