# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

SwitchFix is a macOS 13+ menu bar app (Swift Package, no Xcode project) that detects words typed in the wrong keyboard layout (English ↔ Ukrainian/Russian), deletes them, switches the input source and retypes the converted text. This repo is a fork of `rundax/SwitchFix` (`upstream` remote); fork-specific changes are described in the Russian section of README.md.

## Commands

```bash
swift build -c release                         # compile all targets
swift run -c release TestRunner                # detector/model/mapper tests + LayoutEval report
swift run -c release InputPipelineTestRunner   # capture → state machine → correction pipeline tests
swift run -c release InputPipelineTestRunner --integration-smoke   # also posts real CGEvents into an NSTextView
./scripts/build-app.sh                         # → dist/SwitchFix.app (copies the language model bundle, signs)
./scripts/create-dmg.sh                        # → dist/SwitchFix.dmg
./install.sh                                   # build + install to /Applications + login item + permissions
./scripts/setup-codesign.sh                    # one-time: stable self-signed identity in .codesign-identity
scripts/fetch-corpora.sh                       # download pinned training corpora → .build/corpora (checks scripts/corpora.sha256)
swift run -c release ModelTrainer train        # retrain Sources/LanguageModel/Resources/{en,ru,uk}.sfng (deterministic)
swift run -c release ModelTrainer eval         # model-level margin sweep on Tests/LayoutEval (runs on Linux too)
swift run -c release TestRunner --layout-eval-only   # real-text eval of the current detector (report-only)
swift run -c release TestRunner --threshold-sweep    # threshold/sensitivity calibration rows (SWEEP\t…), report-only
```

CI (`.github/workflows/ci.yml`) runs exactly: a duplicate-key check of `Sources/UI/L10n.swift`, release build, `TestRunner`, the threshold sweep (report-only), `InputPipelineTestRunner`, then `build-app.sh` ad-hoc signed. Releases are built on `v*` tags; the version lives in `Resources/Info.plist` (`CFBundleShortVersionString` / `CFBundleVersion`).

### Tests

There is no XCTest/swift-testing target (it needs a full Xcode install); `Tests/SwitchFixTests` is a stub. Tests are plain executables with hand-rolled `assert`/`assertEqual`/`check` helpers that exit 1 on failure. There is no per-test filter — to run one case, comment out other `runSuite` calls locally or add a new suite. `TestRunner` must be run from the repo root: LayoutEval reads `Tests/LayoutEval/*` by relative path.

`InputEngine` accepts injectable `exactDetection` / `correctionEmission` / `selectedTextRequest` / `revertEmission` closures and a `lexicon` — `InputPipelineTestRunner` uses these to test the pipeline without real detection or event posting (the learning tests run the real detector on the bundled models with an in-memory `PersonalLexicon`).

## Architecture

Module graph (Package.swift): `Utils` ← `Core` ← `UI` ← `SwitchFixApp`, and `LanguageModel` ← `Core`. `TestRunner` and `InputPipelineTestRunner` are extra executable targets. `LanguageModel` (character n-gram models, plan 005) has no dependencies; it and the `ModelTrainer` executable build on Linux (`swift build --product ModelTrainer`), unlike the AppKit/Carbon targets.

**Input pipeline** (design rationale in `plan/003_zero_lag_input_pipeline.md` — governing rule: physical input is never delayed; observation may be skipped and corrections cancelled, but text is never mutated when context is stale):

