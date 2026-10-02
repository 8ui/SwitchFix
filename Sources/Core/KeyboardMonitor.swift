import AppKit
import Carbon
import CoreGraphics
import Foundation
import os
import Utils

/// A key with modifiers that switches the input source (System Settings → Keyboard Shortcuts).
public struct InputSourceShortcut: Hashable, Sendable {
    public let keyCode: UInt16
    /// The Cmd/Ctrl/Option/Shift subset of `CGEventFlags` (other bits are dropped).
    public let modifiers: UInt64

    public init(keyCode: UInt16, modifiers: UInt64) {
        self.keyCode = keyCode
        self.modifiers = modifiers & KeyboardMonitor.shortcutModifierMask.rawValue
    }
}

public final class KeyboardMonitor {
    public var onInput: ((CapturedInput) -> Void)?

    private struct TapLifecycle {
        var tap: CFMachPort?
        var source: CFRunLoopSource?
        var isMonitoring = false
        var prefersLayoutTranslation = false
    }

    private struct EventMetadata {
        let sequence: UInt64
        let timestamp: UInt64
        let keyCode: UInt16
        let flagsRawValue: UInt64
        let isAutorepeat: Bool
        let sourcePID: Int32
        let sourceUserData: Int64
        let callbackDurationNanoseconds: UInt64
    }

    private struct TranslationKey: Hashable {
        let keyCode: UInt16
        let shifted: Bool
    }

    private let captureState: CaptureStateStore
    private let lifecycle = OSAllocatedUnfairLock(initialState: TapLifecycle())
    private let translations = OSAllocatedUnfairLock(initialState: [TranslationKey: String]())
    /// System shortcuts that switch the input source, refreshed with the translation table.
    private let systemInputSourceShortcuts = OSAllocatedUnfairLock(
        initialState: KeyboardMonitor.defaultInputSourceShortcuts
    )
    private var diagnosticRing = [EventMetadata?](repeating: nil, count: 256)
    private var diagnosticRingIndex = 0
    // Tap-callback-thread confined: tracks caps lock toggle state for edge detection.
    private var lastAlphaShiftState: Bool?
    // Tap-callback-thread confined: a lone hotkey-modifier press awaiting its release.
    private var controlTapArmed = false
    private var clickTracker = PlainClickTracker()
    private var tapResetCount: UInt64 = 0
    /// Uptime of the last mouse-down the tap delivered: a watchdog compares it with clicks
    /// seen elsewhere to catch a tap that reports enabled but gets no events.
    private let lastMouseDown = OSAllocatedUnfairLock<TimeInterval>(initialState: 0)

    private static let spaceKeyCode: UInt16 = 49
    private static let returnKeyCode: UInt16 = 36
    /// Keypad Enter types U+0003, which would otherwise reach the word buffer as a letter.
    private static let keypadEnterKeyCode: UInt16 = 76
    private static let tabKeyCode: UInt16 = 48
    private static let escapeKeyCode: UInt16 = 53
    private static let deleteKeyCode: UInt16 = 51
    private static let capsLockKeyCode: UInt16 = 57
    private static let zKeyCode: UInt16 = 6
    private static let globeKeyCode: UInt16 = 179

    private static let functionKeyCodes: Set<UInt16> = Set([
        122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111,
        105, 107, 113, 106, 64, 79, 80,
    ])

    private static let leftArrowKeyCode: UInt16 = 123
    private static let rightArrowKeyCode: UInt16 = 124

    /// Left/Right/Home/End: keys that only move the caret in a text field. Up/Down and
    /// Page Up/Down are left out: in a combobox, an address bar or a shell they put a
    /// suggestion or a history entry into the field.
    private static let caretKeyCodes: Set<UInt16> = [leftArrowKeyCode, rightArrowKeyCode, 115, 119]

    /// Arrows, Home/End, Page Up/Down and forward delete: keys that move the caret or edit
    /// around it. `InputStateMachine` uses them to tell caret moves from other shortcuts.
    static let navigationKeyCodes: Set<UInt16> = Set([
        123, 124, 125, 126,
        115, 119, 116, 121,
        117, // forward delete: must not reach the character buffer as U+F728
    ])

