# Key tables from installed layouts — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert text through the physical key using tables read from the installed macOS keyboard layouts, replacing the static PC tables and `UkrainianKeyboardVariant`.

**Architecture:** New value types `KeyStroke` / `KeyTable` / `KeyboardTables` in Core; `KeyboardTables.pc` reproduces today's static tables and stays the default for tests and eval. `KeyTableBuilder` reads `uchr` data via `UCKeyTranslate` and sanitizes it on top of `.pc`. `InputSourceManager` owns per-source tables and the last-used source per layout; `AppDelegate` publishes `KeyboardTables` into `InputEngine`'s detection configuration in place of the Ukrainian variants.

**Tech Stack:** Swift 5.9+/SwiftPM, Carbon (TIS, `UCKeyTranslate`), hand-rolled test executables (`TestRunner`, `InputPipelineTestRunner`).

**Spec:** `docs/features/key-tables-from-installed-layouts-spec.md` (revision 2).

## Global Constraints

- macOS 13+, no new dependencies; Core stays macOS-only.
- plan/003 staleness guards (`prepareCorrection`, `CorrectionPlan.isEligible`) untouched; no TIS calls on input/detection/correction queues.
- `LayoutEval`, `--threshold-sweep`, `DetectionThresholds.calibratedModelChecksums` unchanged — everything test/eval-side runs on `KeyboardTables.pc`.
- `PersonalLexicon.validate` / `LayoutMapper.canBeTyped` keep today's semantics on the static tables.
- Word-boundary character sets in `KeyboardMonitor` unchanged.
- Code/comments in English; commits `feat(layout):` / `refactor(layout):` / `test(layout):` with the attribution trailer.
- Run tests from the repo root: `swift run -c release TestRunner`, `swift run -c release InputPipelineTestRunner`.

**Spec deviation (deliberate):** `KeyboardTables.pc` holds **two** Ukrainian candidates `[standard, legacy]`, reproducing today's default detector behaviour (from-variant standard, legacy tried as fallback), so LayoutEval numbers stay identical.

## File map

- Create `Sources/Core/KeyTables.swift` — `KeyStroke`, `KeyTable`, `KeyboardTables`, `.pc` data (static PC dictionaries move here from `LayoutMapper`).
- Create `Sources/Core/KeyTableBuilder.swift` — `UCKeyTranslate` reader, sanity overlay, installed-source lookup.
- Modify `Sources/Core/LayoutMapper.swift` — conversion via `KeyboardTables`; delete `UkrainianKeyboardVariant` and variant overloads.
- Modify `Sources/Core/InputSourceManager.swift` — per-source tables, last-used source, `keyboardTables(overrides:)`, `switchTo` uses last-used; delete variant code.
- Modify `Sources/Core/LayoutDetector.swift`, `Sources/Core/InputEngine.swift`, `Sources/SwitchFixApp/AppDelegate.swift` — plumbing.
- Create `Sources/TestRunner/KeyTableTests.swift`; modify `Sources/TestRunner/main.swift`, `Sources/InputPipelineTestRunner/main.swift`.
- Modify `CLAUDE.md` (architecture paragraph).

---

### Task 1: Key table types and `.pc` equivalence

**Files:**
- Create: `Sources/Core/KeyTables.swift`
- Modify: `Sources/Core/LayoutMapper.swift` (add table-based overloads next to the old ones; old ones stay until Task 4)
- Test: `Sources/TestRunner/KeyTableTests.swift`, call from `Sources/TestRunner/main.swift`

**Interfaces — Produces:**
- `public struct KeyStroke: Hashable, Sendable { public let keyCode: UInt16; public let shift: Bool; public init(_ keyCode: UInt16, shift: Bool = false) }`
- `public struct KeyTable: Equatable, Sendable { public let keyToChar: [KeyStroke: Character]; public let charToKey: [Character: KeyStroke]; public init(keyToChar:); public func replacing(_ stroke: KeyStroke, with character: Character?) -> KeyTable; public static let mainBlockKeyCodes: [UInt16]; public static let pcEnglish, pcRussian, pcUkrainian, pcUkrainianLegacy: KeyTable }`
- `public struct KeyboardTables: Equatable, Sendable { public init(_ candidates: [Layout: [KeyTable]]); public func candidates(for: Layout) -> [KeyTable]; public func primary(for: Layout) -> KeyTable; public func with(_ layout: Layout, _ tables: [KeyTable]) -> KeyboardTables; public static let pc }`
- `LayoutMapper.convert(_ text: String, from: Layout, to: Layout, tables: KeyboardTables) -> String` (no default in Task 1 — it would be ambiguous with the old overload; Task 4 deletes the old overload and adds `= .pc`)
- `LayoutMapper.convert(_ text: String, from: KeyTable, to: KeyTable) -> String`
- `LayoutMapper.convertCandidates(_ text: String, from: Layout, to: Layout, tables: KeyboardTables) -> [String]`
- `LayoutMapper.convertToAlternatives(_ text: String, from: Layout, tables: KeyboardTables) -> [(Layout, String)]`
- `enum PCLayoutData` (internal): `enToRu`, `enToUkStandard`, `enToUkLegacy` dictionaries.

- [ ] **Step 0: Freeze the eval baseline (before any code change)**

