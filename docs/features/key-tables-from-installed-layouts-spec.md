# Key tables from installed keyboard layouts — spec

Task: `docs/tasks/2026-09-29-key-tables-from-installed-keyboard-layouts.md`.
Revision 2 (after spec-review; findings B1–B3, M1–M7, m1–m6 addressed below).

## Problem

`LayoutMapper` converts text with hard-coded character tables written for the PC
layouts (`RussianWin`, `Ukrainian-PC`) over US QWERTY. Measured with `UCKeyTranslate`
(2026-09-29, macOS 27, `LMGetKbdType()` = 91):

| Key | US / Australian | RussianWin | Russian (mac) | Ukrainian-PC | Ukrainian (mac) | British-PC |
|---|---|---|---|---|---|---|
| Shift+2 | `@` | `"` | `"` | `"` | `"` | `"` |
| Shift+3 | `#` | `№` | `№` | `№` | `№` | `£` |
| Shift+4 | `$` | `;` | `%` | `;` | `%` | `$` |
| Shift+5 | `%` | `%` | `:` | `%` | `:` | `%` |
| Shift+6 | `^` | `:` | `,` | `:` | `,` | `^` |
| Shift+7 | `&` | `?` | `.` | `?` | `.` | `&` |
| Shift+8 | `*` | `*` | `;` | `*` | `;` | `*` |
| `` ` `` / Shift | `` ` `` `~` | `ё` **`Ë` (Latin U+00CB)** | `]` `[` | `ґ` `Ґ` | `'` `~` | `\` `\|` |
| `\` / Shift | `\` `\|` | `\` `/` | `ё` `Ё` | `ʼ` `₴` | `ґ` `Ґ` | `#` `~` |
| `/` / Shift | `/` `?` | `.` `,` | `/` `?` | `.` `,` | `/` `?` | `/` `?` |

Consequences seen in manual testing: `"ьфшд` → `"mail` instead of `@mail`. On the mac
`Russian` / `Ukrainian` layouts even `.`/`,`/`ё` map to the wrong keys; Colemak/Dvorak
(listed as English) convert by QWERTY positions. `UkrainianKeyboardVariant`
(standard/legacy, и/і swap) is a one-off patch for the same root cause. System data is
not always sane (RussianWin gives a Latin `Ë`), so it must be validated.

## Solution

Convert through the physical key: character → key stroke on a table of the source layout
→ character of the same key stroke on a table of the target layout.

### Data model (Core)

- `struct KeyStroke: Hashable, Sendable { keyCode: UInt16; shift: Bool }`.
- `struct KeyTable: Equatable, Sendable` — `keyToChar: [KeyStroke: Character]`,
  `charToKey: [Character: KeyStroke]`. Main block only: a fixed ordered key-code list of
  the letter, digit and punctuation keys (ANSI block; ISO keys 10 and 50 included).
  Layers: none and Shift. No Option layer, no dead keys, no control/whitespace output.
  - `charToKey` collisions: unshifted beats shifted, then key-list order.
- `struct KeyboardTables: Equatable, Sendable` — for each `Layout`, an ordered non-empty
  list of candidate `KeyTable`s (first = the one the user most likely typed on).
  `KeyboardTables.pc` = one table per layout generated from today's static tables
  (US QWERTY, RussianWin, Ukrainian-PC standard).
- One builder: `KeyTableBuilder.table(uchr: Data, keyboardType: UInt32) -> KeyTable`
  replaces the two existing `UCKeyTranslate` helpers' duplication for this purpose
  (`InputSourceManager.translatedCharacter` goes away with the variant;
  `KeyboardMonitor.translatedCharacter` stays — it serves live key events).

### Sanity overlay (from review m3/m5)

A system table is merged **on top of** the `.pc` table of its layout, key by key:

1. A key whose system output is a letter outside the layout's alphabet (Latin letter on a
   Cyrillic layout, Cyrillic on English — e.g. RussianWin Shift+`` ` `` = `Ë`) keeps the
   `.pc` output for that stroke.
2. If two letter keys still produce the same letter after step 1 (a .pc letter kept on a key is dropped when the system already puts it elsewhere), the whole system table is rejected. The ISO section key (10) is left out of this check — it
   legitimately repeats another key (RussianWin: `ё` on keys 10 and 50) —
   (logged once per source ID at `info`), `.pc` is used.
3. Sources whose letter keys are not ЙЦУКЕН/QWERTY-shaped by design are not read from the
   system: `Russian-Phonetic` → `.pc` (thresholds were never calibrated on phonetic
   mappings). No other exclusions.
4. A source whose `uchr` data cannot be read → `.pc`, logged once at `info`.

### Conversion API

- `LayoutMapper.convert(_:from:to:tables:)` — `tables[from]` first candidate's
  `charToKey`, then `tables[to]` first candidate's `keyToChar`; characters without a key
  or keys without a target character are left as-is. `from == to` returns the text.
- `LayoutMapper.convertCandidates(_:from:to:tables:)` — one conversion per source
  candidate, deduplicated, in order. Replaces the detector's "fallback Ukrainian variant"
  loop generically (review M6): the detector tries candidates in order, first one that
  clears its threshold wins (today's rule for the variant fallback).
- `convertToAlternatives(_:from:tables:)` as today, using first candidates.
- ru↔uk (hotkey/selection only) goes through keys as well; the static ru↔uk tables,
  `enToUkLegacy` and `UkrainianKeyboardVariant` are removed.
- Default argument `tables: .pc` everywhere, so tests/eval code keeps compiling.

### Where tables come from (App/Core)

- `InputSourceManager` builds a (sanitized) `KeyTable` per discovered keyboard source
  in `refreshInstalledSources`, and additionally re-runs it on
  `kTISNotifyEnabledKeyboardInputSourcesChanged` (review M2; off the hot path, then the
  app republishes the detection configuration).
- It tracks the **last-used source per layout** (updated on every input-source change;
  initially the active source for its layout, else the first discovered).
  `keyboardTables(overrides: [Layout: String] = [:])` returns, per layout: the override
  source (if given) or the last-used source first, then the other enabled sources of
  that layout (deduplicated by table equality); fallback `.pc`.
- `switchTo(layout)` selects the last-used source of that layout (today: first
  discovered), so the retyped text and subsequent typing use the same table.
- Keyboard type: live `LMGetKbdType()` when building; tables are not rebuilt when a
  different physical keyboard is connected (out of scope, logged as debt).

### Engine plumbing (review M7, caller list m6)

- `DetectionConfiguration.keyboardTables` replaces `ukrainianFromVariant/ToVariant`
  (`InputEngine.swift` ~41, ~241, ~369–392, ~663); `LayoutDetector.keyboardTables`
  replaces its variant properties (~50, ~278–295, ~499). The configuration is captured
  per request as today, so staleness guards are unaffected.
- `handleLayoutChange(from:to:context:keyboardTables:)` receives tables built with
  `overrides: [old: oldSourceID, new: newSourceID]` (`AppDelegate` ~233–246).
- `AppDelegate.updateDetectionConfiguration` (~373) passes `keyboardTables()`.
- `LayoutEval.swift` (~148, ~154) and TestRunner variant tests (`main.swift` ~76–103,
  ~283/339/379/542/578) move to `KeyboardTables`; legacy-variant tests become tests of a
  legacy-shaped candidate table.

### Word boundaries (review B1)

Unchanged: `KeyboardMonitor.boundaryCharacterSet` / `softBoundaryCharacterSet` stay
character-based. Consequence, documented as a known limitation (debt): characters like
`№ ? @ # $ % ^ & *` still end the buffered word, so they are converted only when they
sit inside a selection, or when they are soft (`"` → `@` inside `"ьфшд`). Deciding
boundaries by physical key is a separate task.

### Personal lexicon (review B3, M5)

`PersonalLexicon.validate` / `LayoutMapper.canBeTyped` keep today's semantics and use
`.pc` only: validation never depends on the installed layouts, so a saved entry cannot
become invalid on load after the user changes layouts.

### Invariants

- plan/003 staleness guards untouched; no TIS calls on input/detection/correction paths.
- `LayoutEval`, threshold sweep, `calibratedModelChecksums` unchanged (they run on `.pc`).
- `ModelTrainer` keeps its own lowercase-letter mirror (Linux target, cannot import Core);
  `.pc` letters must equal it — a TestRunner check compares the two strings (copied
  constant with a comment pointing at `ModelTrainer/main.swift`). Core itself is
  macOS-only (review B2).

## Acceptance criteria

Tables for tests are built from `TISCreateInputSourceList(…, includeAllInstalled: true)`
filtered by ID, so no layout needs to be enabled; a missing layout skips its case with
a printed note. ISO-sensitive keys (10, 50) are not used in assertions except via the
`.pc` equality check.

1. `LayoutMapper` with system tables (selection/hotkey path — whole strings):
   - RussianWin → US: `"ьфшд` → `@mail`, `№1` → `#1`, `;5` → `$5`, `:` → `^`, `?` → `&`;
     US → RussianWin: `user@mail.com` → `гыук"ьфшдюсщь`.
   - Russian (mac) → US: `.` → `&`, `,` → `^`, `руддщ` → `hello`.
   - Ukrainian-PC: `ghbdsn` ↔ `привіт`; Ukrainian (mac) is the legacy variant: `ghsdbn` ↔ `привіт`.
   - RussianWin: Latin `Ë` never appears; `Ё` round-trips through its key (the key is
     `~` on ANSI, `±` on ISO keyboards).
   - Australian table == US table.
   - Sanitized RussianWin / US / Ukrainian-PC tables agree with `.pc` on every character
     of the old static tables.
2. Automatic path (InputPipelineTestRunner, injected tables): `"ьфшд` typed as one
   word + hotkey → `@mail` with RussianWin/US tables; `.pc` behaviour unchanged.
3. `.pc` conversions and `canBeTyped` identical to today's (existing suites green;
   LayoutEval numbers unchanged — compare the TestRunner table with the pre-change run).
4. `UkrainianKeyboardVariant` no longer exists.
5. Full TestRunner / InputPipelineTestRunner green; `build-app.sh` builds.
6. Manual on the user's Mac (RussianWin + Australian): scenario A, `"ьфшд` + hotkey →
   `@mail`, scenario G.

## Out of scope (→ debt)

- Physical-key word boundaries (`№`, `?`, `@`, … ending the word).
- Option layer, dead keys, Caps Lock specifics (Caps+punctuation behaves as today:
  Cyrillic capitals on punctuation keys map to the shifted US symbol).
- Rebuilding tables when the keyboard type changes.
- Report-only LayoutEval on real (non-`.pc`) tables.
- Sharing key data with `ModelTrainer` via a common dependency-free target.