    public init(captureState: CaptureStateStore? = nil) {
        if let captureState {
            self.captureState = captureState
        } else {
            let context = InputContextSnapshot(
                epoch: 0,
                frontmostPID: 0,
                appAllowed: false,
                layout: .english,
                inputSourceID: "unknown",
                secureFocus: .unknown
            )
            self.captureState = CaptureStateStore(
                context: context,
                hotkeys: HotkeyConfiguration(
                    hotkeyModifiers: CGEventFlags.maskControl.rawValue | CGEventFlags.maskShift.rawValue
                )
            )
        }
    }

    public var hotkeyKeyCode: UInt16 {
        get { captureState.hotkeyConfiguration().hotkeyKeyCode }
        set {
            let old = captureState.hotkeyConfiguration()
            captureState.updateHotkeys(HotkeyConfiguration(
                hotkeyKeyCode: newValue,
                hotkeyModifiers: old.hotkeyModifiers,
                revertHotkeyKeyCode: old.revertHotkeyKeyCode,
                revertHotkeyModifiers: old.revertHotkeyModifiers
            ))
        }
    }

    public var hotkeyModifiers: UInt64 {
        get { captureState.hotkeyConfiguration().hotkeyModifiers }
        set {
            let old = captureState.hotkeyConfiguration()
            captureState.updateHotkeys(HotkeyConfiguration(
                hotkeyKeyCode: old.hotkeyKeyCode,
                hotkeyModifiers: newValue,
                revertHotkeyKeyCode: old.revertHotkeyKeyCode,
                revertHotkeyModifiers: old.revertHotkeyModifiers
            ))
        }
    }

    public var revertHotkeyKeyCode: UInt16 {
        get { captureState.hotkeyConfiguration().revertHotkeyKeyCode }
        set {
            let old = captureState.hotkeyConfiguration()
            captureState.updateHotkeys(HotkeyConfiguration(
                hotkeyKeyCode: old.hotkeyKeyCode,
                hotkeyModifiers: old.hotkeyModifiers,
                revertHotkeyKeyCode: newValue,
                revertHotkeyModifiers: old.revertHotkeyModifiers
            ))
        }
    }

    public var revertHotkeyModifiers: UInt64 {
        get { captureState.hotkeyConfiguration().revertHotkeyModifiers }
        set {
            let old = captureState.hotkeyConfiguration()
            captureState.updateHotkeys(HotkeyConfiguration(
                hotkeyKeyCode: old.hotkeyKeyCode,
                hotkeyModifiers: old.hotkeyModifiers,
                revertHotkeyKeyCode: old.revertHotkeyKeyCode,
                revertHotkeyModifiers: newValue
            ))
        }
    }