```bash
swift run -c release TestRunner --layout-eval-only > .build/eval-before.txt
swift run -c release TestRunner --threshold-sweep > .build/sweep-before.txt
```

- [ ] **Step 1: Write the failing test** — `Sources/TestRunner/KeyTableTests.swift`:

```swift
import Core

func runKeyTableTests() {
    runSuite("KeyTables: .pc reproduces the static tables") {
        // Every character the old tables know, both directions, all layout pairs.
        let samples = [
            "qwertyuiop[]asdfghjkl;'zxcvbnm,./`QWERTYUIOP{}ASDFGHJKL:\"ZXCVBNM<>?~",
            "йцукенгшщзхъфывапролджэячсмитьбю.ёЙЦУКЕНГШЩЗХЪФЫВАПРОЛДЖЭЯЧСМИТЬБЮ,Ё",
            "йцукенгшщзхїфівапролджєячсмитьбю.ґЙЦУКЕНГШЩЗХЇФІВАПРОЛДЖЄЯЧСМИТЬБЮ,Ґ",
            "hello, мир! 123 @#$ user@mail.com ghbdtn иууьи",
        ]
        for text in samples {
            for from in Layout.allCases {
                for to in Layout.allCases {
                    assertEqual(
                        LayoutMapper.convert(text, from: from, to: to, tables: .pc),
                        LayoutMapper.convert(text, from: from, to: to),
                        "\(from)→\(to) '\(text)'"
                    )
                }
            }
        }
    }

    runSuite("KeyTables: legacy Ukrainian candidate") {
        let legacyFirst = KeyboardTables.pc.with(.ukrainian, [.pcUkrainianLegacy, .pcUkrainian])
        assertEqual(LayoutMapper.convert("seems", from: .english, to: .ukrainian, tables: .pc), "іууьі")
        assertEqual(LayoutMapper.convert("seems", from: .english, to: .ukrainian, tables: legacyFirst), "иууьи")
        assertEqual(LayoutMapper.convert("иууьи", from: .ukrainian, to: .english, tables: legacyFirst), "seems")
        assertEqual(
            LayoutMapper.convertCandidates("иууьи", from: .ukrainian, to: .english, tables: .pc),
            ["beemb", "seems"],
            ".pc tries standard first, legacy second (today's fallback)"
        )
    }

    runSuite("KeyTables: collisions prefer the unshifted key") {
        let table = KeyTable(keyToChar: [KeyStroke(44): ".", KeyStroke(47, shift: true): "."])
        assertEqual(table.charToKey["."], KeyStroke(44))
    }

    runSuite("KeyTables: ModelTrainer mirror matches .pc letters") {
        // Copied from Sources/ModelTrainer/main.swift (englishKeys / cyrillicKeys) — keep in sync.
        let english = "qwertyuiop[]asdfghjkl;'zxcvbnm,.`"
        assertEqual(LayoutMapper.convert(english, from: .english, to: .russian, tables: .pc),
                     "йцукенгшщзхъфывапролджэячсмитьбюё")
        assertEqual(LayoutMapper.convert(english, from: .english, to: .ukrainian, tables: .pc),
                     "йцукенгшщзхїфівапролджєячсмитьбюґ")
    }
}
```

In `Sources/TestRunner/main.swift`, right after the `"LayoutMapper: Same layout"` suite, add the call `runKeyTableTests()`.

- [ ] **Step 2: Run to verify it fails**

Run: `swift build -c release --product TestRunner`
Expected: compile error `cannot find 'KeyboardTables' in scope`.

- [ ] **Step 3: Implement `Sources/Core/KeyTables.swift`**

```swift
import Foundation

/// A physical key press on the main block: key code plus Shift.
public struct KeyStroke: Hashable, Sendable {
    public let keyCode: UInt16
    public let shift: Bool

    public init(_ keyCode: UInt16, shift: Bool = false) {
        self.keyCode = keyCode
        self.shift = shift
    }
}

/// Characters one keyboard layout produces on the main block (no Option layer, no dead keys).
public struct KeyTable: Equatable, Sendable {
    public let keyToChar: [KeyStroke: Character]
    public let charToKey: [Character: KeyStroke]

    /// Main-block key codes in collision tie-break order: letter rows, then the digit row,
    /// then the ANSI backslash and the ISO section key (10).
    public static let mainBlockKeyCodes: [UInt16] = [
        12, 13, 14, 15, 17, 16, 32, 34, 31, 35, 33, 30,
        0, 1, 2, 3, 5, 4, 38, 40, 37, 41, 39,
        6, 7, 8, 9, 11, 45, 46, 43, 47, 44,
        50, 18, 19, 20, 21, 23, 22, 26, 28, 25, 29, 27, 24, 42, 10,
    ]

    public init(keyToChar: [KeyStroke: Character]) {
        self.keyToChar = keyToChar
        // Unshifted beats shifted, then key-list order: deterministic reverse map.
        var reverse: [Character: KeyStroke] = [:]
        for shift in [false, true] {
            for code in Self.mainBlockKeyCodes {
                let stroke = KeyStroke(code, shift: shift)
                if let character = keyToChar[stroke], reverse[character] == nil {
                    reverse[character] = stroke
                }
            }
        }
        charToKey = reverse
    }