1. `KeyboardMonitor` — a **listen-only** `CGEventTap` (session, falling back to HID) turns events into `CapturedInput` and hands them to `InputEngine.enqueue`. Key-downs are classified by the pure `KeyboardMonitor.classifyKeyDown`; the system input-source shortcuts (ids 60/61 of `com.apple.symbolichotkeys`, default Ctrl+Space / Ctrl+Option+Space, none with a single input source; re-read with the translation table) count as `.inputSourceKey`, like Globe. A plain single left click (at mouse-up, no drag; `PlainClickTracker`) and ←/→/Home/End (Cmd/Opt+←/→ too) are `.caretMove` (caret placed, text untouched); other shortcuts, ↑/↓/PgUp/PgDn, forward delete and modified clicks are `.navigation`/`.focusMayChange` (possible unseen edit).
2. `CaptureStateStore` (in `CapturedInput.swift`) is the lock-protected shared truth: current `InputContextSnapshot` (epoch, frontmost PID, app allowed, layout, input source, secure-focus state), physical sequence number, edit generation, correction epoch, hotkeys, pending-queue depth.
3. `InputEngine` serializes work on separate queues (input / detection / correction / selection). `InputStateMachine` owns the word buffer and emits `InputStateCommand`s (`flush`, `invalidate`, `requestManualCorrection`, `requestRevert`, …).
4. On `flush`, `LayoutDetector` (+ `NgramMarginScorer`, `ShortWordTable`, `LayoutMapper`) decides whether the keystrokes read better in another layout. Manual hotkey uses `forceConversion`, converting even words the model does not recognize; source layout is inferred from the word's script, not the active input source. `LayoutMapper` converts through the physical key using `KeyboardTables` (`KeyTables.swift`): the app builds them from the enabled layouts (`KeyTableBuilder` via `UCKeyTranslate`, sanitized on top of `KeyboardTables.pc`), last-used source per layout first (`InputSourceManager`, which `switchTo` also follows). Tests, LayoutEval, the sweep and `PersonalLexicon` validation use the static `KeyboardTables.pc` (US / RussianWin / Ukrainian-PC, legacy Ukrainian as second candidate), so real-layout tables never change eval numbers.
5. Before emitting, `prepareCorrection` / `CorrectionPlan.isEligible` re-check sequence, edit generation, correction epoch, context equality, secure focus and app allow-list. Any mismatch cancels the correction — preserve these staleness guards when changing the pipeline. Then, when `screenTextRequest` is set (mode `SwitchFix_fieldTextCheck`: `off` / `shadow`, logs only / `enforce`, the default), the engine reads the text before the caret (`AccessibilityFocusCoordinator.requestFieldText`, never turns AXManualAccessibility on; terminals bypassed in `AppDelegate`) and `ScreenVerification.verdict` decides: a selection or a changed word cancels, except an autocorrected word (`.replaced`: same script and first letter, ≤2 edits, bounded by a separator; deleted as the field shows it once a second read agrees), a lagging field is re-read until a 150 ms deadline (staleness rechecked before and after every read), an unreadable one fails open; case, smart quotes and NBSP count as equal. A hotkey word just read from the screen (`DetectionRequest.screenVerified`) is not re-read — unless nothing was typed since a caret move (`ScreenSuffix` empty): then it is read only in `enforce` mode, outside terminals, ≥200 ms after the move, and re-read before deleting with a selection or an unreadable field cancelling (`requiresScreenMatch`). Focus resolution and AX focus moves go through `InputEngine.focusResolved`/`focusMoved`, which keep a placed caret; other context changes forget it. With a word buffered, a selection is the app's inline suggestion: in `enforce` the hotkey and layout-switch mode ignore it and correct the word (`ScreenSelectionHandling`), deleting one more character when the text before the selection (only a tail selection is read) ends with the word, else cancelling; once such a selection was seen an unreadable field cancels. The revert hotkey goes through the same check (`TextCorrector.prepareUndo` → check → `takeUndo`/`postUndo`) for the corrected text, except that a mismatch is re-read until the deadline (the field may still be applying the correction) and an autocorrect-like change cancels; a refused revert forgets the undo and never falls back to converting the word.
6. `TextCorrector` posts synthetic Backspace + Unicode events tagged with `switchFixEventMarker` (so the monitor ignores its own events), with modifier flags explicitly cleared. Delivery is `postToPid` by default, or `.cgSessionEventTap` / `.cghidEventTap` per app via `AppPostMode` overrides (e.g. Telegram/Qt). It also handles undo/revert and selection replacement.
7. Learning (plan 005 §4.5/§12): `CorrectionPlan.provenance` (`automatic` / `hotkey` / `hotkeyForced` / `selection` / `layoutSwitch`, never read by `isEligible`) decides what an applied or reverted correction teaches `PersonalLexicon` (Core; JSON in `SwitchFix_personalLexicon`, debounced save, detector reads it under a lock). `RevertPlan.recorded` is the reverted plan. Reverting a single-token `automatic` correction adds "never correct"; a `hotkeyForced` conversion (the detector did not recognize the word) adds "always correct" and its revert forgets it; `manual` entries (Words tab) are never changed by learning. Keys are the word without trailing punctuation (`LayoutDetector.lexiconWord(from:)`). Reverting a `hotkey` correction forgets a rule learned from the hotkey that converts the word to the same target (the detector applied it). A correction cancelled after detection (any cancel above, or a failed emission) is reported back with `LayoutDetector.noteCorrectionNotApplied(detectionID)`: it stops counting as corrected in the short-word context, and the layout-switch confirmation is restored if nothing was detected since.

`AppDelegate` is the glue: it observes frontmost-app and input-source changes (`kTISNotifySelectedKeyboardInputSourceChanged`) and publishes new contexts via `CaptureStateStore.replaceContext`, distinguishing layout switches SwitchFix itself initiated (`InputSourceManager.consumeExpectedSelection`). `AccessibilityFocusCoordinator` (in `Utils/Permissions.swift`) resolves secure-field focus asynchronously per epoch and reads selected text via AX (setting `AXManualAccessibility` only when focus is invisible without it, switched back off 30 s after the last such query and on quit — left on it puts VS Code into screen-reader mode). A new epoch orphans pending focus queries — after a context change, call `focusMayChange` or keystrokes are dropped until focus resolves.