    @discardableResult
    public func start() -> Bool {
        if lifecycle.withLock({ $0.isMonitoring }) {
            return true
        }

        let eventMask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.leftMouseDragged.rawValue) |
            (1 << CGEventType.leftMouseUp.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.otherMouseDown.rawValue)
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let tapResult = createEventTap(eventMask: eventMask, userInfo: userInfo),
              let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tapResult.tap, 0) else {
            let accessibility = Permissions.isAccessibilityGranted()
            let inputMonitoring = Permissions.isInputMonitoringGranted()
            SwitchFixLog.monitor.error(
                "KeyboardMonitor: failed to create event tap (Accessibility: \(accessibility ? "granted" : "missing"), Input Monitoring: \(inputMonitoring ? "granted" : "missing"))"
            )
            return false
        }

        lifecycle.withLock { value in
            value.tap = tapResult.tap
            value.source = source
            value.isMonitoring = true
            value.prefersLayoutTranslation = tapResult.location == .cghidEventTap
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tapResult.tap, enable: true)
        SwitchFixLog.monitor.notice(
            "KeyboardMonitor: event tap active (\(tapResult.location == .cgSessionEventTap ? "session" : "HID"))"
        )
        return true
    }

    public var lastMouseDownUptime: TimeInterval {
        lastMouseDown.withLock { $0 }
    }

    /// The HID fallback tap misses clicks posted at session level (Screen Sharing,
    /// Universal Control), so a missed click proves nothing there.
    public var usesHIDTap: Bool {
        lifecycle.withLock { $0.isMonitoring && $0.prefersLayoutTranslation }
    }

    public var isTapEnabled: Bool {
        guard let tap = lifecycle.withLock({ $0.tap }) else { return false }
        return CGEvent.tapIsEnabled(tap: tap)
    }

    /// Replaces the tap with a new one: after sleep, a screen lock or re-signing a tap may stop
    /// receiving events without any tapDisabled event.
    @discardableResult
    public func restart(reason: String) -> Bool {
        SwitchFixLog.monitor.notice("KeyboardMonitor: recreating event tap (\(reason))")
        stop()
        return start()
    }

    /// Precompute the current layout's key texts away from the event-tap callback (the HID
    /// tap's only source of text; at session level, a check of the event's own text).
    public func refreshInputTranslations() {
        let sources = [
            TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
            TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
        ].compactMap { $0 }
        var table: [TranslationKey: String] = [:]
        for source in sources {
            for keyCode in UInt16(0)..<UInt16(128) {
                for shifted in [false, true] {
                    let key = TranslationKey(keyCode: keyCode, shifted: shifted)
                    if table[key] == nil,
                       let text = Self.translatedCharacter(from: source, keyCode: keyCode, shifted: shifted) {
                        table[key] = text
                    }
                }
            }
        }
        let preparedTable = table
        translations.withLock { $0 = preparedTable }
        refreshInputSourceShortcuts()
    }

    public func stop() {
        let resources = lifecycle.withLock { value -> (CFMachPort?, CFRunLoopSource?) in
            guard value.isMonitoring else { return (nil, nil) }
            value.isMonitoring = false
            value.prefersLayoutTranslation = false
            let resources = (value.tap, value.source)
            value.tap = nil
            value.source = nil
            return resources
        }

        if let tap = resources.0 {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source = resources.1 {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
    }

    private func createEventTap(
        eventMask: CGEventMask,
        userInfo: UnsafeMutableRawPointer
    ) -> (tap: CFMachPort, location: CGEventTapLocation)? {
        for location: CGEventTapLocation in [.cgSessionEventTap, .cghidEventTap] {
            if let tap = CGEvent.tapCreate(
                tap: location,
                place: .headInsertEventTap,
                options: .listenOnly,
                eventsOfInterest: eventMask,
                callback: KeyboardMonitor.eventTapCallback,
                userInfo: userInfo
            ) {
                return (tap, location)
            }
        }
        return nil
    }

    private func handleTapReset(event: CGEvent) {
        tapResetCount &+= 1
        SwitchFixLog.monitor.notice("tap disabled by system, re-enabling (count=\(tapResetCount))")
        let input = captureState.capture(
            timestamp: event.timestamp,
            kind: .tapReset,
            keyCode: 0,
            flagsRawValue: event.flags.rawValue,
            isAutorepeat: false,
            sourcePID: Int32(truncatingIfNeeded: event.getIntegerValueField(.eventSourceUnixProcessID)),
            sourceUserData: event.getIntegerValueField(.eventSourceUserData)
        )
        onInput?(input)
        if let tap = lifecycle.withLock({ $0.tap }) {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    private func handle(type: CGEventType, event: CGEvent, startedAt: UInt64) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            handleTapReset(event: event)
            return
        }
        if type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown {
            let now = ProcessInfo.processInfo.systemUptime
            lastMouseDown.withLock { $0 = now }
        }

        let sourceUserData = event.getIntegerValueField(.eventSourceUserData)
        guard sourceUserData != switchFixEventMarker else { return }

        let keyCode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        guard let kind = classify(type: type, event: event, keyCode: keyCode, flags: flags) else {
            return
        }

        let input = captureState.capture(
            timestamp: event.timestamp,
            kind: kind,
            keyCode: keyCode,
            flagsRawValue: flags.rawValue,
            isAutorepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
            sourcePID: Int32(truncatingIfNeeded: event.getIntegerValueField(.eventSourceUnixProcessID)),
            sourceUserData: sourceUserData
        )
        onInput?(input)
        let duration = DispatchTime.now().uptimeNanoseconds &- startedAt
        diagnosticRing[diagnosticRingIndex] = EventMetadata(
            sequence: input.sequence,
            timestamp: input.timestamp,
            keyCode: input.keyCode,
            flagsRawValue: input.flagsRawValue,
            isAutorepeat: input.isAutorepeat,
            sourcePID: input.sourcePID,
            sourceUserData: input.sourceUserData,
            callbackDurationNanoseconds: duration
        )
        diagnosticRingIndex = (diagnosticRingIndex + 1) % diagnosticRing.count
    }

    private func classify(
        type: CGEventType,
        event: CGEvent,
        keyCode: UInt16,
        flags: CGEventFlags
    ) -> CapturedInput.Kind? {
        let hotkeys = captureState.hotkeyConfiguration()
        // Hotkey key code = left Control (59) or left Option (58): fire on a lone tap of
        // that modifier (either side; press + release with nothing else in between),
        // so <modifier>+<key> combos keep working as usual.
        let tapModifier = TapModifierHotkey.configured(keyCode: hotkeys.hotkeyKeyCode)
        let isTapKey = type == .flagsChanged && tapModifier?.keyCodes.contains(keyCode) == true
        if !isTapKey {
            controlTapArmed = false
        }
        if isTapKey, let tapModifier {
            if flags.contains(tapModifier.flag) {
                let others = CGEventFlags([.maskCommand, .maskControl, .maskAlternate, .maskShift])
                    .subtracting(tapModifier.flag)
                controlTapArmed = flags.intersection(others).isEmpty
                return nil
            }
            let fire = controlTapArmed
            controlTapArmed = false
            return fire ? .hotkey : nil
        }

        if type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown {
            return clickTracker.mouseDown(Self.classifyMouseDown(
                isLeftButton: type == .leftMouseDown,
                flags: flags,
                clickState: event.getIntegerValueField(.mouseEventClickState)
            ))
        }
        if type == .leftMouseDragged {
            clickTracker.dragged()
            return nil
        }
        if type == .leftMouseUp {
            return clickTracker.mouseUp()
        }
        if type == .keyDown {
            clickTracker.dragged()
        }

        if type == .flagsChanged {
            guard keyCode == KeyboardMonitor.capsLockKeyCode,
                  Self.isMatchingHotkey(
                    keyCode: keyCode,
                    flags: flags,
                    configuredKeyCode: hotkeys.revertHotkeyKeyCode,
                    configuredModifiers: hotkeys.revertHotkeyModifiers
                  ) else {
                return nil
            }
            // Caps lock emits flagsChanged on both press and release with the same
            // toggled state; fire only when the alpha-shift bit actually flips so a
            // single press cannot trigger the revert hotkey twice.
            let alphaShiftEngaged = flags.contains(.maskAlphaShift)
            guard alphaShiftEngaged != lastAlphaShiftState else { return nil }
            lastAlphaShiftState = alphaShiftEngaged
            return .revertHotkey
        }

        guard type == .keyDown else { return nil }

        if let kind = Self.classifyKeyDown(
            keyCode: keyCode,
            flags: flags,
            hotkeys: hotkeys,
            inputSourceShortcuts: systemInputSourceShortcuts.withLock { $0 }
        ) {
            return kind
        }

        let prefersTranslation = lifecycle.withLock { $0.prefersLayoutTranslation }
        let translated = translations.withLock {
            $0[TranslationKey(keyCode: keyCode, shifted: flags.contains(.maskShift))]
        }
        // Only physical keys: text expanders and auto-type post their text with any keyCode.
        // ISO keys 10 and 50 depend on a keyboard type an agent app may not know.
        let physical = event.getIntegerValueField(.eventSourceStateID)
            == Int64(CGEventSourceStateID.hidSystemState.rawValue)
        guard let text = KeyboardMonitor.typedCharacters(
            event: KeyboardMonitor.eventCharacterString(from: event),
            translated: translated,
            preferTranslation: prefersTranslation,
            canOverrideEvent: physical && keyCode != 10 && keyCode != 50
        ) else {
            return .navigation
        }
        if WordBoundary.isPunctuationBoundary(text) {
            return .boundary(text)
        }
        return .character(text)
    }

    /// The Cmd/Ctrl/Option/Shift subset of the flags that hotkeys and shortcuts compare.
    static let shortcutModifierMask: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]

    private static func isMatchingHotkey(
        keyCode: UInt16,
        flags: CGEventFlags,
        configuredKeyCode: UInt16,
        configuredModifiers: UInt64
    ) -> Bool {
        guard keyCode == configuredKeyCode else { return false }
        return flags.intersection(shortcutModifierMask)
            == CGEventFlags(rawValue: configuredModifiers).intersection(shortcutModifierMask)
    }

    /// A plain single left click only places the caret (reported at mouse-up, see
    /// `PlainClickTracker`). Other buttons open menus that may
    /// insert text; with modifiers a click adds a cursor (VS Code), opens the context menu
    /// (Control) or extends the selection (Shift); a double or triple click selects.
    public static func classifyMouseDown(isLeftButton: Bool, flags: CGEventFlags, clickState: Int64) -> CapturedInput.Kind {
        guard isLeftButton,
              flags.intersection(shortcutModifierMask).isEmpty,
              clickState <= 1 else {
            return .focusMayChange
        }
        return .caretMove(byClick: true)
    }

    /// Whether a key-down only moves the caret, leaving the text alone: Left/Right/Home/End
    /// without modifiers, or Left/Right with Cmd or Option alone (line and word jumps).
    /// Shift selects and Control belongs to system and app shortcuts; both stay navigation.
    static func isCaretMove(keyCode: UInt16, flags: CGEventFlags) -> Bool {
        guard caretKeyCodes.contains(keyCode) else { return false }
        let modifiers = flags.intersection(shortcutModifierMask)
        if modifiers.isEmpty { return true }
        return (keyCode == leftArrowKeyCode || keyCode == rightArrowKeyCode)
            && (modifiers == .maskCommand || modifiers == .maskAlternate)
    }

    /// The capture kind of a key-down, or nil for a key that types text (resolved from the
    /// event by the caller). Pure: the hotkeys and the system input-source shortcuts are passed in.
    public static func classifyKeyDown(
        keyCode: UInt16,
        flags: CGEventFlags,
        hotkeys: HotkeyConfiguration,
        inputSourceShortcuts: Set<InputSourceShortcut>
    ) -> CapturedInput.Kind? {
        if isMatchingHotkey(
            keyCode: keyCode,
            flags: flags,
            configuredKeyCode: hotkeys.hotkeyKeyCode,
            configuredModifiers: hotkeys.hotkeyModifiers
        ) {
            return .hotkey
        }
        if isMatchingHotkey(
            keyCode: keyCode,
            flags: flags,
            configuredKeyCode: hotkeys.revertHotkeyKeyCode,
            configuredModifiers: hotkeys.revertHotkeyModifiers
        ) {
            return .revertHotkey
        }

        if keyCode == zKeyCode,
           flags.contains(.maskCommand),
           flags.intersection([.maskControl, .maskAlternate, .maskShift]).isEmpty {
            return .undo
        }

        // A system shortcut that switches the input source (Ctrl+Space by default) acts like
        // the Globe key: layout-switch mode keeps the word typed before it.
        let shortcut = InputSourceShortcut(keyCode: keyCode, modifiers: flags.rawValue)
        if inputSourceShortcuts.contains(shortcut) {
            return .inputSourceKey
        }

        if isCaretMove(keyCode: keyCode, flags: flags) {
            return .caretMove(byClick: false)
        }
        if !flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty ||
            functionKeyCodes.contains(keyCode) {
            return .navigation
        }
        if navigationKeyCodes.contains(keyCode) {
            return .navigation
        }
        if keyCode == globeKeyCode {
            return .inputSourceKey
        }
        if keyCode == tabKeyCode || keyCode == escapeKeyCode {
            return .focusMayChange
        }
        if keyCode == spaceKeyCode {
            return .boundary(" ")
        }
        if keyCode == returnKeyCode || keyCode == keypadEnterKeyCode {
            return .boundary("\n")
        }
        if keyCode == deleteKeyCode {
            return .delete
        }
        return nil
    }

    // MARK: - System input-source shortcuts

    /// macOS default of "Select the previous input source" (id 60): Ctrl+Space.
    private static let previousSourceDefault = InputSourceShortcut(
        keyCode: spaceKeyCode,
        modifiers: CGEventFlags.maskControl.rawValue
    )
    /// macOS default of "Select next source in Input menu" (id 61): Ctrl+Option+Space.
    private static let nextSourceDefault = InputSourceShortcut(
        keyCode: spaceKeyCode,
        modifiers: CGEventFlags.maskControl.rawValue | CGEventFlags.maskAlternate.rawValue
    )
    public static let defaultInputSourceShortcuts: Set<InputSourceShortcut> = [previousSourceDefault, nextSourceDefault]

    /// `AppleSymbolicHotKeys` ids of the input-source shortcuts and their defaults.
    private static let inputSourceShortcutIDs = [("60", previousSourceDefault), ("61", nextSourceDefault)]

    /// The enabled input-source shortcuts in `symbolicHotKeys` (`AppleSymbolicHotKeys` of
    /// `com.apple.symbolichotkeys`; nil: the domain is missing). An absent or malformed entry
    /// means the macOS default; with fewer than two selectable input sources nothing switches,
    /// so the keys stay ordinary shortcuts (IDE autocomplete).
    public static func inputSourceShortcuts(
        from symbolicHotKeys: [String: Any]?,
        selectableSourceCount: Int
    ) -> Set<InputSourceShortcut> {
        guard selectableSourceCount >= 2 else { return [] }
        var result = Set<InputSourceShortcut>()
        for (id, fallback) in inputSourceShortcutIDs {
            guard let entry = symbolicHotKeys?[id] as? [String: Any] else {
                result.insert(fallback)
                continue
            }
            // No `enabled` key: on. A value that is not a number or bool: malformed, the default.
            let enabled: Bool
            if let flag = entry["enabled"] {
                guard let number = flag as? NSNumber else {
                    result.insert(fallback)
                    continue
                }
                enabled = number.boolValue
            } else {
                enabled = true
            }
            guard enabled else { continue }
            guard let value = entry["value"] as? [String: Any],
                  let parameters = value["parameters"] as? [NSNumber],
                  parameters.count >= 3 else {
                result.insert(fallback)
                continue
            }
            // A cleared shortcut is stored as (65535, 65535, 0).
            guard let keyCode = UInt16(exactly: parameters[1].intValue), keyCode != UInt16.max else { continue }
            result.insert(InputSourceShortcut(keyCode: keyCode, modifiers: parameters[2].uint64Value))
        }
        return result
    }

    /// Re-reads the input-source shortcuts (on main, never inside the tap callback).
    private func refreshInputSourceShortcuts() {
        let domain = "com.apple.symbolichotkeys" as CFString
        // Another process (System Settings) writes this domain: drop the cached copy.
        CFPreferencesAppSynchronize(domain)
        let symbolicHotKeys = CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString, domain) as? [String: Any]
        let filter = [
            kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String,
            kTISPropertyInputSourceIsSelectCapable as String: true,
        ] as CFDictionary
        let selectable = (TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource])?.count ?? 0
        let shortcuts = Self.inputSourceShortcuts(from: symbolicHotKeys, selectableSourceCount: selectable)
        let changed = systemInputSourceShortcuts.withLock { current -> Bool in
            defer { current = shortcuts }
            return current != shortcuts
        }
        if changed {
            SwitchFixLog.monitor.notice("input-source shortcuts: \(shortcuts.count) (selectable sources: \(selectable))")
        }
    }

    /// The text a key typed: the event's own text, or the current layout's (`translated`).
    ///
    /// The HID tap sees events before they get text, so it always translates. At session
    /// level, right after SwitchFix switches the layout, macOS may still attach the previous
    /// layout's text to key events while the app (Safari, Notes) types with the new one; when
    /// the two disagree on Cyrillic, the current layout wins. Case (Caps Lock) and differences
    /// within one script (Russian vs Ukrainian, punctuation vs punctuation) keep the event's text.
    /// - Parameter canOverrideEvent: false for posted (non-hardware) events and ISO-dependent keys.
    public static func typedCharacters(
        event: String?,
        translated: String?,
        preferTranslation: Bool,
        canOverrideEvent: Bool = true
    ) -> String? {
        if preferTranslation { return translated ?? event }
        guard canOverrideEvent, let event, let translated else { return event }
        return isCyrillic(event) == isCyrillic(translated) ? event : translated
    }

    private static func isCyrillic(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x400...0x4FF).contains($0.value) }
    }

    private static func eventCharacterString(from event: CGEvent) -> String? {
        var actualLength = 0
        var characters = [UniChar](repeating: 0, count: 8)
        event.keyboardGetUnicodeString(
            maxStringLength: characters.count,
            actualStringLength: &actualLength,
            unicodeString: &characters
        )
        guard actualLength > 0 else { return nil }
        let text = String(utf16CodeUnits: characters, count: actualLength)
        return text.isEmpty ? nil : text
    }

    private static func translatedCharacter(
        from source: TISInputSource,
        keyCode: UInt16,
        shifted: Bool
    ) -> String? {
        guard let layoutDataReference = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let layoutData = unsafeBitCast(layoutDataReference, to: CFData.self) as Data
        let modifierState: UInt32 = shifted ? UInt32(shiftKey >> 8) : 0
        var deadKeyState: UInt32 = 0
        var characters = [UniChar](repeating: 0, count: 8)
        var actualLength = 0
        // The layout pointer is only valid inside withUnsafeBytes.
        let status = layoutData.withUnsafeBytes { pointer -> OSStatus in
            guard let baseAddress = pointer.baseAddress else { return OSStatus(paramErr) }
            return UCKeyTranslate(
                baseAddress.assumingMemoryBound(to: UCKeyboardLayout.self),
                keyCode,
                UInt16(kUCKeyActionDown),
                modifierState,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                characters.count,
                &actualLength,
                &characters
            )
        }
        guard status == noErr, actualLength > 0 else { return nil }
        return String(utf16CodeUnits: characters, count: actualLength)
    }

    private static let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let startedAt = DispatchTime.now().uptimeNanoseconds
        let monitor = Unmanaged<KeyboardMonitor>.fromOpaque(userInfo).takeUnretainedValue()
        monitor.handle(type: type, event: event, startedAt: startedAt)
        return Unmanaged.passUnretained(event)
    }

    deinit {
        stop()
    }
}

/// Turns a plain click into a caret move at mouse-up. The mouse-down itself may change focus
/// and is reported as such; text a click edits (a menu item, a suggestion, dropped text)
/// changes at mouse-up, so the caret settles from there, and a drag in between is an edit.
public struct PlainClickTracker {
    private var pending = false

    public init() {}

    /// `kind`: `KeyboardMonitor.classifyMouseDown`; reported as `.focusMayChange`.
    public mutating func mouseDown(_ kind: CapturedInput.Kind) -> CapturedInput.Kind {
        pending = kind == .caretMove(byClick: true)
        return .focusMayChange
    }

    /// The mouse moved with the button down (selecting or dragging text), or a key was
    /// pressed during the click.
    public mutating func dragged() {
        pending = false
    }

    public mutating func mouseUp() -> CapturedInput.Kind? {
        defer { pending = false }
        return pending ? .caretMove(byClick: true) : nil
    }
}