    public func replacing(_ stroke: KeyStroke, with character: Character?) -> KeyTable {
        var map = keyToChar
        map[stroke] = character
        return KeyTable(keyToChar: map)
    }

    /// US QWERTY, full main block.
    public static let pcEnglish = KeyTable(keyToChar: PCLayoutData.usQWERTY)
    public static let pcRussian = KeyTable(keyToChar: PCLayoutData.strokes(for: PCLayoutData.enToRu))
    public static let pcUkrainian = KeyTable(keyToChar: PCLayoutData.strokes(for: PCLayoutData.enToUkStandard))
    public static let pcUkrainianLegacy = KeyTable(keyToChar: PCLayoutData.strokes(for: PCLayoutData.enToUkLegacy))
}

/// Candidate tables per layout; the first one is what the user most likely typed on.
public struct KeyboardTables: Equatable, Sendable {
    private let tables: [Layout: [KeyTable]]

    public init(_ candidates: [Layout: [KeyTable]]) {
        tables = candidates.filter { !$0.value.isEmpty }
    }

    public func candidates(for layout: Layout) -> [KeyTable] {
        tables[layout] ?? Self.pc.tables[layout] ?? []
    }

    public func primary(for layout: Layout) -> KeyTable {
        candidates(for: layout)[0]
    }

    public func with(_ layout: Layout, _ candidates: [KeyTable]) -> KeyboardTables {
        var copy = tables
        copy[layout] = candidates
        return KeyboardTables(copy)
    }

    /// Today's static PC tables (US QWERTY, RussianWin, Ukrainian-PC). The legacy
    /// Ukrainian candidate keeps the detector's old fallback, so eval numbers stay put.
    public static let pc = KeyboardTables([
        .english: [.pcEnglish],
        .russian: [.pcRussian],
        .ukrainian: [.pcUkrainian, .pcUkrainianLegacy],
    ])
}

/// Static PC layout data: the source of truth for `.pc`, `canBeTyped` and lexicon
/// validation. Keys are US QWERTY characters.
enum PCLayoutData {
    // Move here verbatim from LayoutMapper: enToRu, enToUkStandard, enToUkLegacy.
    // (Cut the three dictionaries out of LayoutMapper.swift and paste them here as
    // `static let`, dropping `private`.)

    /// (key code, unshifted, shifted) for US QWERTY.
    static let usKeys: [(UInt16, Character, Character)] = [
        (12, "q", "Q"), (13, "w", "W"), (14, "e", "E"), (15, "r", "R"), (17, "t", "T"),
        (16, "y", "Y"), (32, "u", "U"), (34, "i", "I"), (31, "o", "O"), (35, "p", "P"),
        (33, "[", "{"), (30, "]", "}"),
        (0, "a", "A"), (1, "s", "S"), (2, "d", "D"), (3, "f", "F"), (5, "g", "G"),
        (4, "h", "H"), (38, "j", "J"), (40, "k", "K"), (37, "l", "L"), (41, ";", ":"),
        (39, "'", "\""),
        (6, "z", "Z"), (7, "x", "X"), (8, "c", "C"), (9, "v", "V"), (11, "b", "B"),
        (45, "n", "N"), (46, "m", "M"), (43, ",", "<"), (47, ".", ">"), (44, "/", "?"),
        (50, "`", "~"), (18, "1", "!"), (19, "2", "@"), (20, "3", "#"), (21, "4", "$"),
        (23, "5", "%"), (22, "6", "^"), (26, "7", "&"), (28, "8", "*"), (25, "9", "("),
        (29, "0", ")"), (27, "-", "_"), (24, "=", "+"), (42, "\\", "|"),
    ]

    static let usQWERTY: [KeyStroke: Character] = {
        var map: [KeyStroke: Character] = [:]
        for (code, plain, shifted) in usKeys {
            map[KeyStroke(code)] = plain
            map[KeyStroke(code, shift: true)] = shifted
        }
        return map
    }()

    /// Re-keys a US-character → layout-character table by US key strokes.
    static func strokes(for table: [Character: Character]) -> [KeyStroke: Character] {
        let usStrokes = KeyTable(keyToChar: usQWERTY).charToKey
        var map: [KeyStroke: Character] = [:]
        for (us, native) in table {
            if let stroke = usStrokes[us] { map[stroke] = native }
        }
        return map
    }
}
```

Move `enToRu`, `enToUkStandard`, `enToUkLegacy` from `LayoutMapper` into `PCLayoutData` (as `static let`); in `LayoutMapper` replace their uses with `PCLayoutData.enToRu` etc. so the old API still compiles.

- [ ] **Step 4: Add the table-based API to `LayoutMapper`** (below the old `convert`):

```swift
    /// Convert through the physical key: `from`'s key for each character, then the
    /// character of that key on `to`. Unmapped characters are left as-is.
    public static func convert(_ text: String, from: Layout, to: Layout, tables: KeyboardTables) -> String {
        guard from != to else { return text }
        return convert(text, from: tables.primary(for: from), to: tables.primary(for: to))
    }

    public static func convert(_ text: String, from source: KeyTable, to target: KeyTable) -> String {
        String(text.map { character in
            source.charToKey[character].flatMap { target.keyToChar[$0] } ?? character
        })
    }

    /// One conversion per source candidate table, deduplicated, in candidate order.
    public static func convertCandidates(_ text: String, from: Layout, to: Layout, tables: KeyboardTables) -> [String] {
        guard from != to else { return [text] }
        let target = tables.primary(for: to)
        var results: [String] = []
        for source in tables.candidates(for: from) {
            let converted = convert(text, from: source, to: target)
            if !results.contains(converted) { results.append(converted) }
        }
        return results
    }

    public static func convertToAlternatives(_ text: String, from: Layout, tables: KeyboardTables) -> [(Layout, String)] {
        Layout.allCases.compactMap { target in
            guard target != from else { return nil }
            let converted = convert(text, from: from, to: target, tables: tables)
            return converted == text ? nil : (target, converted)
        }
    }
