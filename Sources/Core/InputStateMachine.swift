import Foundation

public enum InputCorrectionMode: Equatable {
    case automatic
    case hotkey
    case layoutSwitch
}

public struct InputPreferencesSnapshot: Equatable {
    public let isEnabled: Bool
    public let correctionMode: InputCorrectionMode

    public init(isEnabled: Bool, correctionMode: InputCorrectionMode) {
        self.isEnabled = isEnabled
        self.correctionMode = correctionMode
    }
}

public enum InputInvalidationReason: Equatable {
    case disabled
    case staleContext
    case disallowedApplication
    case secureFocus
    case unknownFocus
    case navigation
    case inputSourceKey
    case focusChanged
    case tapReset
    case queueOverflow
    case bufferOverflow
    case contextChanged
}

public enum InputStateCommand: Equatable {
    case append(String)
    case flush(word: String, boundary: String, sequence: UInt64, context: InputContextSnapshot)
    case deleteLast
    case invalidate(InputInvalidationReason)
    /// `screenSuffix`: how the text before the caret must end (see `ScreenSuffix`); nil when
    /// SwitchFix cannot vouch for the screen, so no word is read from it.
    case requestManualCorrection(word: String?, screenSuffix: String?, sequence: UInt64, context: InputContextSnapshot)
    case requestRevert(word: String?, sequence: UInt64, context: InputContextSnapshot)
    case nativeUndo
}

/// The end of the text before the caret as SwitchFix saw it typed since the last edit it did
/// not see. A word read from the screen (Accessibility, which can lag behind typing) is
/// trusted only when the screen ends with it, so something must have been typed since.
/// Clicks and arrow keys count as unseen too: focus resolution replaces the context, and
/// modifier shortcuts (Cmd+V, Opt+Backspace) are classified as navigation.
struct ScreenSuffix {
    private(set) var text = ""
    /// Something changed the text unseen (undo, a correction, a dropped event): an empty
    /// suffix proves nothing until the user types again.
    private(set) var needsTyping = true

    var verification: String? { needsTyping && text.isEmpty ? nil : text }

    mutating func unknownEdit() {
        text = ""
        needsTyping = true
    }

    mutating func typed(_ characters: String) {
        text += characters
        // The screen window is one character longer than the longest word.
        if text.count > CaretWordExtractor.maxWordLength {
            text = String(text.suffix(CaretWordExtractor.maxWordLength))
        }
    }

    mutating func deleted() {
        if text.isEmpty {
            needsTyping = true
        } else {
            text.removeLast()
        }
    }
}

public struct InputStateMachine {
    public private(set) var currentBuffer = ""
    public private(set) var isInvalidUntilBoundary = false
    /// Set by caret keys (arrows, Home/End, Page Up/Down, with or without modifiers): the
    /// caret may now be inside a word, so the characters typed until the next boundary are
    /// kept for the hotkey but never flushed for automatic correction. Other shortcuts
    /// (Option+Backspace, Cmd+V) do not set it: the word retyped after them is corrected.
    /// Clicks do not set it either — the first word typed after a click must be corrected.
    /// Cleared at a boundary or an app switch, not by focus resolution, which replaces the
    /// context after every arrow key.
    public private(set) var skipsAutomaticFlushUntilBoundary = false
    public private(set) var layoutSwitchWord = ""
    private var screenSuffix = ScreenSuffix()
    public private(set) var context: InputContextSnapshot
    public private(set) var preferences: InputPreferencesSnapshot

    public init(context: InputContextSnapshot, preferences: InputPreferencesSnapshot) {
        self.context = context
        self.preferences = preferences
    }

    public mutating func updateContext(_ context: InputContextSnapshot) -> [InputStateCommand] {
        let changed = self.context != context
        if context.frontmostPID != self.context.frontmostPID {
            skipsAutomaticFlushUntilBoundary = false
        }
        self.context = context
        guard changed else { return [] }
        currentBuffer = ""
        isInvalidUntilBoundary = false
        layoutSwitchWord = ""
        screenSuffix.unknownEdit()
        return [.invalidate(.contextChanged)]
    }

    /// Marks the buffer invalid until the next boundary: used when an event was
    /// dropped (stale context), so on-screen text and the buffer may disagree.
    public mutating func invalidateUntilBoundary() {
        invalidate(untilBoundary: true)
        screenSuffix.unknownEdit()
    }

    public mutating func updatePreferences(_ preferences: InputPreferencesSnapshot) -> [InputStateCommand] {
        let wasEnabled = self.preferences.isEnabled
        self.preferences = preferences
        guard wasEnabled && !preferences.isEnabled else { return [] }
        currentBuffer = ""
        isInvalidUntilBoundary = false
        layoutSwitchWord = ""
        screenSuffix.unknownEdit()
        return [.invalidate(.disabled)]
    }

