import Carbon
import Foundation

/// Builds `KeyTable`s from installed keyboard layouts (`uchr` data via `UCKeyTranslate`).
public enum KeyTableBuilder {
    private static let isoSectionKeyCode: UInt16 = 10

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
                          let scalar = character.unicodeScalars.first,
                          scalar.value >= 0x20, scalar.value != 0x7F
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
        for (stroke, character) in pc
        where raw[stroke] == nil && character.isLetter && systemCharacters.contains(character) {
            merged[stroke] = nil
        }
        // The ISO section key (10) often repeats another key (RussianWin: 'ё' on 10 and 50),
        // so it is left out of the collision check; `charToKey` prefers the other key.
        var seenLetters = Set<Character>()
        for (stroke, character) in merged where character.isLetter && stroke.keyCode != isoSectionKeyCode {
            if !seenLetters.insert(character).inserted { return nil }
        }
        return KeyTable(keyToChar: merged)
    }

    public static func table(for source: TISInputSource, layout: Layout, keyboardType: UInt32) -> KeyTable? {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        return sanitized(rawTable(uchr: data, keyboardType: keyboardType), layout: layout)
    }

    /// Table of an installed (not necessarily enabled) layout; for tests and diagnostics.
    /// - Parameter keyboardType: the physical keyboard type; nil: the one last typed on.
    public static func installedTable(sourceID: String, layout: Layout, keyboardType: UInt32? = nil) -> KeyTable? {
        installedRawTable(sourceID: sourceID, keyboardType: keyboardType).flatMap { sanitized($0, layout: layout) }
    }

    /// `rawTable` of an installed layout; for tests and diagnostics.
    public static func installedRawTable(sourceID: String, keyboardType: UInt32? = nil) -> [KeyStroke: Character]? {
        let filter = [kTISPropertyInputSourceID as String: sourceID] as CFDictionary
        guard let sources = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource],
              let source = sources.first,
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        return rawTable(uchr: data, keyboardType: keyboardType ?? UInt32(LMGetKbdType()))
    }

    /// A keyboard type of the given physical layout (`kKeyboardANSI`, `kKeyboardISO`), for
    /// building tables of a keyboard other than the one attached; nil if none is known.
    public static func keyboardType(physicalLayout: PhysicalKeyboardLayoutType) -> UInt32? {
        // Common USB keyboard types (ANSI 40, ISO 41, JIS 42) first, then any other one.
        let candidates = [UInt32(40), 41, 42] + Array(UInt32(1)...UInt32(255))
        return candidates.first { KBGetLayoutType(Int16($0)) == physicalLayout }
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
