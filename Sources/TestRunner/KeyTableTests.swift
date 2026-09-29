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