    public mutating func consume(_ input: CapturedInput) -> [InputStateCommand] {
        guard input.sourceUserData != switchFixEventMarker else { return [] }
        // Cleared by any consumed input; text inserted without a captured event
        // (dictation, emoji picker) does not clear it — InputEngine bounds its age.
        layoutSwitchWord = ""

        guard input.context.epoch == context.epoch,
              input.context.frontmostPID == context.frontmostPID,
              input.context.layout == context.layout,
              input.context.inputSourceID == context.inputSourceID else {
            invalidate(untilBoundary: false)
            screenSuffix.unknownEdit()
            return [.invalidate(.staleContext)]
        }

        switch input.kind {
        case .tapReset:
            invalidate(untilBoundary: true)
            screenSuffix.unknownEdit()
            return [.invalidate(.tapReset)]
        case .queueOverflow:
            invalidate(untilBoundary: true)
            screenSuffix.unknownEdit()
            return [.invalidate(.queueOverflow)]
        case .navigation:
            invalidate(untilBoundary: false)
            if KeyboardMonitor.navigationKeyCodes.contains(input.keyCode) {
                skipsAutomaticFlushUntilBoundary = true
            }
            screenSuffix.unknownEdit()
            return [.invalidate(.navigation)]
        case .inputSourceKey:
            // The key may insert text instead of switching (emoji picker), so the
            // buffer must not continue across it; the word is only set aside for a
            // layout change that follows before any other input.
            let word = canBuffer(input.context) && !isInvalidUntilBoundary ? currentBuffer : ""
            invalidate(untilBoundary: false)
            layoutSwitchWord = word
            screenSuffix.unknownEdit()
            return [.invalidate(.inputSourceKey)]
        case .focusMayChange:
            invalidate(untilBoundary: false)
            screenSuffix.unknownEdit()
            return [.invalidate(.focusChanged)]
        case .undo:
            invalidate(untilBoundary: true)
            screenSuffix.unknownEdit()
            return [.nativeUndo]
        case .hotkey:
            let word = currentBuffer.isEmpty ? nil : currentBuffer
            let suffix = screenSuffix.verification
            // The correction rewrites these characters outside the event stream,
            // so the buffer must drop them; keeping them desyncs the buffer from
            // the screen and makes the next flush delete already-corrected text.
            currentBuffer = ""
            screenSuffix.unknownEdit()
            return [.requestManualCorrection(
                word: word,
                screenSuffix: suffix,
                sequence: input.sequence,
                context: input.context
            )]
        case .revertHotkey:
            let word = currentBuffer.isEmpty ? nil : currentBuffer
            // Same desync hazard: whether the revert succeeds (original text is
            // restored) or falls back to a manual correction, the on-screen word
            // is rewritten without buffer-visible events.
            currentBuffer = ""
            screenSuffix.unknownEdit()
            return [.requestRevert(word: word, sequence: input.sequence, context: input.context)]
        case .delete:
            guard canBuffer(input.context) else {
                return invalidateForContext(input.context)
            }
            screenSuffix.deleted()
            guard !currentBuffer.isEmpty, !isInvalidUntilBoundary else {
                invalidate(untilBoundary: true)
                return [.invalidate(.navigation)]
            }
            currentBuffer.removeLast()
            return [.deleteLast]
        case .character(let text):
            guard canBuffer(input.context) else {
                return invalidateForContext(input.context)
            }
            screenSuffix.typed(text)
            guard !isInvalidUntilBoundary else { return [] }
            let nextCount = currentBuffer.count + text.count
            guard nextCount <= 64 else {
                invalidate(untilBoundary: true)
                return [.invalidate(.bufferOverflow)]
            }
            currentBuffer += text
            return [.append(text)]
        case .boundary(let boundary):
            defer {
                currentBuffer = ""
                isInvalidUntilBoundary = false
                skipsAutomaticFlushUntilBoundary = false
            }
            guard canBuffer(input.context) else {
                return invalidateForContext(input.context)
            }
            screenSuffix.typed(boundary)
            guard !isInvalidUntilBoundary, !currentBuffer.isEmpty else { return [] }
            guard !skipsAutomaticFlushUntilBoundary else { return [] }
            switch preferences.correctionMode {
            case .automatic:
                return [.flush(
                    word: currentBuffer,
                    boundary: boundary,
                    sequence: input.sequence,
                    context: input.context
                )]
            case .hotkey, .layoutSwitch:
                return []
            }
        }
    }

    private func canBuffer(_ context: InputContextSnapshot) -> Bool {
        preferences.isEnabled && context.appAllowed && context.secureFocus == .notSecure
    }

    private mutating func invalidateForContext(_ context: InputContextSnapshot) -> [InputStateCommand] {
        invalidate(untilBoundary: false)
        screenSuffix.unknownEdit()
        if !preferences.isEnabled { return [.invalidate(.disabled)] }
        if !context.appAllowed { return [.invalidate(.disallowedApplication)] }
        if context.secureFocus == .secure { return [.invalidate(.secureFocus)] }
        return [.invalidate(.unknownFocus)]
    }

    private mutating func invalidate(untilBoundary: Bool) {
        currentBuffer = ""
        isInvalidUntilBoundary = untilBoundary
    }
}
