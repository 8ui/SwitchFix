import CoreGraphics

/// A lone press-and-release of a modifier used as the correction hotkey.
/// Stored as `hotkeyKeyCode` = the left-side key code with `hotkeyModifiers` = 0;
/// either side of the modifier triggers it.
public struct TapModifierHotkey {
    /// Left-side key code, as stored in preferences.
    public let keyCode: UInt16
    /// Left and right key codes of the modifier.
    public let keyCodes: Set<UInt16>
    public let flag: CGEventFlags
    public let name: String

    public static let all: [TapModifierHotkey] = [
        TapModifierHotkey(keyCode: 59, keyCodes: [59, 62], flag: .maskControl, name: "Control"),
        TapModifierHotkey(keyCode: 58, keyCodes: [58, 61], flag: .maskAlternate, name: "Option"),
    ]

    /// The tap hotkey selected by a configured (left-side) hotkey key code.
    public static func configured(keyCode: UInt16) -> TapModifierHotkey? {
        all.first { $0.keyCode == keyCode }
    }

    /// The tap hotkey a physical modifier key (either side) belongs to.
    public static func containing(keyCode: UInt16) -> TapModifierHotkey? {
        all.first { $0.keyCodes.contains(keyCode) }
    }
}
