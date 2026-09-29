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
        // Unshifted beats shifted, then key-list order: a deterministic reverse map.
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
    // EN (QWERTY) → RU (ЙЦУКЕН) — standard macOS Russian layout
    static let enToRu: [Character: Character] = [
        "q": "й", "w": "ц", "e": "у", "r": "к", "t": "е", "y": "н", "u": "г", "i": "ш", "o": "щ", "p": "з",
        "[": "х", "]": "ъ", "a": "ф", "s": "ы", "d": "в", "f": "а", "g": "п", "h": "р", "j": "о", "k": "л",
        "l": "д", ";": "ж", "'": "э", "z": "я", "x": "ч", "c": "с", "v": "м", "b": "и", "n": "т", "m": "ь",
        ",": "б", ".": "ю", "/": ".",
        // Uppercase
        "Q": "Й", "W": "Ц", "E": "У", "R": "К", "T": "Е", "Y": "Н", "U": "Г", "I": "Ш", "O": "Щ", "P": "З",
        "{": "Х", "}": "Ъ", "A": "Ф", "S": "Ы", "D": "В", "F": "А", "G": "П", "H": "Р", "J": "О", "K": "Л",
        "L": "Д", ":": "Ж", "\"": "Э", "Z": "Я", "X": "Ч", "C": "С", "V": "М", "B": "И", "N": "Т", "M": "Ь",
        "<": "Б", ">": "Ю", "?": ",",
        "`": "ё", "~": "Ё",
    ]

    // EN (QWERTY) → UK (Ukrainian) — modern macOS Ukrainian layout
    static let enToUkStandard: [Character: Character] = [
        "q": "й", "w": "ц", "e": "у", "r": "к", "t": "е", "y": "н", "u": "г", "i": "ш", "o": "щ", "p": "з",
        "[": "х", "]": "ї", "a": "ф", "s": "і", "d": "в", "f": "а", "g": "п", "h": "р", "j": "о", "k": "л",
        "l": "д", ";": "ж", "'": "є", "z": "я", "x": "ч", "c": "с", "v": "м", "b": "и", "n": "т", "m": "ь",
        ",": "б", ".": "ю", "/": ".",
        // Uppercase
        "Q": "Й", "W": "Ц", "E": "У", "R": "К", "T": "Е", "Y": "Н", "U": "Г", "I": "Ш", "O": "Щ", "P": "З",
        "{": "Х", "}": "Ї", "A": "Ф", "S": "І", "D": "В", "F": "А", "G": "П", "H": "Р", "J": "О", "K": "Л",
        "L": "Д", ":": "Ж", "\"": "Є", "Z": "Я", "X": "Ч", "C": "С", "V": "М", "B": "И", "N": "Т", "M": "Ь",
        "<": "Б", ">": "Ю", "?": ",",
        "`": "ґ", "~": "Ґ",
    ]

    // EN (QWERTY) → UK (Ukrainian Legacy) — swaps positions of и/і.
    static let enToUkLegacy: [Character: Character] = {
        var map = enToUkStandard
        map["s"] = "и"
        map["b"] = "і"
        map["S"] = "И"
        map["B"] = "І"
        return map
    }()

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