**Language models** (plan 005 — the only detector; dictionaries were removed): `Sources/LanguageModel/Resources/*.sfng` are committed build inputs produced by `ModelTrainer` from `scripts/fetch-corpora.sh` corpora. The alphabet in `ModelLanguage` and the normalization in `TextNormalization` are part of the model contract — changing either requires retraining (which also regenerates `ShortWordTable+Generated.swift`). `LayoutDetector.checkBuffer` converts English ↔ native Cyrillic only (never ru ↔ uk), checks `PersonalLexicon` rules first, uses `ShortWordTable` for ≤3 letters and per-length margin thresholds in `DetectionThresholds` (`NgramScoring.swift`) otherwise; the Sensitivity slider (`SwitchFix_detectionSensitivity`, positions 0–4) shifts those thresholds via `DetectionThresholds.forSensitivity`. After retraining a model, rerun `TestRunner --threshold-sweep`, update `plan/benchmarks/thresholds_005.md` and `DetectionThresholds.calibratedModelChecksums` — a TestRunner check fails otherwise. Automatic correction is enabled only for layouts whose model (and the English one) loaded (`LanguageModelReadiness`). The SwiftPM bundle may be flat or have `Contents/Resources`; `build-app.sh` and `LanguageModelStore.resourceURL` both handle either layout — keep them in sync; `build-app.sh` fails if the bundle or any `.sfng` is missing. `Tests/LayoutEval` (UD treebanks + hand-written mixed messages) is the held-out eval set; never train on it; dictionary-engine reference numbers are frozen in `plan/benchmarks/baseline_005.md`.

**UI / preferences**: `PreferencesManager` wraps `UserDefaults` (domain `com.switchfix.app`, keys prefixed `SwitchFix_`) and posts `.preferencesDidChange`; `AppFilter` owns the per-app allow/deny list (`.appFilterDidChange`). The Settings window is an AppKit `NSTabViewController` with toolbar-style tabs (General / Correction / Apps / Words / About), each tab a SwiftUI view in an `NSHostingController` (`SettingsWindowController.swift`). Hotkey `keyCode` 58/59 with modifiers 0 means a lone Option/Control tap (`TapModifierHotkey`).

**Localization**: `L10n.tr("English text")` looks up a Russian translation from an in-code dictionary keyed by the English string, falling back to English. Every new user-facing string must go through `L10n.tr` and get a Russian entry in `Sources/UI/L10n.swift`; a duplicate key crashes the first Russian lookup (CI checks for it). In SwiftUI files `Layout` is ambiguous with SwiftUI's protocol — use `KeyboardLayout` (alias in `LearnedWordsView.swift`).

## Process

- Every code change goes through the `run-task-pipeline` skill (its triage picks the preset). Process
  skills are `superpowers:*`; in cloud sessions the same skills exist without the prefix (vendored in
  `.claude/skills/`, one-off copies — edit `rtp` there and run its `scripts/regress.sh`).
- Task tracker: `docs/tasks/`. CLI: `rtp`, **never `npx rtp`** (an unrelated npm package). If `rtp` is not
  on PATH, from the repo root: `node .claude/skills/run-task-pipeline/scripts/rtp.mjs <sub>` (no quotes
  around the path). `rtp next <id>` in the review phase prints this project's checks from `docs/tasks/.rtp.json`.
- Cloud sessions (`CLAUDE_CODE_REMOTE=true`, Ubuntu) have no Swift: `rtp next` hides the swift checks there
  (`"only": "local"` in `.rtp.json`); push the branch and record the green CI run
  (`.github/workflows/ci.yml` runs on `claude/**`): `rtp verify <id> --record "CI зелёный: <run url>"`.
  Link the **push** run of the code commit: a commit that touches only `docs/tasks/**` starts no push run,
  so recording the evidence does not cancel it (pull_request runs of an open PR still cancel each other).
- Cloud sessions cannot push tags: a release there = bump the version in `Resources/Info.plist` on master;
  the `v*` tag and the GitHub release are made locally.
- Never push to `upstream` (`rundax/SwitchFix`).

## Debugging

Logs go through `SwitchFixLog.<category>` (subsystem `com.switchfix`), every message prefixed `[SwitchFix]` with public values (the raw `Logger`s in `InputEngine`/`TextCorrector` mark values public explicitly). Typed text (buffer, words, selection) must go through `SwitchFixLog.text(_:)`, which logs only the length, and per-key input is logged without its key code (`InputEngine.logDescription`), unless `defaults write com.switchfix.app SwitchFix_logTypedText -bool YES` (read at launch):

```bash
log stream --level debug --predicate 'subsystem == "com.switchfix"'
```

Rebuilding with ad-hoc signing invalidates Accessibility/Input Monitoring grants; use `setup-codesign.sh` once. `scripts/regrant-permissions.sh` and `scripts/cleanup-tcc.sh` exist for broken TCC state.

## Conventions

- Commit messages use conventional prefixes with a scope (`feat(ui):`, `fix(focus):`, `ci:`, `docs(readme):`); fork docs/README text is in Russian, code and comments in English.
- `plan/` holds design documents; `004_per_app_default_language.md` is not yet implemented; `005_ngram_layout_detection.md` (character n-gram detector, learning from reverts, Words tab, sensitivity slider) is implemented — see its §12 and `plan/benchmarks/`.
