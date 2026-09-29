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