```

- [ ] **Step 5: Run tests**

Run: `swift run -c release TestRunner 2>&1 | grep -E "FAIL|Results"`
Expected: `Results: N passed, 0 failed`. If the `.pc` equivalence fails on ru↔uk: the old path used `ruToUkStandard` (only ы/э/ъ/ё differ) — through keys, letters identical on both layouts map to themselves, so results must match; investigate any diff before continuing (do not special-case).

- [ ] **Step 6: Commit**

```bash
git add Sources/Core/KeyTables.swift Sources/Core/LayoutMapper.swift Sources/TestRunner/KeyTableTests.swift Sources/TestRunner/main.swift
git commit -m "feat(layout): key-stroke tables with a PC default equal to the static tables"
```

---

### Task 2: `KeyTableBuilder` — system tables with sanity overlay

**Files:**
- Create: `Sources/Core/KeyTableBuilder.swift`
- Test: `Sources/TestRunner/KeyTableTests.swift` (new function `runSystemKeyTableTests()`, called after `runKeyTableTests()`)

**Interfaces — Consumes:** Task 1 types. **Produces:**
- `public enum KeyTableBuilder`
  - `static func rawTable(uchr: Data, keyboardType: UInt32) -> [KeyStroke: Character]`
  - `static func sanitized(_ raw: [KeyStroke: Character], layout: Layout) -> KeyTable?` (nil = letter collision → caller uses `.pc`)
  - `static func table(for source: TISInputSource, layout: Layout, keyboardType: UInt32) -> KeyTable?`
  - `static func installedTable(sourceID: String, layout: Layout) -> KeyTable?` (includeAllInstalled; tests and diagnostics)
- `extension Layout { func ownsLetter(_ c: Character) -> Bool }` (internal)

- [ ] **Step 1: Failing tests**

```swift
func runSystemKeyTableTests() {
    func table(_ id: String, _ layout: Layout) -> KeyTable? {
        let table = KeyTableBuilder.installedTable(sourceID: "com.apple.keylayout.\(id)", layout: layout)
        if table == nil { print("  SKIP: \(id) not installed on this machine") }
        return table
    }

    runSuite("KeyTables: system tables agree with .pc on the old characters") {
        let pairs: [(String, Layout, KeyTable)] = [
            ("US", .english, .pcEnglish), ("RussianWin", .russian, .pcRussian),
            ("Ukrainian-PC", .ukrainian, .pcUkrainian),
        ]
        for (id, layout, pc) in pairs {
            guard let system = table(id, layout) else { continue }
            for (stroke, character) in pc.keyToChar where stroke.keyCode != 10 && stroke.keyCode != 50 {
                assertEqual(system.keyToChar[stroke], character, "\(id) \(stroke)")
            }
        }
    }

    runSuite("KeyTables: shifted digit row and mac layouts") {
        guard let us = table("US", .english), let win = table("RussianWin", .russian) else { return }
        assertEqual(LayoutMapper.convert("\"ьфшд", from: win, to: us), "@mail")
        assertEqual(LayoutMapper.convert("№1", from: win, to: us), "#1")
        assertEqual(LayoutMapper.convert(";5", from: win, to: us), "$5")
        assertEqual(LayoutMapper.convert(":?", from: win, to: us), "^&")
        assertEqual(LayoutMapper.convert("user@mail.com", from: us, to: win), "гыук\"ьфшдюсщь")
        if let mac = table("Russian", .russian) {
            assertEqual(LayoutMapper.convert(".,", from: mac, to: us), "&^")
            assertEqual(LayoutMapper.convert("руддщ", from: mac, to: us), "hello")
        }
        for id in ["Ukrainian", "Ukrainian-PC"] {
            if let uk = table(id, .ukrainian) {
                assertEqual(LayoutMapper.convert("ghbdsn", from: us, to: uk), "привіт", id)
                assertEqual(LayoutMapper.convert("привіт", from: uk, to: us), "ghbdsn", id)
            }
        }
        if let au = table("Australian", .english) { assertEqual(au, us, "Australian ≡ US") }
    }

    runSuite("KeyTables: sanity overlay") {
        // RussianWin Shift+` is a Latin Ë in the system data; .pc's Ё must survive.
        if let win = table("RussianWin", .russian), let us = table("US", .english) {
            assertEqual(LayoutMapper.convert("~", from: us, to: win), "Ё")
            assertEqual(LayoutMapper.convert("Ё", from: win, to: us), "~")
        }
        // ISO variant: 'Ё' on Shift+10, Latin 'Ë' on Shift+50 → accepted, Shift+50 dropped.
        var iso = KeyTable.pcRussian.keyToChar
        iso[KeyStroke(10, shift: true)] = "Ё"
        iso[KeyStroke(50, shift: true)] = "Ë"
        let isoTable = KeyTableBuilder.sanitized(iso, layout: .russian)
        assertEqual(isoTable?.charToKey["Ё"], KeyStroke(10, shift: true))
        assertEqual(isoTable?.keyToChar[KeyStroke(50, shift: true)], nil)
        var raw = KeyTable.pcRussian.keyToChar
        raw[KeyStroke(12)] = "Q"   // Latin letter on a Cyrillic layout → keeps 'й'
        assertEqual(KeyTableBuilder.sanitized(raw, layout: .russian)?.keyToChar[KeyStroke(12)], "й")
        raw[KeyStroke(13)] = "й"   // two letter keys give 'й' → rejected
        raw[KeyStroke(12)] = "й"
        assert(KeyTableBuilder.sanitized(raw, layout: .russian) == nil, "letter collision rejects the table")
    }
}
```

- [ ] **Step 2: Run** `swift build -c release --product TestRunner` → Expected: `cannot find 'KeyTableBuilder'`.

- [ ] **Step 3: Implement `Sources/Core/KeyTableBuilder.swift`**

```swift
import Carbon
import Foundation
import Utils

