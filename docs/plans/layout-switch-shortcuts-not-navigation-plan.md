# Layout-switch shortcuts are not navigation — implementation plan

> **For agentic workers:** execute task by task (executing-plans). Steps use checkboxes.

**Goal:** the system shortcuts that switch the input source (by default Ctrl+Space "select the previous
input source", Ctrl+Option+Space "select next source") are captured as `.inputSourceKey`, like the Globe
key, instead of `.navigation`; so layout-switch mode keeps the word typed before the switch. The key-down
classification becomes a pure, tested function.

**Architecture:** `KeyboardMonitor.classify` keeps the stateful parts (tap-modifier hotkey, Caps Lock edge,
mouse) and delegates the key-down decision to `public static func classifyKeyDown(keyCode:flags:hotkeys:
inputSourceShortcuts:) -> CapturedInput.Kind?` (nil — a text key; the instance method then resolves the
typed characters as today). The shortcuts come from `com.apple.symbolichotkeys` (`AppleSymbolicHotKeys`
ids 60 and 61), parsed by a pure `static func inputSourceShortcuts(from:)` and stored in a lock next to
the translation table; refreshed together with it (`refreshInputTranslations`: launch, wake, input-source
and app changes).

**Tech stack:** Swift package; `InputPipelineTestRunner`.

**Task:** `docs/tasks/2026-10-02-layout-switch-shortcuts-not-navigation.md`.

## Global constraints

- Order of the key-down decision is unchanged except for the new rule: SwitchFix's own hotkey, then the
  revert hotkey, then Cmd+Z, then **input-source shortcuts (new)**, then modifier/F-key navigation, caret
  keys, Globe, Tab/Esc, Space, Return, Delete, text. A user who bound SwitchFix's hotkey to Ctrl+Space keeps it.
- A shortcut matches on key code and the Cmd/Ctrl/Option/Shift subset of the flags (as `isMatchingHotkey`).
- Only enabled entries count. A missing domain or entry → the macOS defaults (60: Ctrl+Space, 61:
  Ctrl+Option+Space), both enabled; an entry present with `enabled = 0` is off.
- Nothing is read from defaults on the event-tap callback thread.
- Out of scope (debt): Caps Lock as the input-source switch (a macOS setting, flagsChanged), third-party
  switchers (Karabiner, Punto), shortcuts on non-standard key codes.

---

### Task 1: Pure key-down classification

**Files:** `Sources/Core/KeyboardMonitor.swift` (`classify` ~329-447), tests `Sources/InputPipelineTestRunner/main.swift`.

```swift
public struct InputSourceShortcut: Hashable, Sendable {
    public let keyCode: UInt16
    /// Cmd/Ctrl/Option/Shift subset of `CGEventFlags`.
    public let modifiers: UInt64
    public init(keyCode: UInt16, modifiers: UInt64)
}
extension KeyboardMonitor {
    /// The capture kind of a key-down, or nil for a key that types text.
    public static func classifyKeyDown(keyCode: UInt16, flags: CGEventFlags, hotkeys: HotkeyConfiguration,
                                       inputSourceShortcuts: Set<InputSourceShortcut>) -> CapturedInput.Kind?
}
```

- [ ] Tests first: Globe 179 → `.inputSourceKey`; Ctrl+Space with the default shortcut set →
  `.inputSourceKey`, with an empty set → `.navigation`; Ctrl+Option+Space → `.inputSourceKey`; Cmd+Space →
  `.navigation` (Spotlight, not in the set); plain Space → `.boundary(" ")`; Cmd+Z → `.undo`; Cmd+V, Ctrl+C
  → `.navigation`; arrows → `.navigation`; Return/keypad Enter → `.boundary("\n")`; Delete → `.delete`;
  Tab/Esc → `.focusMayChange`; a letter key → nil; SwitchFix's hotkey configured as Ctrl+Space → `.hotkey`
  (wins over the shortcut).
- [ ] Move the `type == .keyDown` part of `classify` (from the hotkey checks to the Delete key) into
  `classifyKeyDown`; `classify` calls it with `shortcuts.withLock { $0 }` and falls through to the
  text resolution when it returns nil. Add the shortcut rule after Cmd+Z.
- [ ] Commit `refactor(monitor): key-down classification is a pure function`.

### Task 2: Read the system shortcuts

**Files:** `Sources/Core/KeyboardMonitor.swift`, tests `Sources/InputPipelineTestRunner/main.swift`.

```swift
extension KeyboardMonitor {
    public static let defaultInputSourceShortcuts: Set<InputSourceShortcut>   // Ctrl+Space, Ctrl+Option+Space
    /// `AppleSymbolicHotKeys` of `com.apple.symbolichotkeys` (nil: domain missing).
    public static func inputSourceShortcuts(from symbolicHotKeys: [String: Any]?) -> Set<InputSourceShortcut>
}
```

- [ ] Tests: nil → defaults; `["60": ["enabled": 0, ...]]` → only Ctrl+Option+Space; a remapped 60
  (`parameters: [65535, 49, 1048576]`, Cmd+Space) → Cmd+Space + default 61; malformed entries (missing
  `value`, non-numeric parameters, `NSNumber` vs `Int` vs `Bool` for `enabled`) → treated as missing (default).
  Parameters are `[ascii, keyCode, NSEvent modifier flags]`; the modifier bits equal `CGEventFlags` masks
  (Shift 0x20000, Ctrl 0x40000, Option 0x80000, Cmd 0x100000) — keep only those four.
- [ ] `refreshInputTranslations` also reads `UserDefaults(suiteName: "com.apple.symbolichotkeys")?
  .dictionary(forKey: "AppleSymbolicHotKeys")` and stores the parsed set in
  `private let inputSourceShortcuts = OSAllocatedUnfairLock(initialState: KeyboardMonitor.defaultInputSourceShortcuts)`.
  Log the count (no keys) on change.
- [ ] CLAUDE.md, input pipeline item 1: one sentence on input-source shortcuts.
- [ ] Commit `fix(monitor): input-source shortcuts keep the word in layout-switch mode`.

### Task 3: Review

- [ ] Close the debts in `2026-09-30-layout-switch-mode-loses-the-word-when-switching-with-the`
  (Ctrl-Space) and the "classify is private and untested" one; record new debts (Caps Lock switch).
- [ ] Reviewer subagent, CI evidence.
