# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

SwitchFix is a macOS 13+ menu bar app (Swift Package, no Xcode project) that detects words typed in the wrong keyboard layout (English ↔ Ukrainian/Russian), deletes them, switches the input source and retypes the converted text. This repo is a fork of `rundax/SwitchFix` (`upstream` remote); fork-specific changes are described in the Russian section of README.md.

## Commands

```bash
swift build -c release                         # compile all targets
swift run -c release TestRunner                # detection/dictionary/mapper tests + perf suites
swift run -c release InputPipelineTestRunner   # capture → state machine → correction pipeline tests
swift run -c release InputPipelineTestRunner --integration-smoke   # also posts real CGEvents into an NSTextView
./scripts/build-app.sh                         # → dist/SwitchFix.app (compiles .bin dictionaries, signs)
./scripts/create-dmg.sh                        # → dist/SwitchFix.dmg
./install.sh                                   # build + install to /Applications + login item + permissions
./scripts/setup-codesign.sh                    # one-time: stable self-signed identity in .codesign-identity
```

CI (`.github/workflows/ci.yml`) runs exactly: release build, both test runners, then `build-app.sh` ad-hoc signed. Releases are built on `v*` tags; the version lives in `Resources/Info.plist` (`CFBundleShortVersionString` / `CFBundleVersion`).

### Tests

There is no XCTest/swift-testing target (it needs a full Xcode install); `Tests/SwitchFixTests` is a stub. Tests are plain executables with hand-rolled `assert`/`assertEqual`/`check` helpers that exit 1 on failure. There is no per-test filter — to run one case, comment out other `runSuite` calls locally or add a new suite. `TestRunner` must be run from the repo root: it calls `DictionaryLoader.shared.enableTextFallbackForTesting()` and reads `Sources/Dictionary/Resources/*.txt` directly (production only loads mmap'd `.bin` files).

`InputEngine` accepts injectable `exactDetection` / `correctionEmission` / `selectedTextRequest` closures — `InputPipelineTestRunner` uses these to test the pipeline without real dictionaries or event posting.

## Architecture

Module graph (Package.swift): `Utils` ← `Dictionary` ← `Core` ← `UI` ← `SwitchFixApp`. `TestRunner` and `InputPipelineTestRunner` are extra executable targets.

**Input pipeline** (design rationale in `plan/003_zero_lag_input_pipeline.md` — governing rule: physical input is never delayed; observation may be skipped and corrections cancelled, but text is never mutated when context is stale):

1. `KeyboardMonitor` — a **listen-only** `CGEventTap` (session, falling back to HID) turns events into `CapturedInput` and hands them to `InputEngine.enqueue`.
2. `CaptureStateStore` (in `CapturedInput.swift`) is the lock-protected shared truth: current `InputContextSnapshot` (epoch, frontmost PID, app allowed, layout, input source, secure-focus state), physical sequence number, edit generation, correction epoch, hotkeys, pending-queue depth.
3. `InputEngine` serializes work on separate queues (input / detection / correction / selection). `InputStateMachine` owns the word buffer and emits `InputStateCommand`s (`flush`, `invalidate`, `requestManualCorrection`, `requestRevert`, …).
4. On `flush`, `LayoutDetector` (+ `WordValidator`, `ScriptAnalyzer`, `LayoutMapper`) decides whether the word is valid in another layout. Manual hotkey uses `forceConversion`, converting even words missing from the dictionary; source layout is inferred from the word's script, not the active input source.
5. Before emitting, `prepareCorrection` / `CorrectionPlan.isEligible` re-check sequence, edit generation, correction epoch, context equality, secure focus and app allow-list. Any mismatch cancels the correction — preserve these staleness guards when changing the pipeline.
6. `TextCorrector` posts synthetic Backspace + Unicode events tagged with `switchFixEventMarker` (so the monitor ignores its own events), with modifier flags explicitly cleared. Delivery is `postToPid` by default, or `.cgSessionEventTap` / `.cghidEventTap` per app via `AppPostMode` overrides (e.g. Telegram/Qt). It also handles undo/revert and selection replacement.

`AppDelegate` is the glue: it observes frontmost-app and input-source changes (`kTISNotifySelectedKeyboardInputSourceChanged`) and publishes new contexts via `CaptureStateStore.replaceContext`, distinguishing layout switches SwitchFix itself initiated (`InputSourceManager.consumeExpectedSelection`). `AccessibilityFocusCoordinator` (in `Utils/Permissions.swift`) resolves secure-field focus asynchronously per epoch and reads selected text via AX (setting `AXManualAccessibility` for Electron). A new epoch orphans pending focus queries — after a context change, call `focusMayChange` or keystrokes are dropped until focus resolves.

**Dictionaries**: source word lists are `Sources/Dictionary/Resources/{en_US,ru_RU,uk_UA}.txt` plus `overrides/*_allow.txt` / `*_deny.txt`. `build-app.sh` compiles them with `scripts/compile_dictionary.swift` into `.build/dictionary-bin/*.bin` (format `SFDICT2`, see `DictionaryBinaryFormat.swift`, with bloom filter), copies them into `SwitchFix_Dictionary.bundle` and deletes the `.txt` files. Newer SwiftPM emits the bundle with `Contents/Resources`; `build-app.sh` and `DictionaryLoader.findDictionaryURL` both handle either layout — keep them in sync, otherwise correction silently stops working. Automatic correction is only enabled for layouts whose dictionary prepared successfully (`AutomaticDictionaryReadiness`).

**UI / preferences**: `PreferencesManager` wraps `UserDefaults` (domain `com.switchfix.app`, keys prefixed `SwitchFix_`) and posts `.preferencesDidChange`; `AppFilter` owns the per-app allow/deny list (`.appFilterDidChange`). The Settings window is an AppKit `NSTabViewController` with toolbar-style tabs (General / Correction / Apps / About), each tab a SwiftUI view in an `NSHostingController` (`SettingsWindowController.swift`). Hotkey `keyCode` 58/59 with modifiers 0 means a lone Option/Control tap (`TapModifierHotkey`).

**Localization**: `L10n.tr("English text")` looks up a Russian translation from an in-code dictionary keyed by the English string, falling back to English. Every new user-facing string must go through `L10n.tr` and get a Russian entry in `Sources/UI/L10n.swift`.

## Debugging

Logs go through `SwitchFixLog.<category>` (subsystem `com.switchfix`), every message prefixed `[SwitchFix]` with public values:

```bash
log stream --level debug --predicate 'subsystem == "com.switchfix"'
```

Rebuilding with ad-hoc signing invalidates Accessibility/Input Monitoring grants; use `setup-codesign.sh` once. `scripts/regrant-permissions.sh` and `scripts/cleanup-tcc.sh` exist for broken TCC state.

## Conventions

- Commit messages use conventional prefixes with a scope (`feat(ui):`, `fix(focus):`, `ci:`, `docs(readme):`); fork docs/README text is in Russian, code and comments in English.
- `plan/` holds design documents; `004_per_app_default_language.md` and `005_ngram_layout_detection.md` (replace dictionaries with a character n-gram model + learning from reverts) are plans that are not yet implemented.