public enum KeyTableBuilder {
    /// Reads the none/Shift layers of the main block. Dead keys (non-zero dead-key
    /// state), control characters and whitespace are skipped.
    public static func rawTable(uchr: Data, keyboardType: UInt32) -> [KeyStroke: Character] {
        var map: [KeyStroke: Character] = [:]
        uchr.withUnsafeBytes { pointer in
            guard let base = pointer.baseAddress else { return }
            let layout = base.assumingMemoryBound(to: UCKeyboardLayout.self)
            for code in KeyTable.mainBlockKeyCodes {
                for shift in [false, true] {
                    var deadKeyState: UInt32 = 0
                    var characters = [UniChar](repeating: 0, count: 4)
                    var length = 0
                    let status = UCKeyTranslate(
                        layout, code, UInt16(kUCKeyActionDown),
                        shift ? UInt32(shiftKey >> 8) & 0xFF : 0,
                        keyboardType, 0, &deadKeyState, characters.count, &length, &characters
                    )
                    guard status == noErr, deadKeyState == 0, length > 0,
                          let character = String(utf16CodeUnits: characters, count: length).first,
                          !character.isWhitespace,
                          !(character.unicodeScalars.first.map { $0.value < 0x20 || $0.value == 0x7F } ?? true)
                    else { continue }
                    map[KeyStroke(code, shift: shift)] = character
                }
            }
        }
        return map
    }

    /// System output on top of `.pc`, key by key. A letter outside the layout's script
    /// keeps `.pc`'s output (RussianWin Shift+` is a Latin 'Ë'); two letter keys giving
    /// the same letter reject the table.
    public static func sanitized(_ raw: [KeyStroke: Character], layout: Layout) -> KeyTable? {
        let pc = KeyboardTables.pc.primary(for: layout).keyToChar
        var merged = pc
        let systemCharacters = Set(raw.values)
        for (stroke, character) in raw {
            if character.isLetter && !layout.ownsLetter(character) {
                // Keep .pc's character only if the system does not already put it elsewhere
                // (RussianWin on ISO: 'Ё' on key 10, Latin 'Ë' on Shift+50).
                if let fallback = pc[stroke], systemCharacters.contains(fallback) {
                    merged[stroke] = nil
                }
                continue
            }
            merged[stroke] = character
        }
        // A .pc letter the system does not produce on its key (dead key) must not
        // duplicate a letter the system puts elsewhere.
        for (stroke, character) in pc where raw[stroke] == nil && character.isLetter && systemCharacters.contains(character) {
            merged[stroke] = nil
        }
        var seenLetters = Set<Character>()
        for character in merged.values where character.isLetter {
            if !seenLetters.insert(character).inserted { return nil }
        }
        return KeyTable(keyToChar: merged)
    }

    public static func table(for source: TISInputSource, layout: Layout, keyboardType: UInt32) -> KeyTable? {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        return sanitized(rawTable(uchr: data, keyboardType: keyboardType), layout: layout)
    }

    public static func installedTable(sourceID: String, layout: Layout) -> KeyTable? {
        let filter = [kTISPropertyInputSourceID as String: sourceID] as CFDictionary
        guard let sources = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource],
              let source = sources.first else { return nil }
        return table(for: source, layout: layout, keyboardType: UInt32(LMGetKbdType()))
    }
}

