import Carbon
import Core

func runKeyTableTests() {
    runSuite("KeyTables: .pc reproduces the static tables") {
        // Expected strings were produced by the pre-key-table LayoutMapper (static
        // character maps, commit 126f5f3) — the frozen contract of `.pc`.
        let samples = [
            "qwertyuiop[]asdfghjkl;'zxcvbnm,./`QWERTYUIOP{}ASDFGHJKL:\"ZXCVBNM<>?~",
            "йцукенгшщзхъфывапролджэячсмитьбю.ёЙЦУКЕНГШЩЗХЪФЫВАПРОЛДЖЭЯЧСМИТЬБЮ,Ё",
            "йцукенгшщзхїфівапролджєячсмитьбю.ґЙЦУКЕНГШЩЗХЇФІВАПРОЛДЖЄЯЧСМИТЬБЮ,Ґ",
            "hello, мир! 123 @#$ user@mail.com ghbdtn иууьи",
        ]
        let expected: [(Int, Layout, Layout, String)] = [
        (0, .english, .ukrainian, "йцукенгшщзхїфівапролджєячсмитьбю.ґЙЦУКЕНГШЩЗХЇФІВАПРОЛДЖЄЯЧСМИТЬБЮ,Ґ"),
        (0, .english, .russian, "йцукенгшщзхъфывапролджэячсмитьбю.ёЙЦУКЕНГШЩЗХЪФЫВАПРОЛДЖЭЯЧСМИТЬБЮ,Ё"),
        (0, .ukrainian, .english, "qwertyuiop[]asdfghjkl;'zxcvbnm?//`QWERTYUIOP{}ASDFGHJKL:\"ZXCVBNM<>?~"),
        (0, .ukrainian, .russian, "qwertyuiop[]asdfghjkl;'zxcvbnm,./`QWERTYUIOP{}ASDFGHJKL:\"ZXCVBNM<>?~"),
        (0, .russian, .english, "qwertyuiop[]asdfghjkl;'zxcvbnm?//`QWERTYUIOP{}ASDFGHJKL:\"ZXCVBNM<>?~"),
        (0, .russian, .ukrainian, "qwertyuiop[]asdfghjkl;'zxcvbnm,./`QWERTYUIOP{}ASDFGHJKL:\"ZXCVBNM<>?~"),
        (1, .english, .ukrainian, "йцукенгшщзхъфывапролджэячсмитьбююёЙЦУКЕНГШЩЗХЪФЫВАПРОЛДЖЭЯЧСМИТЬБЮбЁ"),
        (1, .english, .russian, "йцукенгшщзхъфывапролджэячсмитьбююёЙЦУКЕНГШЩЗХЪФЫВАПРОЛДЖЭЯЧСМИТЬБЮбЁ"),
        (1, .ukrainian, .english, "qwertyuiop[ъaыdfghjkl;эzxcvbnm,./ёQWERTYUIOP{ЪAЫDFGHJKL:ЭZXCVBNM<>?Ё"),
        (1, .ukrainian, .russian, "йцукенгшщзхъфывапролджэячсмитьбю.ёЙЦУКЕНГШЩЗХЪФЫВАПРОЛДЖЭЯЧСМИТЬБЮ,Ё"),
        (1, .russian, .english, "qwertyuiop[]asdfghjkl;'zxcvbnm,./`QWERTYUIOP{}ASDFGHJKL:\"ZXCVBNM<>?~"),
        (1, .russian, .ukrainian, "йцукенгшщзхїфівапролджєячсмитьбю.ґЙЦУКЕНГШЩЗХЇФІВАПРОЛДЖЄЯЧСМИТЬБЮ,Ґ"),
        (2, .english, .ukrainian, "йцукенгшщзхїфівапролджєячсмитьбююґЙЦУКЕНГШЩЗХЇФІВАПРОЛДЖЄЯЧСМИТЬБЮбҐ"),
        (2, .english, .russian, "йцукенгшщзхїфівапролджєячсмитьбююґЙЦУКЕНГШЩЗХЇФІВАПРОЛДЖЄЯЧСМИТЬБЮбҐ"),
        (2, .ukrainian, .english, "qwertyuiop[]asdfghjkl;'zxcvbnm,./`QWERTYUIOP{}ASDFGHJKL:\"ZXCVBNM<>?~"),
        (2, .ukrainian, .russian, "йцукенгшщзхъфывапролджэячсмитьбю.ёЙЦУКЕНГШЩЗХЪФЫВАПРОЛДЖЭЯЧСМИТЬБЮ,Ё"),
        (2, .russian, .english, "qwertyuiop[їaіdfghjkl;єzxcvbnm,./ґQWERTYUIOP{ЇAІDFGHJKL:ЄZXCVBNM<>?Ґ"),
        (2, .russian, .ukrainian, "йцукенгшщзхїфівапролджєячсмитьбю.ґЙЦУКЕНГШЩЗХЇФІВАПРОЛДЖЄЯЧСМИТЬБЮ,Ґ"),
        (3, .english, .ukrainian, "руддщб мир! 123 @#$ гіук@ьфшдюсщь привет иууьи"),
        (3, .english, .russian, "руддщб мир! 123 @#$ гыук@ьфшдюсщь привет иууьи"),
        (3, .ukrainian, .english, "hello? vbh! 123 @#$ user@mail/com ghbdtn beemb"),
        (3, .ukrainian, .russian, "hello, мир! 123 @#$ user@mail.com ghbdtn иууьи"),
        (3, .russian, .english, "hello? vbh! 123 @#$ user@mail/com ghbdtn beemb"),
        (3, .russian, .ukrainian, "hello, мир! 123 @#$ user@mail.com ghbdtn иууьи"),
        ]
        for (index, from, to, result) in expected {
            assertEqual(LayoutMapper.convert(samples[index], from: from, to: to, tables: .pc), result, "\(from)→\(to) #\(index)")
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

    runSuite("KeyTables: resolve orders candidates by first choice") {
        let legacy = KeyTable.pcUkrainianLegacy
        let resolved = KeyboardTables.resolve(
            layoutSources: [.ukrainian: ["uk.std", "uk.legacy"], .english: ["us"]],
            tablesBySource: ["uk.std": .pcUkrainian, "uk.legacy": legacy, "us": .pcEnglish],
            firstChoice: [.ukrainian: "uk.legacy"]
        )
        assertEqual(resolved.candidates(for: .ukrainian), [legacy, .pcUkrainian])
        // Only a standard Ukrainian source enabled: the legacy (и/і swapped) variant stays a
        // trailing candidate, as the detector always tried it before key tables.
        let standardOnly = KeyboardTables.resolve(
            layoutSources: [.ukrainian: ["uk.std"]],
            tablesBySource: ["uk.std": KeyTable.pcUkrainian.replacing(KeyStroke(18, shift: true), with: "!")],
            firstChoice: [:]
        )
        assertEqual(standardOnly.candidates(for: .ukrainian).last, legacy, "legacy fallback kept")
        assertEqual(resolved.candidates(for: .russian), [.pcRussian], "missing layout → .pc")
        let dup = KeyboardTables.resolve(
            layoutSources: [.english: ["us", "au"]],
            tablesBySource: ["us": .pcEnglish, "au": .pcEnglish], firstChoice: [:]
        )
        assertEqual(dup.candidates(for: .english).count, 1, "equal tables are deduplicated")
    }

    runSystemKeyTableTests()

    runSuite("KeyTables: ModelTrainer mirror matches .pc letters") {
        // Copied from Sources/ModelTrainer/main.swift (englishKeys / cyrillicKeys) — keep in sync.
        let english = "qwertyuiop[]asdfghjkl;'zxcvbnm,.`"
        assertEqual(LayoutMapper.convert(english, from: .english, to: .russian, tables: .pc),
                    "йцукенгшщзхъфывапролджэячсмитьбюё")
        assertEqual(LayoutMapper.convert(english, from: .english, to: .ukrainian, tables: .pc),
                    "йцукенгшщзхїфівапролджєячсмитьбюґ")
    }
}

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

    runSuite("KeyTables: keys 10 and 50 on ANSI and ISO keyboards") {
        let types: [(String, UInt32?)] = [
            ("ANSI", KeyTableBuilder.keyboardType(physicalLayout: PhysicalKeyboardLayoutType(kKeyboardANSI))),
            ("ISO", KeyTableBuilder.keyboardType(physicalLayout: PhysicalKeyboardLayoutType(kKeyboardISO))),
        ]
        let pairs: [(String, Layout, KeyTable)] = [
            ("US", .english, .pcEnglish), ("RussianWin", .russian, .pcRussian),
            ("Ukrainian-PC", .ukrainian, .pcUkrainian),
        ]
        for (name, type) in types {
            guard let type else {
                print("  SKIP: no \(name) keyboard type")
                continue
            }
            guard let us = KeyTableBuilder.installedTable(sourceID: "com.apple.keylayout.US", layout: .english, keyboardType: type) else {
                print("  SKIP: US not installed on this machine")
                return
            }
            for (id, layout, pc) in pairs {
                guard let system = KeyTableBuilder.installedTable(
                    sourceID: "com.apple.keylayout.\(id)", layout: layout, keyboardType: type
                ) else {
                    print("  SKIP: \(id) not installed on this machine")
                    continue
                }
                for (stroke, character) in pc.keyToChar where stroke.keyCode != 10 {
                    // ISO keyboards swap the § and ` keys; on ANSI key 50 is the ` key.
                    if name == "ISO" && stroke.keyCode == 50 { continue }
                    // RussianWin Shift+` is a Latin 'Ë' in the system data: dropped, 'Ё' is elsewhere.
                    if id == "RussianWin" && stroke == KeyStroke(50, shift: true) {
                        assertEqual(system.keyToChar[stroke], nil, "\(name) \(id): Latin 'Ë' dropped")
                        assert(system.charToKey["Ё"].map { $0 != stroke } ?? false, "\(name) \(id): 'Ё' on another key")
                        continue
                    }
                    assertEqual(system.keyToChar[stroke], character, "\(name) \(id) \(stroke)")
                }
                // Whichever key carries them, the letters of the ` key (ё, ґ) round-trip.
                for shift in [false, true] {
                    guard let letter = pc.keyToChar[KeyStroke(50, shift: shift)], letter.isLetter else { continue }
                    let typed = LayoutMapper.convert(String(letter), from: system, to: us)
                    assertEqual(LayoutMapper.convert(typed, from: us, to: system), String(letter), "\(name) \(id) via '\(typed)'")
                }
            }
        }
    }

    runSuite("KeyTables: dead keys are skipped") {
        guard let raw = KeyTableBuilder.installedRawTable(sourceID: "com.apple.keylayout.USInternational-PC") else {
            print("  SKIP: USInternational-PC not installed on this machine")
            return
        }
        // US International: ' " ` ~ ^ start a composition instead of typing.
        let deadKeys = [KeyStroke(39), KeyStroke(39, shift: true), KeyStroke(50), KeyStroke(50, shift: true), KeyStroke(22, shift: true)]
        for stroke in deadKeys {
            assertEqual(raw[stroke], nil, "dead key \(stroke)")
        }
        assertEqual(raw[KeyStroke(0)], "a")
        assertEqual(raw[KeyStroke(0, shift: true)], "A")
        // A skipped key keeps .pc's character in the table.
        let table = KeyTableBuilder.sanitized(raw, layout: .english)
        assertEqual(table?.keyToChar[KeyStroke(39)], "'")
        assertEqual(table?.keyToChar[KeyStroke(0)], "a")
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
        // Ukrainian-PC is the standard variant; mac "Ukrainian" is the legacy one (и/і swapped).
        for (id, keys) in [("Ukrainian-PC", "ghbdsn"), ("Ukrainian", "ghsdbn")] {
            if let uk = table(id, .ukrainian) {
                assertEqual(LayoutMapper.convert(keys, from: us, to: uk), "привіт", id)
                assertEqual(LayoutMapper.convert("привіт", from: uk, to: us), keys, id)
            }
        }
        if let au = table("Australian", .english) { assertEqual(au, us, "Australian ≡ US") }
    }

    runSuite("KeyTables: sanity overlay") {
        // RussianWin Shift+` is a Latin 'Ë' in the system data. Which key carries 'Ё'
        // depends on the keyboard type (ANSI vs ISO), so only assert what holds on both:
        // 'Ë' never appears, 'Ё' round-trips through its key.
        if let win = table("RussianWin", .russian), let us = table("US", .english) {
            assert(!win.keyToChar.values.contains("Ë"), "Latin 'Ë' is filtered out")
            let typed = LayoutMapper.convert("Ё", from: win, to: us)
            assertEqual(LayoutMapper.convert(typed, from: us, to: win), "Ё", "via '\(typed)'")
        }
        // ISO variant: 'Ё' on Shift+10, Latin 'Ë' on Shift+50 → accepted, Shift+50 dropped.
        var iso = KeyTable.pcRussian.keyToChar
        iso[KeyStroke(10, shift: true)] = "Ё"
        iso[KeyStroke(50, shift: true)] = "Ë"
        let isoTable = KeyTableBuilder.sanitized(iso, layout: .russian)
        assertEqual(isoTable?.charToKey["Ё"], KeyStroke(10, shift: true))
        assertEqual(isoTable?.keyToChar[KeyStroke(50, shift: true)], nil)
        // RussianWin puts 'ё' on both ` (50) and the ISO § key (10): a duplicate on key 10
        // is normal and must not reject the table; the non-ISO key wins.
        var withISO = KeyTable.pcRussian.keyToChar
        withISO[KeyStroke(10)] = "ё"
        let withISOTable = KeyTableBuilder.sanitized(withISO, layout: .russian)
        assertEqual(withISOTable?.charToKey["ё"], KeyStroke(50))
        var raw = KeyTable.pcRussian.keyToChar
        raw[KeyStroke(12)] = "Q"   // Latin letter on a Cyrillic layout → keeps 'й'
        assertEqual(KeyTableBuilder.sanitized(raw, layout: .russian)?.keyToChar[KeyStroke(12)], "й")
        raw[KeyStroke(13)] = "й"   // two letter keys give 'й' → rejected
        raw[KeyStroke(12)] = "й"
        assert(KeyTableBuilder.sanitized(raw, layout: .russian) == nil, "letter collision rejects the table")
    }
}