extension Layout {
    /// Whether `character` is a letter of this layout's script.
    func ownsLetter(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first else { return false }
        switch self {
        case .english: return scalar.isASCII
        case .russian, .ukrainian: return (0x0400...0x04FF).contains(scalar.value)
        }
    }
}
```

Note: mac Ukrainian has `ʼ` (U+02BC, a letter modifier; `isLetter` true, outside Cyrillic range) on `\` of Ukrainian-PC → it keeps `.pc`'s output for that key (none) → key has no character; acceptable (apostrophe handling is unchanged).

- [ ] **Step 4: Run** `swift run -c release TestRunner 2>&1 | grep -E "FAIL|SKIP|Results"` → Expected: 0 failed. A failure in "agree with .pc" means `.pc` is wrong for that key on real layouts: report it, do not loosen the test.

- [ ] **Step 5: Commit** `git commit -m "feat(layout): build key tables from installed layouts with a sanity overlay"`

---

### Task 3: `InputSourceManager` — per-source tables and last-used source

**Files:**
- Modify: `Sources/Core/InputSourceManager.swift`
- Test: manual/log only (TIS state is process-global; covered by Task 5 manual run). Keep the pure part testable: `KeyboardTables.resolve(...)` below is unit-tested.

**Interfaces — Produces:**
- `InputSourceManager.keyboardTables(overrides: [Layout: String] = [:]) -> KeyboardTables`
- `static func KeyboardTables.resolve(layoutSources: [Layout: [String]], tablesBySource: [String: KeyTable], firstChoice: [Layout: String]) -> KeyboardTables` (in `KeyTables.swift`)

- [ ] **Step 1: Failing test** (append to `runKeyTableTests()`):

```swift
    runSuite("KeyTables: resolve orders candidates by first choice") {
        let legacy = KeyTable.pcUkrainianLegacy
        let resolved = KeyboardTables.resolve(
            layoutSources: [.ukrainian: ["uk.std", "uk.legacy"], .english: ["us"]],
            tablesBySource: ["uk.std": .pcUkrainian, "uk.legacy": legacy, "us": .pcEnglish],
            firstChoice: [.ukrainian: "uk.legacy"]
        )
        assertEqual(resolved.candidates(for: .ukrainian), [legacy, .pcUkrainian])
        assertEqual(resolved.candidates(for: .russian), [.pcRussian], "missing layout → .pc")
        let dup = KeyboardTables.resolve(
            layoutSources: [.english: ["us", "au"]],
            tablesBySource: ["us": .pcEnglish, "au": .pcEnglish], firstChoice: [:]
        )
        assertEqual(dup.candidates(for: .english).count, 1, "equal tables are deduplicated")
    }
```

- [ ] **Step 2:** build → Expected: `type 'KeyboardTables' has no member 'resolve'`.

- [ ] **Step 3: Implement `resolve`** in `KeyTables.swift`:

```swift
extension KeyboardTables {
    /// Candidates per layout: `firstChoice` source first, then the other sources in
    /// discovery order; sources without a table are skipped, equal tables deduplicated;
    /// a layout with nothing left falls back to `.pc`.
    public static func resolve(
        layoutSources: [Layout: [String]],
        tablesBySource: [String: KeyTable],
        firstChoice: [Layout: String]
    ) -> KeyboardTables {
        var result: [Layout: [KeyTable]] = [:]
        for (layout, ids) in layoutSources {
            var ordered = ids
            if let first = firstChoice[layout], let index = ordered.firstIndex(of: first) {
                ordered.remove(at: index)
                ordered.insert(first, at: 0)
            }
            var tables: [KeyTable] = []
            for id in ordered {
                if let table = tablesBySource[id], !tables.contains(table) { tables.append(table) }
            }
            if !tables.isEmpty { result[layout] = tables }
        }
        return KeyboardTables(result)
    }
}
```

- [ ] **Step 4: Rework `InputSourceManager`**
  - `State`: replace `ukrainianVariants` with `sources: [String: TISInputSource]`, `layoutSources: [Layout: [String]]` (discovery order), `tablesBySource: [String: KeyTable]`, `lastUsedSourceID: [Layout: String]`. Keep `preferredSources`/`sourceIDs` only if still read elsewhere (grep); otherwise remove.
  - `refreshInstalledSources()`: for each keyboard-layout source matched to a `Layout`, record it; build `KeyTableBuilder.table(for:layout:keyboardType: UInt32(LMGetKbdType()))` unless `sourceID.hasSuffix("Russian-Phonetic")`. Whenever the builder returns nil or the source is excluded, store `KeyboardTables.pc.primary(for: layout)` for that source ID (spec: such a source falls back to `.pc`, it is not skipped) and log `SwitchFixLog.source.info("key table unavailable for \(sourceID), using built-in")` once per ID (`loggedFallbacks: Set<String>` in State). Build all tables **outside** the lock, then assign `sources`, `layoutSources`, `tablesBySource` and the pruned `lastUsedSourceID` (entries whose source disappeared removed; seeded from the current source ID if its layout has no entry) in **one** `withLock`.
  - `refreshCurrentInputSource()`: after resolving, if `state.sources[sourceID] != nil` set `lastUsedSourceID[layout] = sourceID`.
  - `switchTo(_ layout:)`: target source = `lastUsedSourceID[layout]` if present in `sources`, else first of `layoutSources[layout]`.
  - `keyboardTables(overrides:)`: `KeyboardTables.resolve(layoutSources:tablesBySource:firstChoice: lastUsedSourceID.merging(overrides) { $1 })` under the lock.
  - Keep `currentUkrainianVariant`, `preferredUkrainianVariant`, `ukrainianVariant(forInputSourceID:)` and their helpers (`detectUkrainianVariant`, `translatedCharacter`, `sKeyCode`, `bKeyCode`, the `ukrainianVariants` map) for now — `AppDelegate` still calls them; Task 4 deletes them. Every commit builds.

- [ ] **Step 5:** `swift build -c release 2>&1 | grep error:` → nothing. `swift run -c release TestRunner 2>&1 | grep -E "FAIL|Results"` → 0 failed.

- [ ] **Step 6: Commit** `git commit -m "feat(layout): per-source key tables and last-used source per layout"`

---

### Task 4: Replace `UkrainianKeyboardVariant` with `KeyboardTables` end to end

**Files:**
- Modify: `Sources/Core/LayoutMapper.swift`, `Sources/Core/LayoutDetector.swift`, `Sources/Core/InputEngine.swift`, `Sources/SwitchFixApp/AppDelegate.swift`, `Sources/TestRunner/main.swift`, `Sources/TestRunner/LayoutEval.swift` (only if it passes variants), `Sources/InputPipelineTestRunner/main.swift`

**Interfaces — Consumes:** Tasks 1–3. **Produces:**
- `LayoutDetector.keyboardTables: KeyboardTables` (default `.pc`)
- `InputEngine.updateDetectionConfiguration(allowedLayouts: Set<Layout>, keyboardTables: KeyboardTables = .pc, thresholds: DetectionThresholds = .default)`
- `InputEngine.handleLayoutChange(from: Layout, to: Layout, context: InputContextSnapshot, keyboardTables: KeyboardTables)`

- [ ] **Step 1: Migrate tests first (they define the target API)**
  - `TestRunner/main.swift` suite `"LayoutMapper: Ukrainian variants"` (lines ~74–108): delete it (covered by `"KeyTables: legacy Ukrainian candidate"`).
  - Line ~283 `detector.ukrainianToVariant = .legacy` → `detector.keyboardTables = .pc.with(.ukrainian, [.pcUkrainianLegacy, .pcUkrainian])`.
  - Lines ~339, ~379–380, ~542, ~578 (`ukrainianFromVariant = .legacy`, and `ukrainianToVariant = .standard`) → the same single line `detector.keyboardTables = .pc.with(.ukrainian, [.pcUkrainianLegacy, .pcUkrainian])`.
  - `InputPipelineTestRunner/main.swift` ~904 and ~969: replace the two variant arguments with nothing (default `.pc`), e.g. `engine.updateDetectionConfiguration(allowedLayouts: [.english, .russian])`.
  - Add the automatic-path acceptance test after `"learning: forced hotkey target follows the last Cyrillic layout"`:

```swift
run("key tables: hotkey converts a shifted digit-row symbol through the key") {
    var harness = LearningHarness()
    // RussianWin: Shift+2 is '"'; US: '@'. `.pc` has no key for '"' on Russian.
    let russianWin = KeyTable.pcRussian.replacing(KeyStroke(19, shift: true), with: "\"")
    harness.engine.updateDetectionConfiguration(
        allowedLayouts: [.english, .russian],
        keyboardTables: KeyboardTables.pc.with(.russian, [russianWin])
    )
    let russian = harness.store.replaceContext(
        frontmostPID: 100, appAllowed: true, layout: .russian,
        inputSourceID: "com.test.russian", secureFocus: .notSecure
    )
    harness.engine.updateContext(russian)
    harness.type("\"ьфшд", boundary: nil)
    harness.send(.hotkey)
    check(waitUntil { harness.emitted.count == 1 }, "hotkey converts")
    check(harness.emitted.last?.correctedText == "@mail", "got \(harness.emitted.last?.correctedText ?? "nil")")
}

run("key tables: .pc keeps today's result for the same input") {
    var harness = LearningHarness()
    let russian = harness.store.replaceContext(
        frontmostPID: 100, appAllowed: true, layout: .russian,
        inputSourceID: "com.test.russian", secureFocus: .notSecure
    )
    harness.engine.updateContext(russian)
    harness.type("\"ьфшд", boundary: nil)
    harness.send(.hotkey)
    check(waitUntil { harness.emitted.count == 1 }, "hotkey converts")
    check(harness.emitted.last?.correctedText == "\"mail", "got \(harness.emitted.last?.correctedText ?? "nil")")
}
```

- [ ] **Step 2:** build → Expected: errors `value of type 'LayoutDetector' has no member 'keyboardTables'`, extra/missing arguments.

- [ ] **Step 3: `LayoutMapper`** — delete `UkrainianKeyboardVariant`, `ruToUk*`, `ukLegacyToRu`, `ukStandardToRu`, `mappingTable`, and all `ukrainianFromVariant:ukrainianToVariant:` overloads. Keep:
  - `convert(_:from:to:)` → `convert(text, from: from, to: to, tables: .pc)`
  - `convertToAlternatives(_:from:)` → `convertToAlternatives(text, from: from, tables: .pc)`
  - Give the `tables:` parameters of the Task 1 functions a default `= .pc` and delete the now-duplicate no-table overloads if the compiler reports ambiguity.
  - `canBeTyped` unchanged in meaning: `ruToEn` / `ukStandardToEn` / `ukLegacyToEn` become private statics built from `PCLayoutData` (`buildReverse(PCLayoutData.enToRu)` …), `.english` uses `PCLayoutData.enToRu`.

- [ ] **Step 4: `LayoutDetector`**
  - Replace `ukrainianFromVariant` / `ukrainianToVariant` with `public var keyboardTables: KeyboardTables = .pc`.
  - In `checkLanguageModels`, replace the `conversions` construction (the `LayoutMapper.convert(... ukrainianFromVariant ...)` call and the `if sourceLayout == .ukrainian && target == .english { fallback }` block) with:

```swift
            let conversions = LayoutMapper.convertCandidates(word, from: sourceLayout, to: target, tables: keyboardTables)
```
  Keep the comment about "first one that clears its threshold wins" (now: first candidate table).
  - `finishLexiconCorrection`: `LayoutMapper.convert(word, from: sourceLayout, to: target, tables: keyboardTables)`.

- [ ] **Step 5: `InputEngine`**
  - `DetectionConfiguration`: replace the two variant fields with `var keyboardTables: KeyboardTables = .pc`.
  - `updateDetectionConfiguration(allowedLayouts:keyboardTables:thresholds:)` stores it.
  - Where the detector is configured (~369): `self.detector.keyboardTables = configuration.keyboardTables`.
  - Force path (~388) and `selectionConversion` (~660): `LayoutMapper.convertToAlternatives(…, from: …, tables: configuration.keyboardTables)`.
  - `handleLayoutChange(from:to:context:keyboardTables:)`: both `LayoutMapper.convert` calls use `tables: keyboardTables`.

- [ ] **Step 6: `AppDelegate`**
  - `updateDetectionConfiguration(allowedLayouts:)`:

```swift
    private func updateDetectionConfiguration(allowedLayouts: Set<Layout>) {
        inputEngine?.updateDetectionConfiguration(
            allowedLayouts: allowedLayouts,
            keyboardTables: inputSourceManager.keyboardTables(),
            thresholds: .forSensitivity(PreferencesManager.shared.detectionSensitivity)
        )
    }
```
  - `selectedInputSourceChanged`: delete `fromVariant`/`toVariant`; build overrides without a
    dictionary literal (a literal with duplicate keys traps when `oldLayout == newLayout`,
    e.g. RussianWin → Russian):

```swift
        var overrides = [oldLayout: oldSourceID]
        overrides[newLayout] = newSourceID
        let tables = inputSourceManager.keyboardTables(overrides: overrides)
```
    and pass `keyboardTables: tables` to `handleLayoutChange`.
  - Next to the existing `kTISNotifySelectedKeyboardInputSourceChanged` observer (~171) add one for `kTISNotifyEnabledKeyboardInputSourcesChanged`:

```swift
    @objc private func enabledInputSourcesChanged() {
        inputSourceManager.refreshInstalledSources()
        inputSourceManager.refreshCurrentInputSource()
        keyboardMonitor?.refreshInputTranslations()
        updateDetectionConfiguration(allowedLayouts: readyLayouts)
    }
```
  - Delete the variant helpers kept in Task 3 from `InputSourceManager`.

- [ ] **Step 7: Run everything**

```bash
swift build -c release 2>&1 | grep -E "error|warning: .*deprecated" ; \
swift run -c release TestRunner 2>&1 | grep -E "FAIL|Results" ; \
swift run -c release InputPipelineTestRunner 2>&1 | tail -2 ; \
grep -rn "UkrainianKeyboardVariant\|ukrainianFromVariant\|ukrainianToVariant" Sources
```
Expected: no errors; `0 failed` twice; grep prints nothing. Compare the LayoutEval table in TestRunner output with the pre-change run (Task 1 Step 0): `swift run -c release TestRunner --layout-eval-only | diff .build/eval-before.txt -` and `swift run -c release TestRunner --threshold-sweep | diff .build/sweep-before.txt -` must both print nothing.

- [ ] **Step 8: Commit** `git commit -m "refactor(layout): replace UkrainianKeyboardVariant with key tables from installed layouts"`

---

### Task 5: Docs, app build, manual verification

**Files:** `CLAUDE.md`, `docs/tasks/2026-09-29-key-tables-from-installed-keyboard-layouts.md`

- [ ] **Step 1: CLAUDE.md** — in the input-pipeline item 4 replace "`LayoutMapper`" mention with: "`LayoutMapper` converts through the physical key using `KeyboardTables` (`KeyTables.swift`): the app builds them from the installed layouts (`KeyTableBuilder`, sanitized on top of `KeyboardTables.pc`, the static PC tables tests and LayoutEval use); `InputSourceManager` tracks the last-used source per layout." Remove any mention of Ukrainian variants.
- [ ] **Step 2:** `./scripts/build-app.sh` → Expected: `dist/SwitchFix.app` built. Then `./install.sh`.
- [ ] **Step 3: Manual (user, RussianWin + Australian):** scenario A of `docs/testing/ngram-lexicon-manual-test.md`; in Russian layout type `"ьфшд` and press the hotkey → `@mail`; select `гыук"ьфшдюсщь` + hotkey → `user@mail.com`; scenario G. Record with `rtp verify <id> --record … --out …`.
- [ ] **Step 4: Debt** — the spec's out-of-scope items are already in the task's `## Debt`; add: `rtp debt <id> --add "Автодетекция перебирает все таблицы исходной раскладки (US+Colemak/Dvorak): первая прошедшая порог побеждает — не измерено LayoutEval"`.
- [ ] **Step 5: Commit** `git commit -m "docs: key tables from installed layouts"`
