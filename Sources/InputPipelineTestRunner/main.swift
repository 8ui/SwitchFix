import AppKit
import Core
import CoreGraphics
import Darwin
import Foundation
import LanguageModel
import Utils

private var passed = 0
private var failed = 0

private final class DetectionRecorder {
    private let lock = NSLock()
    private var sequences: [UInt64] = []

    func record(_ sequence: UInt64) -> Int {
        lock.lock()
        defer { lock.unlock() }
        sequences.append(sequence)
        return sequences.count
    }

    func snapshot() -> [UInt64] {
        lock.lock()
        defer { lock.unlock() }
        return sequences
    }
}

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if condition() {
        passed += 1
    } else {
        failed += 1
        print("FAIL: \(message)")
    }
}

private func context(
    epoch: UInt64 = 1,
    pid: pid_t = 100,
    allowed: Bool = true,
    layout: Layout = .english,
    sourceID: String = "com.test.english",
    focus: SecureFocusState = .notSecure
) -> InputContextSnapshot {
    InputContextSnapshot(
        epoch: epoch,
        frontmostPID: pid,
        appAllowed: allowed,
        layout: layout,
        inputSourceID: sourceID,
        secureFocus: focus
    )
}

private func input(
    sequence: UInt64,
    kind: CapturedInput.Kind,
    context: InputContextSnapshot,
    editGeneration: UInt64? = nil,
    autorepeat: Bool = false,
    marker: Int64 = 0,
    keyCode: UInt16 = 0
) -> CapturedInput {
    CapturedInput(
        sequence: sequence,
        timestamp: sequence,
        kind: kind,
        keyCode: keyCode,
        flagsRawValue: 0,
        isAutorepeat: autorepeat,
        sourcePID: 1,
        sourceUserData: marker,
        context: context,
        editGeneration: editGeneration ?? sequence
    )
}

private func automaticMachine(_ value: InputContextSnapshot = context()) -> InputStateMachine {
    InputStateMachine(
        context: value,
        preferences: InputPreferencesSnapshot(isEnabled: true, correctionMode: .automatic)
    )
}

private func run(_ name: String, _ body: () -> Void) {
    print("--- \(name) ---")
    body()
}

run("ordered word") {
    let current = context()
    var machine = automaticMachine(current)
    var commands: [InputStateCommand] = []
    for (index, character) in ["c", "o", "d", "e"].enumerated() {
        commands += machine.consume(input(
            sequence: UInt64(index + 1),
            kind: .character(character),
            context: current
        ))
    }
    commands += machine.consume(input(sequence: 5, kind: .boundary(" "), context: current))
    let flushes = commands.compactMap { command -> String? in
        if case .flush(let word, _, _, _, _) = command { return word }
        return nil
    }
    check(flushes == ["code"], "c-o-d-e must flush exactly once and in order")
}

run("navigation skips automatic correction of the word it lands in") {
    let current = context()
    var machine = automaticMachine(current)
    var sequence: UInt64 = 0
    func send(_ kind: CapturedInput.Kind, keyCode: UInt16 = 0) -> [InputStateCommand] {
        sequence += 1
        return machine.consume(input(sequence: sequence, kind: kind, context: current, keyCode: keyCode))
    }
    func flushed(_ commands: [InputStateCommand]) -> [String] {
        commands.compactMap { if case .flush(let word, _, _, _, _) = $0 { return word } else { return nil } }
    }
    let leftArrow: UInt16 = 123
    let backspace: UInt16 = 51
    for character in ["w", "o", "r"] { _ = send(.character(character)) }
    _ = send(.navigation, keyCode: leftArrow)
    _ = send(.character("d"))
    _ = send(.character("s"))
    check(machine.currentBuffer == "ds", "keys after an arrow stay buffered for the hotkey")
    check(flushed(send(.boundary(" "))).isEmpty, "a fragment typed after an arrow is not auto-corrected")
    for character in ["g", "h", "b", "d", "t", "n"] { _ = send(.character(character)) }
    check(flushed(send(.boundary(" "))) == ["ghbdtn"], "the next word is corrected again")
    // Option+Backspace (a shortcut, not a caret key) deletes a word; the retyped word is corrected.
    _ = send(.navigation, keyCode: backspace)
    for character in ["g", "h", "b", "d", "t", "n"] { _ = send(.character(character)) }
    check(flushed(send(.boundary(" "))) == ["ghbdtn"], "a word retyped after Option+Backspace is corrected")
    // An app switch after an arrow starts fresh.
    _ = send(.navigation, keyCode: leftArrow)
    let otherApp = context(epoch: 2, pid: 200)
    _ = machine.updateContext(otherApp)
    for character in ["g", "h", "b", "d", "t", "n"] {
        sequence += 1
        _ = machine.consume(input(sequence: sequence, kind: .character(character), context: otherApp))
    }
    sequence += 1
    let afterSwitch = machine.consume(input(sequence: sequence, kind: .boundary(" "), context: otherApp))
    check(flushed(afterSwitch) == ["ghbdtn"], "the first word in another app is corrected")
}

run("flush marks a word typed right after the previous flush") {
    let current = context()
    var machine = automaticMachine(current)
    var sequence: UInt64 = 0
    func send(_ kind: CapturedInput.Kind) -> [InputStateCommand] {
        sequence += 1
        return machine.consume(input(sequence: sequence, kind: kind, context: current))
    }
    func adjacency(after between: [CapturedInput.Kind], word: String = "ab") -> Bool? {
        for kind in between { _ = send(kind) }
        for character in word { _ = send(.character(String(character))) }
        for command in send(.boundary(" ")) {
            if case .flush(_, _, _, _, let continues) = command { return continues }
        }
        return nil
    }
    check(adjacency(after: []) == false, "the first word follows nothing")
    check(adjacency(after: []) == true, "a word typed right after a flush continues it")
    check(adjacency(after: [.character("x"), .delete]) == true, "deletes inside the word keep adjacency")
    check(adjacency(after: [.boundary(" ")]) == false, "a second space breaks adjacency")
    _ = adjacency(after: [])
    check(adjacency(after: [.undo, .boundary(" ")]) == false, "undo breaks adjacency")
    _ = adjacency(after: [])
    check(adjacency(after: [.hotkey]) == false, "a hotkey breaks adjacency")
}

run("autorepeat preserved") {
    let current = context()
    var machine = automaticMachine(current)
    _ = machine.consume(input(sequence: 1, kind: .character("c"), context: current, autorepeat: true))
    _ = machine.consume(input(sequence: 2, kind: .character("c"), context: current, autorepeat: true))
    let commands = machine.consume(input(sequence: 3, kind: .boundary(" "), context: current))
    let word = commands.compactMap { command -> String? in
        if case .flush(let word, _, _, _, _) = command { return word }
        return nil
    }.first
    check(word == "cc", "autorepeat characters must not be deduplicated")
}

run("manual hotkey resyncs buffer") {
    let current = context()
    var machine = automaticMachine(current)
    for (index, character) in ["g", "h", "b", "d", "t", "n"].enumerated() {
        _ = machine.consume(input(
            sequence: UInt64(index + 1),
            kind: .character(character),
            context: current
        ))
    }
    let hotkeyCommands = machine.consume(input(sequence: 7, kind: .hotkey, context: current))
    guard case .requestManualCorrection(let word?, _, _, _) = hotkeyCommands.first else {
        check(false, "hotkey must request manual correction with the buffered word")
        return
    }
    check(word == "ghbdtn", "hotkey must hand the buffered word to correction")
    check(machine.currentBuffer.isEmpty, "buffer must drop the word handed to correction")

    // The correction rewrites the word via tagged events the pipeline ignores,
    // so only post-hotkey typing may remain in the buffer.
    for (index, character) in ["d", "r", "u", "g"].enumerated() {
        _ = machine.consume(input(
            sequence: UInt64(8 + index),
            kind: .character(character),
            context: current
        ))
    }
    let flushed = machine.consume(input(sequence: 12, kind: .boundary(" "), context: current))
        .compactMap { command -> String? in
            if case .flush(let word, _, _, _, _) = command { return word }
            return nil
        }
    check(flushed == ["drug"], "stale pre-correction text must never be re-deleted at the next boundary")
}

run("revert hotkey resyncs buffer") {
    let current = context()
    var machine = automaticMachine(current)
    _ = machine.consume(input(sequence: 1, kind: .character("x"), context: current))
    let commands = machine.consume(input(sequence: 2, kind: .revertHotkey, context: current))
    guard case .requestRevert(let word?, _, _) = commands.first else {
        check(false, "revert hotkey must request revert with the buffered word")
        return
    }
    check(word == "x", "revert must hand the buffered word to the undo path")
    check(machine.currentBuffer.isEmpty, "revert must drop the buffered word to avoid desync")
}

run("generated identity ignored") {
    let current = context()
    var machine = automaticMachine(current)
    _ = machine.consume(input(sequence: 1, kind: .character("a"), context: current))
    let ignored = machine.consume(input(
        sequence: 999,
        kind: .character("x"),
        context: current,
        marker: switchFixEventMarker
    ))
    check(ignored.isEmpty && machine.currentBuffer == "a", "tagged events must be ignored regardless of arrival time")
}

run("no correction pause window") {
    let current = context()
    var machine = automaticMachine(current)
    var appended: [String] = []
    for sequence in UInt64(1)...UInt64(20) {
        let character = String(UnicodeScalar(96 + Int(sequence))!)
        for command in machine.consume(input(
            sequence: sequence,
            kind: .character(character),
            context: current
        )) {
            if case .append(let value) = command { appended.append(value) }
        }
    }
    check(appended.count == 20 && appended.joined().count == 20, "physical input must remain represented exactly once")
}

run("native undo invalidates detector state") {
    let current = context()
    var machine = automaticMachine(current)
    _ = machine.consume(input(sequence: 1, kind: .character("x"), context: current))
    let commands = machine.consume(input(sequence: 2, kind: .undo, context: current))
    check(commands.contains(.nativeUndo), "Command-Z must reach the pipeline as native undo")
    check(machine.currentBuffer.isEmpty && machine.isInvalidUntilBoundary, "native undo must invalidate detector synchronization")
}

run("correction sequence and context gates") {
    let base = context()
    let plan = CorrectionPlan(
        boundarySequence: 10,
        contextEpoch: base.epoch,
        targetPID: base.frontmostPID,
        editGeneration: 10,
        correctionEpoch: 0,
        deleteCount: 5,
        replacementText: "hello ",
        originalText: "руддщ",
        correctedText: "hello",
        boundaryText: " ",
        originalLayout: .ukrainian,
        targetLayout: .english
    )
    let valid = CaptureStateSnapshot(
        latestPhysicalSequence: 10,
        editGeneration: 10,
        correctionEpoch: 0,
        context: base,
        pendingInputCount: 0,
        correctionAllowed: true
    )
    check(plan.isEligible(using: valid), "matching candidate must be eligible")
    check(!plan.isEligible(using: CaptureStateSnapshot(
        latestPhysicalSequence: 11,
        editGeneration: 11,
        correctionEpoch: 0,
        context: base,
        pendingInputCount: 0,
        correctionAllowed: true
    )), "later physical input must cancel a candidate")

    let staleContexts = [
        context(epoch: 2),
        context(pid: 101),
        context(allowed: false),
        context(epoch: 2, layout: .ukrainian, sourceID: "com.test.ukrainian"),
        context(focus: .unknown),
        context(focus: .secure),
    ]
    for stale in staleContexts {
        let state = CaptureStateSnapshot(
            latestPhysicalSequence: 10,
            editGeneration: 10,
            correctionEpoch: 0,
            context: stale,
            pendingInputCount: 0,
            correctionAllowed: true
        )
        check(!plan.isEligible(using: state), "app/layout/focus/security epoch changes must cancel candidates")
    }
    let reset = CaptureStateSnapshot(
        latestPhysicalSequence: 10,
        editGeneration: 10,
        correctionEpoch: 0,
        context: base,
        pendingInputCount: 0,
        correctionAllowed: false
    )
    check(!plan.isEligible(using: reset), "tap reset or overload must disable correction eligibility")
}

run("secure focus fails closed") {
    check(AccessibilityFocusCoordinator.classifyFocus(
        role: "AXTextField",
        subrole: "AXSecureTextField",
        subroleQueryDefinitive: true
    ) == .secure, "AX secure-text subrole must classify as secure")
    check(AccessibilityFocusCoordinator.classifyFocus(
        role: "AXTextField",
        subrole: nil,
        subroleQueryDefinitive: false
    ) == .unknown, "failed AX subrole query must remain unknown")
    check(AccessibilityFocusCoordinator.resolveFocus(
        accessibilityState: .unknown,
        secureInputEnabled: true
    ) == .secure, "secure-input mode must protect inaccessible password fields")
    check(AccessibilityFocusCoordinator.resolveFocus(
        accessibilityState: .unknown,
        secureInputEnabled: false
    ) == .notSecure, "normal inaccessible web editors must remain available")
    for focus in [SecureFocusState.unknown, .secure] {
        let current = context(focus: focus)
        var machine = automaticMachine(current)
        _ = machine.consume(input(sequence: 1, kind: .character("s"), context: current))
        check(machine.currentBuffer.isEmpty, "unknown and secure focus must never buffer text")
    }
}

run("layout-switch selection source script") {
    check(
        ScriptAnalyzer.containsScript(for: .english, in: "hello [test]"),
        "Latin selections must be eligible when switching from English"
    )
    check(
        !ScriptAnalyzer.containsScript(for: .english, in: "привіт [тест]"),
        "Cyrillic selections must not be converted as English text"
    )
    check(
        ScriptAnalyzer.containsScript(for: .ukrainian, in: "привіт [тест]"),
        "Cyrillic selections must be eligible when switching from Ukrainian"
    )
}

run("selection source order") {
    check(
        ScriptAnalyzer.selectionSourceOrder(for: "привет, мир", currentLayout: .english) == [.russian, .ukrainian, .english],
        "Cyrillic text starts from a Cyrillic layout"
    )
    check(
        ScriptAnalyzer.selectionSourceOrder(for: "hello", currentLayout: .russian) == [.english, .russian, .ukrainian],
        "Latin text starts from English"
    )
    // No letters: ';' exists on both US and RussianWin (Shift+4), so only the layout the
    // text was typed on can decide — ';5' typed on Russian must become '$5', not 'ж5'.
    check(
        ScriptAnalyzer.selectionSourceOrder(for: ";5", currentLayout: .russian).first == .russian,
        "letterless text starts from the current layout"
    )
}

run("64 grapheme cap") {
    let current = context()
    var machine = automaticMachine(current)
    let grapheme = "👨‍👩‍👧‍👦"
    for sequence in UInt64(1)...UInt64(64) {
        _ = machine.consume(input(sequence: sequence, kind: .character(grapheme), context: current))
    }
    check(machine.currentBuffer.count == 64, "64 grapheme clusters must be accepted")
    let overflow = machine.consume(input(sequence: 65, kind: .character(grapheme), context: current))
    check(machine.currentBuffer.isEmpty && machine.isInvalidUntilBoundary, "65th grapheme must invalidate the buffer")
    check(overflow.contains(.invalidate(.bufferOverflow)), "overflow must emit an invalidation")
    _ = machine.consume(input(sequence: 66, kind: .boundary(" "), context: current))
    _ = machine.consume(input(sequence: 67, kind: .character("a"), context: current))
    check(machine.currentBuffer == "a", "boundary must rebuild state after overflow")
}

run("queue overload") {
    let current = context()
    let store = CaptureStateStore(
        context: current,
        hotkeys: HotkeyConfiguration(hotkeyModifiers: 0)
    )
    var overflowMarkers = 0
    for sequence in UInt64(1)...UInt64(300) {
        let captured = input(sequence: sequence, kind: .character("x"), context: current)
        switch store.reserveEnqueue(for: captured) {
        case .enqueue(let reserved):
            if reserved.kind == .queueOverflow { overflowMarkers += 1 }
        case .drop:
            break
        }
    }
    check(overflowMarkers == 1, "queue overload must enqueue one invalidation marker")
    check(!store.snapshot().correctionAllowed, "queue overload must disable correction")
    switch store.reserveEnqueue(for: input(sequence: 301, kind: .boundary(" "), context: current)) {
    case .enqueue:
        check(true, "boundary controls must not be dropped during overload")
    case .drop:
        check(false, "boundary controls must not be dropped during overload")
    }
}

run("tap reset recovery") {
    let current = context()
    let store = CaptureStateStore(context: current, hotkeys: HotkeyConfiguration(hotkeyModifiers: 0))
    var machine = automaticMachine(current)
    let reset = store.capture(
        timestamp: 1,
        kind: .tapReset,
        keyCode: 0,
        flagsRawValue: 0,
        isAutorepeat: false,
        sourcePID: 1,
        sourceUserData: 0
    )
    _ = machine.consume(reset)
    _ = machine.consume(store.capture(
        timestamp: 2,
        kind: .character("x"),
        keyCode: 0,
        flagsRawValue: 0,
        isAutorepeat: false,
        sourcePID: 1,
        sourceUserData: 0
    ))
    check(machine.currentBuffer.isEmpty && !store.snapshot().correctionAllowed, "tap reset must disable buffering and correction")
    _ = machine.consume(store.capture(
        timestamp: 3,
        kind: .boundary(" "),
        keyCode: 0,
        flagsRawValue: 0,
        isAutorepeat: false,
        sourcePID: 1,
        sourceUserData: 0
    ))
    _ = machine.consume(store.capture(
        timestamp: 4,
        kind: .character("y"),
        keyCode: 0,
        flagsRawValue: 0,
        isAutorepeat: false,
        sourcePID: 1,
        sourceUserData: 0
    ))
    check(machine.currentBuffer == "y" && store.snapshot().correctionAllowed, "a new boundary context must rebuild detector state after tap reset")
}

run("bounded tagged event batch") {
    let current = context()
    let plan = CorrectionPlan(
        boundarySequence: 1,
        contextEpoch: 1,
        targetPID: current.frontmostPID,
        editGeneration: 1,
        correctionEpoch: 0,
        deleteCount: 4,
        replacementText: "code ",
        originalText: "сщву",
        correctedText: "code",
        boundaryText: " ",
        originalLayout: .ukrainian,
        targetLayout: .english
    )
    let events = TextCorrector.eventDescriptors(for: plan)
    let deletes = events.filter {
        $0.kind == .deleteKeyDown || $0.kind == .deleteKeyUp
    }
    let unicode = events.filter {
        if case .unicodeKeyDown = $0.kind { return true }
        if case .unicodeKeyUp = $0.kind { return true }
        return false
    }
    check(deletes.count == 8, "N deletes must produce exactly N tagged key pairs")
    check(unicode.count == plan.replacementText.count * 2, "replacement of N chars must produce N Unicode key pairs")
    check(events.allSatisfy { $0.sourceUserData == switchFixEventMarker }, "every generated event must carry the marker")
}

run("undo generation") {
    let originalContext = context(epoch: 4, pid: 100)
    let plan = CorrectionPlan(
        boundarySequence: 7,
        contextEpoch: 4,
        targetPID: 100,
        editGeneration: 7,
        correctionEpoch: 0,
        deleteCount: 4,
        replacementText: "code ",
        originalText: "сщву",
        correctedText: "code",
        boundaryText: " ",
        originalLayout: .ukrainian,
        targetLayout: .english
    )
    let valid = CaptureStateSnapshot(
        latestPhysicalSequence: 8,
        editGeneration: 7,
        correctionEpoch: 0,
        context: originalContext,
        pendingInputCount: 0,
        correctionAllowed: true
    )
    check(TextCorrector.isUndoEligible(
        recordedPlan: plan,
        sequence: 8,
        context: originalContext,
        latest: valid
    ), "undo must be available only in its original app, epoch, and edit generation")
    let edited = CaptureStateSnapshot(
        latestPhysicalSequence: 9,
        editGeneration: 8,
        correctionEpoch: 0,
        context: originalContext,
        pendingInputCount: 0,
        correctionAllowed: true
    )
    check(!TextCorrector.isUndoEligible(
        recordedPlan: plan,
        sequence: 9,
        context: originalContext,
        latest: edited
    ), "next physical edit must invalidate undo")
    let otherApp = context(epoch: 5, pid: 101)
    let moved = CaptureStateSnapshot(
        latestPhysicalSequence: 8,
        editGeneration: 7,
        correctionEpoch: 0,
        context: otherApp,
        pendingInputCount: 0,
        correctionAllowed: true
    )
    check(!TextCorrector.isUndoEligible(
        recordedPlan: plan,
        sequence: 8,
        context: otherApp,
        latest: moved
    ), "undo must not target a different app or context epoch")
}

run("missing language model seam") {
    let missing = LanguageModelStore(resourceLocator: { _ in nil })
    check(!LanguageModelReadiness.prepare(.english, store: missing), "a missing model must report the layout unavailable")
    check(!LanguageModelReadiness.prepare(.russian, store: missing), "every layout needs its model and the English one")
    check(LanguageModelReadiness.prepare(.russian), "bundled models must load in the test runner")
    let current = context()
    let store = CaptureStateStore(context: current, hotkeys: HotkeyConfiguration(hotkeyModifiers: 0))
    let detectionCalled = DispatchSemaphore(value: 0)
    let correctionCalled = DispatchSemaphore(value: 0)
    let engine = InputEngine(
        captureState: store,
        initialContext: current,
        preferences: InputPreferencesSnapshot(isEnabled: true, correctionMode: .automatic),
        exactDetection: { _ in
            detectionCalled.signal()
            return nil
        },
        correctionEmission: { _ in
            correctionCalled.signal()
            return true
        }
    )
    engine.enqueue(store.capture(
        timestamp: 1,
        kind: .character("x"),
        keyCode: 0,
        flagsRawValue: 0,
        isAutorepeat: false,
        sourcePID: 1,
        sourceUserData: 0
    ))
    engine.enqueue(store.capture(
        timestamp: 2,
        kind: .boundary(" "),
        keyCode: 0,
        flagsRawValue: 0,
        isAutorepeat: false,
        sourcePID: 1,
        sourceUserData: 0
    ))
    check(detectionCalled.wait(timeout: .now() + 1) == .success, "unavailable exact detector must complete")
    check(correctionCalled.wait(timeout: .now() + 0.05) == .timedOut, "a detector returning nothing must produce no correction")
}

run("disabling invalidates queued corrections") {
    let current = context()
    let store = CaptureStateStore(context: current, hotkeys: HotkeyConfiguration(hotkeyModifiers: 0))
    let detectionEntered = DispatchSemaphore(value: 0)
    let releaseDetection = DispatchSemaphore(value: 0)
    let correctionCalled = DispatchSemaphore(value: 0)
    let engine = InputEngine(
        captureState: store,
        initialContext: current,
        preferences: InputPreferencesSnapshot(isEnabled: true, correctionMode: .automatic),
        exactDetection: { request in
            detectionEntered.signal()
            _ = releaseDetection.wait(timeout: .now() + 5)
            return DetectionResult(
                sourceLayout: .english,
                targetLayout: .ukrainian,
                convertedWord: "ч",
                originalWord: request.word,
                shouldSwitchLayout: false
            )
        },
        correctionEmission: { _ in
            correctionCalled.signal()
            return true
        }
    )
    engine.enqueue(store.capture(
        timestamp: 1,
        kind: .character("x"),
        keyCode: 0,
        flagsRawValue: 0,
        isAutorepeat: false,
        sourcePID: 1,
        sourceUserData: 0
    ))
    engine.enqueue(store.capture(
        timestamp: 2,
        kind: .boundary(" "),
        keyCode: 0,
        flagsRawValue: 0,
        isAutorepeat: false,
        sourcePID: 1,
        sourceUserData: 0
    ))
    check(detectionEntered.wait(timeout: .now() + 1) == .success, "queued detection must start")

    let initialEpoch = store.snapshot().correctionEpoch
    engine.updatePreferences(InputPreferencesSnapshot(isEnabled: false, correctionMode: .automatic))
    let disabled = store.snapshot()
    check(!disabled.correctionAllowed, "disabling must synchronously block correction")
    check(disabled.correctionEpoch != initialEpoch, "disabling must invalidate existing correction plans")

    engine.updatePreferences(InputPreferencesSnapshot(isEnabled: true, correctionMode: .automatic))
    let reenabled = store.snapshot()
    check(reenabled.correctionEpoch != disabled.correctionEpoch, "re-enabling must not revive invalidated plans")

    releaseDetection.signal()
    check(
        correctionCalled.wait(timeout: .now() + 0.2) == .timedOut,
        "a detection queued before disable must not emit after re-enable"
    )
}

private func layoutSwitchPlans(
    typing word: String,
    then switchKind: CapturedInput.Kind,
    afterSwitch: [CapturedInput.Kind] = [],
    notificationDelay: TimeInterval = 0,
    beforeNotification: (InputEngine, CaptureStateStore) -> Void = { _, _ in }
) -> [CorrectionPlan] {
    let current = context()
    let store = CaptureStateStore(context: current, hotkeys: HotkeyConfiguration(hotkeyModifiers: 0))
    let lock = NSLock()
    var plans: [CorrectionPlan] = []
    let engine = InputEngine(
        captureState: store,
        initialContext: current,
        preferences: InputPreferencesSnapshot(isEnabled: true, correctionMode: .layoutSwitch),
        correctionEmission: { plan in
            lock.lock()
            plans.append(plan)
            lock.unlock()
            return true
        }
    )
    func press(_ kind: CapturedInput.Kind) {
        engine.enqueue(store.capture(
            timestamp: 0,
            kind: kind,
            keyCode: 0,
            flagsRawValue: 0,
            isAutorepeat: false,
            sourcePID: 1,
            sourceUserData: 0
        ))
    }
    func drain(_ label: String) {
        let done = DispatchSemaphore(value: 0)
        engine.drain { done.signal() }
        check(done.wait(timeout: .now() + 2) == .success, "input queue must drain (\(label))")
    }
    for character in word {
        press(.character(String(character)))
    }
    press(switchKind)
    afterSwitch.forEach(press)
    // The input-source notification arrives after the keys are processed (~20 ms in
    // the field); replacing the context earlier would drop them as stale.
    drain("keys")
    beforeNotification(engine, store)
    drain("before notification")
    if notificationDelay > 0 {
        Thread.sleep(forTimeInterval: notificationDelay)
    }
    let latest = store.snapshot().context
    // Focus resolved as not secure, so only the word decides whether a plan is made.
    let switched = store.replaceContext(
        frontmostPID: latest.frontmostPID,
        appAllowed: latest.appAllowed,
        layout: .russian,
        inputSourceID: "com.test.russian",
        secureFocus: .notSecure
    )
    engine.handleLayoutChange(from: .english, to: .russian, context: switched, keyboardTables: .pc)
    drain("layout change")
    // The correction is emitted on the correction queue.
    Thread.sleep(forTimeInterval: 0.2)
    lock.lock()
    defer { lock.unlock() }
    return plans
}

private func convertedWords(_ plans: [CorrectionPlan]) -> [String] {
    plans.map(\.originalText)
}

run("layout switch keeps the word across the Globe key") {
    let plans = layoutSwitchPlans(typing: "ghbdtn", then: .inputSourceKey)
    check(plans.count == 1, "switching layout with the Globe key must convert the word before it, got \(plans.count) plans")
    check(plans.first?.correctedText == "привет", "Globe switch must convert ghbdtn to привет, got \(plans.first?.correctedText ?? "nil")")
    check(plans.first?.provenance == .layoutSwitch, "Globe switch correction must be tagged layoutSwitch")
}

run("layout switch drops the Globe word when anything intervenes") {
    check(
        convertedWords(layoutSwitchPlans(typing: "ghbdtn", then: .navigation)).isEmpty,
        "a cursor move before the switch must drop the word"
    )
    for (label, kind) in [("typing", CapturedInput.Kind.character("x")), ("click", .focusMayChange), ("arrow", .navigation)] {
        let words = convertedWords(layoutSwitchPlans(typing: "ghbdtn", then: .inputSourceKey, afterSwitch: [kind]))
        check(!words.contains { $0.contains("ghbdtn") }, "\(label) after the Globe key must drop the word, got \(words)")
    }
    let appSwitch = convertedWords(layoutSwitchPlans(typing: "ghbdtn", then: .inputSourceKey) { engine, store in
        let other = store.replaceContext(
            frontmostPID: 200,
            appAllowed: true,
            layout: .english,
            inputSourceID: "com.test.english",
            secureFocus: .notSecure
        )
        engine.updateContext(other)
    })
    check(appSwitch.isEmpty, "a frontmost-app change after the Globe key must drop the word, got \(appSwitch)")
    let toggled = convertedWords(layoutSwitchPlans(typing: "ghbdtn", then: .inputSourceKey) { engine, _ in
        engine.updatePreferences(InputPreferencesSnapshot(isEnabled: false, correctionMode: .layoutSwitch))
        engine.updatePreferences(InputPreferencesSnapshot(isEnabled: true, correctionMode: .layoutSwitch))
    })
    check(toggled.isEmpty, "disabling after the Globe key must drop the word, got \(toggled)")
    // Globe may start dictation instead; a much later switch must not delete what was dictated.
    let late = convertedWords(layoutSwitchPlans(typing: "ghbdtn", then: .inputSourceKey, notificationDelay: 0.6))
    check(late.isEmpty, "a layout change long after the Globe key must not convert the word, got \(late)")
}

run("Globe key without a layout change does not keep the word buffered") {
    let current = context()
    var machine = automaticMachine(current)
    for (index, character) in ["g", "h"].enumerated() {
        _ = machine.consume(input(sequence: UInt64(index + 1), kind: .character(character), context: current))
    }
    let globe = machine.consume(input(sequence: 3, kind: .inputSourceKey, context: current))
    check(globe == [.invalidate(.inputSourceKey)], "the Globe key must invalidate the buffer with its own reason, got \(globe)")
    check(machine.layoutSwitchWord == "gh", "the Globe key must set the word aside, got '\(machine.layoutSwitchWord)'")
    _ = machine.consume(input(sequence: 4, kind: .character("x"), context: current))
    let commands = machine.consume(input(sequence: 5, kind: .boundary(" "), context: current))
    let flushed = commands.compactMap { command -> String? in
        if case .flush(let word, _, _, _, _) = command { return word }
        return nil
    }
    // The Globe key may insert text (emoji picker), so the buffer must not glue across it.
    check(flushed == ["x"], "the word before a Globe press must not be flushed together with later input, got \(flushed)")
    check(machine.layoutSwitchWord.isEmpty, "any input after the Globe key must drop the pending layout-switch word")
}

run("caret word extraction") {
    func word(_ prefix: String, atStart: Bool = true, next: Character? = nil) -> String? {
        CaretWordExtractor.word(before: prefix, prefixStartsAtTextStart: atStart, next: next)
    }
    check(word("ujnjdj") == "ujnjdj", "a whole field is one word")
    check(word("hello ujnjdj") == "ujnjdj", "the last word after a space")
    check(word("hello\nujnjdj") == "ujnjdj", "the last word after a newline")
    check(word("(ghbdtn") == "ghbdtn", "hard punctuation ends the word")
    check(word("что-то") == "что-то", "a hyphen stays inside the word")
    check(word("b[jl") == "b[jl", "Cyrillic-letter punctuation stays inside the word")
    check(word("ghbdtn.") == "ghbdtn.", "a trailing soft boundary is kept, as in the buffer")
    check(word("❤️ghbdtn") == "ghbdtn", "an emoji ends the word")
    check(word("ujnjdj ") == nil, "nothing after a trailing space")
    check(word("") == nil, "nothing in an empty field")
    check(word("hel", next: "l") == nil, "the caret inside a word converts nothing")
    check(word("hello", next: " ") == "hello", "a space after the caret is fine")
    check(word("ujnjdj", atStart: false) == nil, "a word reaching a cut window start may be longer")
    check(word("x ujnjdj", atStart: false) == "ujnjdj", "a cut window is fine when the word starts inside it")
    check(word("123") == nil, "a word needs a letter")
    check(word("ghbdtné") == nil, "a character no layout can type rejects the word")
    check(word(String(repeating: "a", count: 65)) == nil, "a word over 64 characters is rejected")
}

run("100,000 event stress") {
    let current = context()
    let store = CaptureStateStore(context: current, hotkeys: HotkeyConfiguration(hotkeyModifiers: 0))
    let recorder = DetectionRecorder()
    let detectionsComplete = DispatchSemaphore(value: 0)
    let engine = InputEngine(
        captureState: store,
        initialContext: current,
        preferences: InputPreferencesSnapshot(isEnabled: true, correctionMode: .automatic),
        exactDetection: { request in
            if recorder.record(request.sequence) == 50_000 {
                detectionsComplete.signal()
            }
            return nil
        }
    )

    for sequence in UInt64(1)...UInt64(100_000) {
        let kind: CapturedInput.Kind = sequence.isMultiple(of: 2) ? .boundary(" ") : .character("x")
        let event = store.capture(
            timestamp: sequence,
            kind: kind,
            keyCode: 0,
            flagsRawValue: 0,
            isAutorepeat: false,
            sourcePID: 1,
            sourceUserData: 0
        )
        engine.enqueue(event)
        if sequence.isMultiple(of: 10) {
            engine.enqueue(input(
                sequence: sequence + 1_000_000,
                kind: .character("z"),
                context: current,
                marker: switchFixEventMarker
            ))
        }
        if sequence.isMultiple(of: 128) {
            let drained = DispatchSemaphore(value: 0)
            engine.drain { drained.signal() }
            check(drained.wait(timeout: .now() + 3) == .success, "engine batch must drain without loss")
        }
    }
    let drained = DispatchSemaphore(value: 0)
    engine.drain { drained.signal() }
    check(drained.wait(timeout: .now() + 3) == .success, "final engine batch must drain")
    check(detectionsComplete.wait(timeout: .now() + 30) == .success, "all boundary detections must complete")

    let sequences = recorder.snapshot()
    check(sequences.count == 50_000, "stress stream must lose or duplicate no physical words")
    check(sequences.enumerated().allSatisfy { index, sequence in
        sequence == UInt64((index + 1) * 2)
    }, "stress stream must preserve physical ordering")
    check(store.snapshot().latestPhysicalSequence == 100_000, "tagged events must not alter physical sequence")

    let inspected = DispatchSemaphore(value: 0)
    engine.inspectState { buffer, invalid, sequence in
        check(buffer.isEmpty && !invalid, "final detector state must match the physical stream")
        check(sequence == 100_000, "engine must process the final physical sequence")
        inspected.signal()
    }
    check(inspected.wait(timeout: .now() + 1) == .success, "final engine state must be observable")
}

run("tap modifier hotkeys") {
    check(TapModifierHotkey.configured(keyCode: 59)?.flag == .maskControl, "left Control configures a Control tap")
    check(TapModifierHotkey.configured(keyCode: 58)?.flag == .maskAlternate, "left Option configures an Option tap")
    check(TapModifierHotkey.configured(keyCode: 62) == nil, "tap hotkeys are stored by their left-side key code")
    check(TapModifierHotkey.containing(keyCode: 62)?.keyCode == 59, "right Control records as left Control")
    check(TapModifierHotkey.containing(keyCode: 61)?.keyCode == 58, "right Option records as left Option")
    check(TapModifierHotkey.containing(keyCode: 56) == nil, "Shift is not a tap hotkey")
}

run("app post mode overrides") {
    let suiteName = "com.switchfix.tests.postMode.\(getpid())"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        check(false, "test defaults suite must be available")
        return
    }
    defer { defaults.removePersistentDomain(forName: suiteName) }

    check(AppPostMode.overrides(in: defaults) == ["com.tdesktop.Telegram": .session],
          "unset overrides default to Telegram via the session tap")
    defaults.set([String: String](), forKey: AppPostMode.defaultsKey)
    check(AppPostMode.overrides(in: defaults).isEmpty, "an explicitly emptied list must not bring Telegram back")
    defaults.set(["com.example.a": "hid", "com.example.b": "bogus"], forKey: AppPostMode.defaultsKey)
    check(AppPostMode.overrides(in: defaults) == ["com.example.a": .hid], "stored modes are read and unknown ones ignored")
}

private enum BlockedCollaborator {
    case detection
    case accessibility
    case correction
}

private func assertRoutingContinues(while blocked: BlockedCollaborator) {
    let current = context()
    let store = CaptureStateStore(context: current, hotkeys: HotkeyConfiguration(hotkeyModifiers: 0))
    let entered = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)
    let routed = DispatchSemaphore(value: 0)

    let detection: InputEngine.ExactDetection = { request in
        if blocked == .detection {
            entered.signal()
            _ = release.wait(timeout: .now() + 5)
            return nil
        }
        return DetectionResult(
            sourceLayout: .english,
            targetLayout: .ukrainian,
            convertedWord: "ф",
            originalWord: request.word,
            shouldSwitchLayout: false
        )
    }
    let emission: InputEngine.CorrectionEmission = { _ in
        if blocked == .correction {
            entered.signal()
            _ = release.wait(timeout: .now() + 5)
        }
        return true
    }
    let selected: InputEngine.SelectedTextRequest = { _, _, completion in
        if blocked == .accessibility {
            entered.signal()
            _ = release.wait(timeout: .now() + 5)
        }
        completion(nil)
    }
    let engine = InputEngine(
        captureState: store,
        initialContext: current,
        preferences: InputPreferencesSnapshot(isEnabled: true, correctionMode: .automatic),
        exactDetection: detection,
        correctionEmission: emission,
        selectedTextRequest: selected
    )

    func enqueue(_ kind: CapturedInput.Kind, timestamp: UInt64) {
        engine.enqueue(store.capture(
            timestamp: timestamp,
            kind: kind,
            keyCode: 0,
            flagsRawValue: 0,
            isAutorepeat: false,
            sourcePID: 1,
            sourceUserData: 0
        ))
    }

    switch blocked {
    case .detection, .correction:
        enqueue(.character("a"), timestamp: 1)
        enqueue(.boundary(" "), timestamp: 2)
    case .accessibility:
        enqueue(.hotkey, timestamp: 1)
    }
    check(entered.wait(timeout: .now() + 1) == .success, "blocked collaborator must be exercised")
    enqueue(.character("b"), timestamp: 3)
    engine.drain { routed.signal() }
    check(routed.wait(timeout: .now() + 1) == .success, "input routing must not wait for blocked collaborator")
    release.signal()
}

run("blocked collaborators") {
    assertRoutingContinues(while: .detection)
    assertRoutingContinues(while: .accessibility)
    assertRoutingContinues(while: .correction)
}

private func runIntegrationSmoke() {
    guard Permissions.isAccessibilityGranted(), Permissions.isInputMonitoringGranted() else {
        print("SKIP: integration smoke requires Accessibility and Input Monitoring")
        return
    }

    let application = NSApplication.shared
    application.setActivationPolicy(.regular)
    application.finishLaunching()
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 400, height: 160),
        styleMask: [.titled],
        backing: .buffered,
        defer: false
    )
    let textView = NSTextView(frame: window.contentView?.bounds ?? .zero)
    window.contentView = textView
    window.makeKeyAndOrderFront(nil)
    window.makeFirstResponder(textView)
    application.activate(ignoringOtherApps: true)
    RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == getpid() else {
        print("SKIP: integration smoke could not make its NSTextView frontmost")
        window.close()
        return
    }
    textView.string = "wrong "
    textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))

    let smokeContext = context(pid: getpid())
    let plan = CorrectionPlan(
        boundarySequence: 1,
        contextEpoch: smokeContext.epoch,
        targetPID: getpid(),
        editGeneration: 1,
        correctionEpoch: 0,
        deleteCount: 6,
        replacementText: "fixed ",
        originalText: "wrong",
        correctedText: "fixed",
        boundaryText: " ",
        originalLayout: .english,
        targetLayout: nil
    )
    let snapshot = CaptureStateSnapshot(
        latestPhysicalSequence: 1,
        editGeneration: 1,
        correctionEpoch: 0,
        context: smokeContext,
        pendingInputCount: 0,
        correctionAllowed: true
    )
    let corrector = TextCorrector()
    DispatchQueue.main.async {
        check(corrector.apply(plan, latestCaptureState: { snapshot }), "integration event batch should post")
        let utf16 = Array("x".utf16)
        if let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
           let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) {
            utf16.withUnsafeBufferPointer { buffer in
                keyDown.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
                keyUp.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
            }
            keyDown.postToPid(getpid())
            keyUp.postToPid(getpid())
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if textView.string != "fixed x" {
                print("  integration received: \(String(reflecting: textView.string))")
            }
            check(textView.string == "fixed x", "NSTextView must preserve untagged input after the correction batch")
            window.close()
            application.stop(nil)
            if let wakeEvent = NSEvent.otherEvent(
                with: .applicationDefined,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 0,
                data1: 0,
                data2: 0
            ) {
                application.postEvent(wakeEvent, atStart: false)
            }
        }
    }
    application.run()
}

// MARK: - Personal lexicon learning (plan/005 §4.5, §12)

private final class EmissionLog {
    private let lock = NSLock()
    private var plans: [CorrectionPlan] = []
    func append(_ plan: CorrectionPlan) { lock.lock(); plans.append(plan); lock.unlock() }
    var last: CorrectionPlan? { lock.lock(); defer { lock.unlock() }; return plans.last }
    var count: Int { lock.lock(); defer { lock.unlock() }; return plans.count }
    var all: [CorrectionPlan] { lock.lock(); defer { lock.unlock() }; return plans }
}

private func waitUntil(_ timeout: TimeInterval = 2, _ condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        Thread.sleep(forTimeInterval: 0.01)
    }
    return condition()
}

/// What the fake Accessibility query answers for the manual hotkey.
private final class CaretStub {
    private let lock = NSLock()
    private var _reply: CaretContext = .unavailable
    private var _textQueries = 0
    /// Runs on the query queue before the reply (e.g. to type while AX is answering).
    var beforeReply: (() -> Void)?
    var reply: CaretContext {
        get { lock.lock(); defer { lock.unlock() }; return _reply }
        set { lock.lock(); _reply = newValue; lock.unlock() }
    }
    /// Queries that asked for the text around the caret, not just the selection.
    var textQueries: Int { lock.lock(); defer { lock.unlock() }; return _textQueries }
    func answer(wantsCaretText: Bool, _ completion: @escaping (CaretContext) -> Void) {
        if wantsCaretText { lock.lock(); _textQueries += 1; lock.unlock() }
        beforeReply?()
        let reply = self.reply
        if case .selection = reply { return completion(reply) }
        completion(wantsCaretText ? reply : .unavailable)
    }
}

/// What the fake field-text check answers before a correction deletes: the replies in
/// order, the last one repeated.
private final class ScreenStub {
    private let lock = NSLock()
    private var replies: [FieldTextProbe]
    private var _windows: [Int] = []
    /// Runs on the query queue before the first reply (e.g. to type while AX is answering).
    var beforeFirstReply: (() -> Void)?

    init(replies: [FieldTextProbe]) {
        self.replies = replies.isEmpty ? [.unavailable(transient: false)] : replies
    }

    convenience init(_ replies: FieldTextProbe...) {
        self.init(replies: replies)
    }

    /// The window length of every query, in order.
    var windows: [Int] { lock.lock(); defer { lock.unlock() }; return _windows }
    var queries: Int { windows.count }

    func answer(window: Int, _ completion: @escaping (FieldTextProbe) -> Void) {
        lock.lock()
        _windows.append(window)
        let first = _windows.count == 1
        let reply = replies.count > 1 ? replies.removeFirst() : replies[0]
        lock.unlock()
        if first { beforeFirstReply?() }
        completion(reply)
    }
}

private struct LearningHarness {
    let store: CaptureStateStore
    let engine: InputEngine
    let lexicon: PersonalLexicon
    let emitted: EmissionLog
    let caret = CaretStub()
    let screen: ScreenStub?
    var timestamp: UInt64 = 0

    init(
        mode: InputCorrectionMode = .automatic,
        revertReturnsNothing: Bool = false,
        layout: Layout = .english,
        screen: ScreenStub? = nil,
        screenCheckMode: ScreenCheckMode = .enforce
    ) {
        self.screen = screen
        let current = context(layout: layout, sourceID: "com.test.\(layout.rawValue)")
        store = CaptureStateStore(context: current, hotkeys: HotkeyConfiguration(hotkeyModifiers: 0))
        lexicon = PersonalLexicon(storage: InMemoryLexiconStorage(), saveDelay: 0)
        let emitted = EmissionLog()
        self.emitted = emitted
        engine = InputEngine(
            captureState: store,
            initialContext: current,
            preferences: InputPreferencesSnapshot(isEnabled: true, correctionMode: mode),
            correctionEmission: { plan in emitted.append(plan); return true },
            caretContextRequest: { [caret] _, _, wantsCaretText, completion in
                caret.answer(wantsCaretText: wantsCaretText, completion)
            },
            screenTextRequest: screen.map { screen in
                { _, _, window, completion in screen.answer(window: window, completion) }
            },
            screenCheckMode: screenCheckMode,
            lexicon: lexicon,
            revertEmission: { _, _ in revertReturnsNothing ? nil : emitted.last }
        )
        engine.updateDetectionConfiguration(allowedLayouts: [.english, .russian])
    }

    mutating func send(_ kind: CapturedInput.Kind, keyCode: UInt16 = 0) {
        timestamp += 1
        engine.enqueue(store.capture(
            timestamp: timestamp, kind: kind, keyCode: keyCode, flagsRawValue: 0,
            isAutorepeat: false, sourcePID: 1, sourceUserData: 0
        ))
    }

    mutating func type(_ word: String, boundary: String? = " ") {
        for character in word { send(.character(String(character))) }
        if let boundary { send(.boundary(boundary)) }
    }

    /// Focus resolves as a plain text field and the engine gets the new context, as
    /// AccessibilityFocusCoordinator and AppDelegate do after a click.
    func resolveFocus() {
        let drained = DispatchSemaphore(value: 0)
        engine.drain { drained.signal() }
        _ = drained.wait(timeout: .now() + 1)
        let current = store.snapshot().context
        if let resolved = store.resolveFocus(.notSecure, frontmostPID: current.frontmostPID, epoch: current.epoch) {
            engine.updateContext(resolved)
        }
    }

    /// Cmd+A (navigation), then Backspace into unknown text: the buffer is invalid until a space.
    mutating func selectAllAndDelete() {
        send(.navigation)
        resolveFocus()
        send(.delete)
    }
}

run("state machine: screen suffix for the hotkey") {
    let current = context()
    var machine = automaticMachine(current)
    var sequence: UInt64 = 0
    func send(_ kind: CapturedInput.Kind) -> [InputStateCommand] {
        sequence += 1
        return machine.consume(input(sequence: sequence, kind: kind, context: current))
    }
    func type(_ text: String) { for character in text { _ = send(.character(String(character))) } }
    func hotkeySuffix() -> String?? {
        guard case .requestManualCorrection(_, let suffix, _, _) = send(.hotkey).first else { return .none }
        return .some(suffix)
    }
    check(hotkeySuffix() == .some(nil), "at start the screen is unknown")
    _ = send(.navigation)
    check(hotkeySuffix() == .some(nil), "a click or shortcut may have edited the screen unseen")
    type("a")
    check(hotkeySuffix() == .some("a"), "typed characters are the suffix")
    check(hotkeySuffix() == .some(nil), "a hotkey rewrites the screen, so the next one cannot trust it")
    _ = send(.navigation)
    _ = send(.delete)
    check(hotkeySuffix() == .some(nil), "an unseen deletion needs typing before the screen is trusted")
    _ = send(.navigation)
    _ = send(.delete)
    type("ujnjdj")
    check(machine.currentBuffer.isEmpty, "characters after an unknown Backspace stay out of the buffer")
    check(hotkeySuffix() == .some("ujnjdj"), "the screen must end with what was typed")
    _ = send(.navigation)
    type("ujnjdjk")
    _ = send(.delete)
    check(hotkeySuffix() == .some("ujnjdj"), "Backspace removes the last typed character only")
    _ = send(.navigation)
    type("ab")
    _ = send(.boundary(" "))
    check(hotkeySuffix() == .some("ab "), "a typed boundary is part of the suffix")
    _ = send(.navigation)
    type(String(repeating: "a", count: 70))
    check(hotkeySuffix() == .some(String(repeating: "a", count: CaretWordExtractor.maxWordLength)), "the suffix keeps the last 64 characters")
    _ = send(.navigation)
    _ = send(.undo)
    check(hotkeySuffix() == .some(nil), "undo changes the screen unseen")
    _ = send(.undo)
    type("x")
    check(hotkeySuffix() == .some("x"), "typing after an unseen change makes the suffix usable again")
}

run("hotkey converts the word before the caret after Cmd+A, Backspace") {
    var harness = LearningHarness()
    harness.caret.reply = .caret(textBefore: "ujnjdj", startsAtTextStart: true, next: nil)
    harness.selectAllAndDelete()
    harness.type("ujnjdj", boundary: nil)
    harness.send(.hotkey)
    check(waitUntil { harness.emitted.count == 1 }, "the word read from the screen is converted")
    check(harness.emitted.last?.originalText == "ujnjdj", "the whole word is replaced, got \(harness.emitted.last?.originalText ?? "nil")")
    check(harness.emitted.last?.correctedText == "готово", "ujnjdj becomes готово, got \(harness.emitted.last?.correctedText ?? "nil")")
}

run("arrow keys skip automatic correction, the hotkey still converts from the buffer") {
    var harness = LearningHarness()
    harness.caret.reply = .unavailable
    harness.send(.navigation, keyCode: 123)
    harness.resolveFocus()
    harness.type("ghbdtn")
    check(!waitUntil(0.3) { harness.emitted.count > 0 }, "the word after an arrow is not auto-corrected even after focus resolves")
    harness.type("ghbdtn")
    check(waitUntil { harness.emitted.count == 1 }, "the next word is corrected")
    harness.send(.navigation, keyCode: 123)
    harness.resolveFocus()
    harness.type("ghbdtn", boundary: nil)
    harness.send(.hotkey)
    check(waitUntil { harness.emitted.count == 2 }, "the hotkey converts the buffered word without Accessibility")
    check(harness.emitted.last?.originalText == "ghbdtn", "got \(harness.emitted.last?.originalText ?? "nil")")
}

/// Strong Russian context, then the short 'ше' ('it' typed on the Russian layout), which the
/// detector defers and merges with a confirming next word ('цщклы' = 'works').
private func shortWordHarness(screen: ScreenStub? = nil) -> LearningHarness {
    var harness = LearningHarness(layout: .russian, screen: screen)
    harness.caret.reply = .unavailable
    harness.type("сейчас")
    harness.type("на")
    return harness
}

run("merged short word: typed right after it, one space between") {
    var harness = shortWordHarness()
    harness.type("ше")
    harness.type("цщклы")
    check(waitUntil { harness.emitted.count == 1 }, "the confirmed pair is corrected")
    check(harness.emitted.last?.originalText == "ше цщклы", "one merged correction, got \(harness.emitted.last?.originalText ?? "nil")")
    check(harness.emitted.last?.correctedText == "it works", "got \(harness.emitted.last?.correctedText ?? "nil")")
}

run("merged short word: never across unseen edits or a non-space boundary") {
    let currentWord = "цщклы ".count
    for (label, between) in [
        ("double space", [CapturedInput.Kind.boundary(" "), .boundary(" ")]),
        ("punctuation then space", [.boundary("!"), .boundary(" ")]),
        ("undo", [.undo, .character("ч"), .boundary(" ")]),
        ("hotkey with nothing to convert", [.hotkey, .boundary(" ")]),
    ] {
        var harness = shortWordHarness()
        harness.type("ше", boundary: nil)
        if case .boundary = between.first {} else { harness.send(.boundary(" ")) }
        for kind in between { harness.send(kind) }
        harness.type("цщклы")
        _ = waitUntil(0.5) { harness.emitted.count > 0 }
        let tooLong = harness.emitted.all.filter { $0.deleteCount > currentWord }
        check(tooLong.isEmpty, "\(label): a correction must not reach past the current word, got \(tooLong.map(\.originalText))")
    }
    var harness = shortWordHarness()
    harness.type("ше", boundary: "\n")
    harness.type("цщклы")
    _ = waitUntil(0.5) { harness.emitted.count > 0 }
    check(!harness.emitted.all.contains { $0.replacementText.contains("\n") }, "Enter is never retyped")
}

run("hotkey on a screen word never teaches the lexicon") {
    var harness = LearningHarness()
    harness.caret.reply = .caret(textBefore: "rehk", startsAtTextStart: true, next: nil)
    harness.selectAllAndDelete()
    harness.type("rehk", boundary: nil)
    harness.send(.hotkey)
    check(waitUntil { harness.emitted.count == 1 }, "an unrecognized screen word is still converted")
    check(harness.emitted.last?.provenance == .hotkey, "a screen word is not a forced lesson")
    check(!waitUntil(0.3) { !harness.lexicon.entries.isEmpty }, "the lexicon stays empty")
}

run("hotkey after a click without typing does not read the screen") {
    var harness = LearningHarness()
    harness.caret.reply = .caret(textBefore: "старое ujnjdj", startsAtTextStart: false, next: " ")
    harness.send(.focusMayChange)
    harness.resolveFocus()
    harness.send(.hotkey)
    check(!waitUntil(0.3) { harness.emitted.count > 0 }, "nothing typed since the click: the screen cannot be verified")
    check(harness.caret.textQueries == 0, "so it is not even read")
}

run("hotkey does not trust a screen word it cannot verify") {
    func emittedCount(_ reply: CaretContext, typed: String = "ujnjdj", configure: (inout LearningHarness) -> Void = { _ in }) -> Int {
        var harness = LearningHarness()
        harness.caret.reply = reply
        configure(&harness)
        harness.selectAllAndDelete()
        harness.type(typed, boundary: nil)
        harness.send(.hotkey)
        _ = waitUntil(0.3) { harness.emitted.count > 0 }
        return harness.emitted.count
    }
    check(emittedCount(.caret(textBefore: "ujnjd", startsAtTextStart: true, next: nil)) == 0,
          "accessibility text lagging behind typing must not be converted")
    check(emittedCount(.caret(textBefore: "ujnjdj", startsAtTextStart: true, next: "x")) == 0,
          "the caret inside a word converts nothing")
    check(emittedCount(.caret(textBefore: "ujnjdj ", startsAtTextStart: true, next: nil)) == 0,
          "a space before the caret converts nothing")
    check(emittedCount(.unavailable) == 0, "no accessibility text, no conversion")
    check(emittedCount(.caret(textBefore: "ujnjdjk", startsAtTextStart: true, next: nil), typed: "ujnjdjk") { harness in
        harness.caret.beforeReply = nil
    } == 1, "sanity: a matching screen converts")
    check(emittedCount(.caret(textBefore: "ujnjdj", startsAtTextStart: true, next: nil)) { harness in
        let store = harness.store, engine = harness.engine
        harness.caret.beforeReply = {
            engine.enqueue(store.capture(
                timestamp: 99, kind: .character("x"), keyCode: 0, flagsRawValue: 0,
                isAutorepeat: false, sourcePID: 1, sourceUserData: 0
            ))
            let drained = DispatchSemaphore(value: 0)
            engine.drain { drained.signal() }
            _ = drained.wait(timeout: .now() + 1)
        }
    } == 0, "typing while accessibility answers makes the reply stale")
}

run("hotkey rejects a screen that lags behind Backspace or a space") {
    var harness = LearningHarness()
    // The app still shows the deleted k.
    harness.caret.reply = .caret(textBefore: "ujnjdjk", startsAtTextStart: true, next: nil)
    harness.selectAllAndDelete()
    harness.type("ujnjdjk", boundary: nil)
    harness.send(.delete)
    harness.send(.hotkey)
    check(!waitUntil(0.3) { harness.emitted.count > 0 }, "a screen still showing a deleted character is not trusted")

    var spaced = LearningHarness(mode: .hotkey)
    // The app has not shown the space yet.
    spaced.caret.reply = .caret(textBefore: "ghbdtn", startsAtTextStart: true, next: nil)
    spaced.send(.focusMayChange)
    spaced.resolveFocus()
    spaced.type("ghbdtn")
    spaced.send(.hotkey)
    check(!waitUntil(0.3) { spaced.emitted.count > 0 }, "a screen missing the typed space is not trusted")
}

run("revert of a screen-word conversion restores it and teaches nothing") {
    var harness = LearningHarness()
    harness.caret.reply = .caret(textBefore: "rehk", startsAtTextStart: true, next: nil)
    harness.selectAllAndDelete()
    harness.type("rehk", boundary: nil)
    harness.send(.hotkey)
    check(waitUntil { harness.emitted.count == 1 }, "converted")
    harness.send(.revertHotkey)
    check(!waitUntil(0.3) { !harness.lexicon.entries.isEmpty }, "neither the conversion nor its revert teaches")
}

run("revert hotkey with nothing to undo does not read the screen") {
    var harness = LearningHarness(revertReturnsNothing: true)
    harness.caret.reply = .caret(textBefore: "Hello", startsAtTextStart: true, next: nil)
    harness.send(.focusMayChange)
    harness.resolveFocus()
    harness.send(.revertHotkey)
    check(!waitUntil(0.3) { harness.emitted.count > 0 }, "Caps Lock must not convert the word before the caret")
    check(harness.caret.textQueries == 0, "Caps Lock must not even read the text around the caret")
}

run("hotkey prefers the buffer over the screen") {
    var harness = LearningHarness()
    harness.caret.reply = .caret(textBefore: "zzz", startsAtTextStart: true, next: nil)
    harness.type("ujnjdj", boundary: nil)
    harness.send(.hotkey)
    check(waitUntil { harness.emitted.count == 1 }, "the buffered word is converted")
    check(harness.emitted.last?.originalText == "ujnjdj", "the buffer wins, got \(harness.emitted.last?.originalText ?? "nil")")
    check(harness.caret.textQueries == 0, "with a buffered word only the selection is read")
}

run("learning: revert of an automatic correction teaches neverCorrect") {
    var harness = LearningHarness()
    harness.type("ghbdtn")
    check(waitUntil { harness.emitted.count == 1 }, "automatic correction is emitted")
    check(harness.emitted.last?.provenance == .automatic, "boundary correction is automatic")
    harness.send(.revertHotkey)
    check(waitUntil { harness.lexicon.rule(for: "ghbdtn", sourceLayout: .english) == .neverCorrect }, "revert is learned")
    harness.type("ghbdtn")
    check(!waitUntil(0.3) { harness.emitted.count > 1 }, "the reverted word is not corrected again")
}

run("automatic correction: a word ended by Enter is not corrected") {
    var harness = LearningHarness()
    harness.type("ghbdtn", boundary: "\n")
    check(!waitUntil(0.3) { harness.emitted.count > 0 }, "Enter may have submitted the text: no delete, no retype")
    harness.type("ghbdtn")
    check(waitUntil { harness.emitted.count == 1 }, "the next word ended by a space is still corrected")
    _ = waitUntil(0.3) { harness.emitted.count > 1 }
    check(harness.emitted.count == 1, "exactly one correction, got \(harness.emitted.count)")
    check(!harness.emitted.all.contains { $0.boundaryText.contains("\n") }, "Enter is never retyped")
    check(harness.emitted.last?.boundaryText == " ", "only the space is retyped")
}

run("learning: forced hotkey conversion teaches alwaysCorrect") {
    var harness = LearningHarness()
    harness.type("rehk", boundary: nil)
    harness.send(.hotkey)
    check(waitUntil { harness.emitted.count == 1 }, "hotkey converts the unrecognized word")
    check(harness.emitted.last?.provenance == .hotkeyForced, "forced conversion is marked")
    check(waitUntil { harness.lexicon.rule(for: "rehk", sourceLayout: .english) == .alwaysCorrect(to: .russian) }, "hotkey lesson is learned")
    harness.send(.boundary(" "))
    harness.type("rehk")
    check(waitUntil { harness.emitted.count == 2 }, "the learned word is corrected automatically")
    check(harness.emitted.last?.provenance == .automatic, "second correction is automatic")
    check(waitUntil { harness.lexicon.entries.first?.matchCount == 1 }, "applied rule is counted")
}

run("learning: reverting a forced hotkey conversion forgets the lesson") {
    var harness = LearningHarness()
    harness.type("rehk", boundary: nil)
    harness.send(.hotkey)
    check(waitUntil { harness.lexicon.rule(for: "rehk", sourceLayout: .english) != nil }, "learned")
    harness.send(.revertHotkey)
    check(waitUntil { harness.lexicon.rule(for: "rehk", sourceLayout: .english) == nil }, "revert of a hotkey fix forgets, never adds neverCorrect")
}

run("learning: manual entries are not overwritten by reverts") {
    var harness = LearningHarness()
    _ = harness.lexicon.add(word: "ghbdtn", sourceLayout: .english, rule: .alwaysCorrect(to: .russian))
    harness.type("ghbdtn")
    check(waitUntil { harness.emitted.count == 1 }, "corrected by the manual rule")
    harness.send(.revertHotkey)
    check(!waitUntil(0.3) { harness.lexicon.rule(for: "ghbdtn", sourceLayout: .english) != .alwaysCorrect(to: .russian) }, "manual rule stays")
}

run("learning: forced hotkey target follows the last Cyrillic layout") {
    var harness = LearningHarness()
    harness.engine.updateDetectionConfiguration(allowedLayouts: Set(Layout.allCases))
    func switchLayout(to layout: Layout) {
        let next = harness.store.replaceContext(
            frontmostPID: 100, appAllowed: true, layout: layout,
            inputSourceID: "com.test.\(layout.rawValue)", secureFocus: .notSecure
        )
        harness.engine.updateContext(next)
    }
    func drainInput() {
        let drained = DispatchSemaphore(value: 0)
        harness.engine.drain { drained.signal() }
        _ = drained.wait(timeout: .now() + 1)
    }
    // Typing on Russian makes it the detector's last Cyrillic layout (survives reset()).
    // Drain before switching back: keystrokes processed after the switch would be
    // dropped as stale and never reach the detector.
    switchLayout(to: .russian)
    harness.type("привет")
    drainInput()
    switchLayout(to: .english)
    harness.type("rehk", boundary: nil)
    harness.send(.hotkey)
    check(waitUntil { harness.emitted.count == 1 }, "forced conversion is emitted")
    check(
        harness.emitted.last?.targetLayout == .russian,
        "forced Latin conversion prefers Russian, not the first installed (got \(harness.emitted.last?.targetLayout?.rawValue ?? "nil"))"
    )
}

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

run("learning: the revert hotkey's fallback conversion does not teach") {
    var harness = LearningHarness(revertReturnsNothing: true)
    harness.type("rehk", boundary: nil)
    harness.send(.revertHotkey)
    check(waitUntil { harness.emitted.count == 1 }, "with nothing to revert the word is converted")
    check(harness.emitted.last?.provenance == .hotkey, "the fallback is not a forced lesson")
    check(!waitUntil(0.3) { harness.lexicon.rule(for: "rehk", sourceLayout: .english) != nil }, "pressing Revert never teaches 'always correct'")
}

run("learning: one- and two-key hotkey conversions are not learned") {
    var harness = LearningHarness()
    harness.type("b", boundary: nil)
    harness.send(.hotkey)
    check(waitUntil { harness.emitted.count == 1 }, "the hotkey converts a single letter")
    check(!waitUntil(0.3) { !harness.lexicon.entries.isEmpty }, "too short to learn")
}

run("learning: trailing punctuation is not part of the learned word") {
    var harness = LearningHarness()
    harness.type("rehk!", boundary: nil)
    harness.send(.hotkey)
    check(waitUntil { harness.lexicon.rule(for: "rehk", sourceLayout: .english) != nil }, "learned without '!'")
}

run("learning: merged multi-word corrections are not learned") {
    let plan = CorrectionPlan(
        boundarySequence: 1, contextEpoch: 1, targetPID: 100, editGeneration: 1, correctionEpoch: 1,
        deleteCount: 9, replacementText: "it works ", originalText: "ше цщкли", correctedText: "it works",
        boundaryText: " ", originalLayout: .ukrainian, targetLayout: .english, provenance: .automatic
    )
    check(!InputEngine.isLearnable(plan), "a merged phrase is not a single token")
    check(!InputEngine.isLearnable(CorrectionPlan(
        boundarySequence: 1, contextEpoch: 1, targetPID: 100, editGeneration: 1, correctionEpoch: 1,
        deleteCount: 5, replacementText: "hello", originalText: "руддщ", correctedText: "hello",
        boundaryText: "", originalLayout: .russian, targetLayout: .english, provenance: .selection
    )), "selection replacements do not teach")
}

run("screen verification: verdict") {
    func verdict(_ word: String, _ probe: FieldTextProbe, boundary: String = " ", final: Bool = false) -> ScreenVerdict {
        ScreenVerification.verdict(word: word, boundary: boundary, probe: probe, final: final)
    }
    check(verdict("ghbdtn", .text(before: "старое ghbdtn ")) == .match, "the field ends with the typed word")
    check(verdict("ghbdtn", .text(before: "Ghbdtn ")) == .match, "automatic capitalization keeps the length")
    check(verdict("'nj", .text(before: "\u{2018}nj ")) == .match, "a smart single quote is still one character")
    check(verdict("\"nj", .text(before: "\u{00AB}nj ")) == .match, "a smart double quote is still one character")
    check(verdict("ghbdtn", .text(before: "ghbdtn\u{00A0}")) == .match, "contenteditable keeps a trailing space as NBSP")
    check(verdict("ie ww", .text(before: "ie\u{00A0}ww ")) == .match, "an NBSP inside a merged pair")
    check(verdict("caf\u{00E9}", .text(before: "cafe\u{0301} ")) == .match, "a decomposed accent is one character")
    check(verdict("ghbdtn", .text(before: "\u{1F600}ghbdtn ")) == .match, "an emoji before the word")
    check(verdict("ghbdtn", .text(before: "ghbdtn"), boundary: "") == .match, "the hotkey has no boundary")
    check(verdict("ghbdtn", .selection(length: 7)) == .mismatch, "an inline suggestion is selected")
    check(verdict("teh", .text(before: "the ")) == .mismatch, "autocorrect replaced the word")
    check(verdict("helo", .text(before: "hello ")) == .mismatch, "a prediction was accepted")
    check(verdict("ghbdtn", .text(before: "xghbdtn ")) == .match, "only the deleted tail matters")
    check(verdict("ghbdtn", .text(before: "x ")) == .mismatch, "unrelated text")
    check(verdict("ghbdtn", .text(before: "ghbdtn")) == .retry, "the app has not handled the space yet")
    check(verdict("ghbdtn", .text(before: "ghb")) == .retry, "accessibility text lags behind typing")
    check(verdict("ghbdtn", .text(before: "ghbdtn"), final: true) == .match,
          "at the deadline an unchanged word without its space is deleted: the editor hides trailing spaces")
    check(verdict("ghbdtn", .text(before: "ghb"), final: true) == .mismatch, "at the deadline a lagging word is not")
    check(verdict("ghbdtn", .text(before: "ghb"), boundary: "", final: true) == .mismatch, "nor without a boundary")
    check(verdict("ghbdtn", .unavailable(transient: true)) == .retry, "a timeout is asked again")
    check(verdict("ghbdtn", .unavailable(transient: true), final: true) == .unknown, "until the deadline")
    check(verdict("ghbdtn", .unavailable(transient: false)) == .unknown, "no text field: correct as before")
    check(verdict("ghbdtn", .text(before: "")) == .retry, "nothing of the word shown yet")
    check(verdict("ghbdtn", .text(before: ""), final: true) == .unknown, "an empty field at the deadline is unreadable, not changed")
}

/// Types `ghbdtn ` with the field answering `replies`; returns the harness after the
/// correction was emitted or given up.
/// `emits`: whether a correction is expected (waited for up to 2 s; otherwise 0.4 s).
private func screenChecked(
    _ replies: FieldTextProbe...,
    emits: Bool,
    mode: ScreenCheckMode = .enforce,
    configure: (inout LearningHarness) -> Void = { _ in }
) -> LearningHarness {
    var harness = LearningHarness(screen: ScreenStub(replies: replies), screenCheckMode: mode)
    configure(&harness)
    harness.type("ghbdtn")
    _ = waitUntil(emits ? 2 : 0.4) { harness.emitted.count > 0 }
    return harness
}

run("screen check: corrects only what the field still shows") {
    var harness = screenChecked(.text(before: "old ghbdtn "), emits: true)
    check(harness.emitted.count == 1, "a matching field is corrected")
    check(harness.screen?.queries == 1, "one query, got \(harness.screen?.queries ?? -1)")
    check((harness.screen?.windows.first ?? 0) >= "ghbdtn ".utf16.count,
          "the window covers what is deleted, got \(harness.screen?.windows ?? [])")

    harness = screenChecked(.text(before: "Ghbdtn "), emits: true)
    check(harness.emitted.count == 1, "automatic capitalization keeps the length: corrected")

    harness = screenChecked(.selection(length: 5), emits: false)
    check(harness.emitted.count == 0, "an inline suggestion is selected: Backspace would delete it")
    check(harness.screen?.queries == 1, "a selection is decided at once, got \(harness.screen?.queries ?? -1)")

    harness = screenChecked(.text(before: "привет "), emits: false)
    check(harness.emitted.count == 0, "the field replaced the word (autocorrect, prediction)")
    check(harness.screen?.queries == 1, "a changed word is decided at once, got \(harness.screen?.queries ?? -1)")

    harness = screenChecked(.unavailable(transient: false), emits: true)
    check(harness.emitted.count == 1, "no readable field: corrected as before")
    check(harness.screen?.queries == 1, "without retries")
}

run("screen check: waits for a field that lags behind") {
    var harness = screenChecked(.text(before: "ghbdtn"), .text(before: "ghbdtn "), emits: true)
    check(harness.emitted.count == 1, "the space arrived on the second read")
    check(harness.screen?.queries == 2, "got \(harness.screen?.queries ?? -1)")

    harness = screenChecked(.unavailable(transient: true), .text(before: "ghbdtn "), emits: true)
    check(harness.emitted.count == 1, "a timeout is asked again")

    harness = screenChecked(.text(before: "ghbd"), emits: false)
    check(harness.emitted.count == 0, "a field that never catches up is not touched")
    check((harness.screen?.queries ?? 0) >= 2, "it was asked again before giving up")

    harness = screenChecked(.text(before: "ghbdtn"), emits: true)
    check(harness.emitted.count == 1, "the word without its space at the deadline: the editor hides trailing spaces")

    harness = screenChecked(.unavailable(transient: true), emits: true)
    check(harness.emitted.count == 1, "timeouts until the deadline: corrected as before")
}

run("screen check: typing during the check cancels it") {
    let harness = screenChecked(.text(before: "ghbdtn"), emits: false) { harness in
        let store = harness.store, engine = harness.engine
        harness.screen?.beforeFirstReply = {
            engine.enqueue(store.capture(
                timestamp: 99, kind: .character("x"), keyCode: 0, flagsRawValue: 0,
                isAutorepeat: false, sourcePID: 1, sourceUserData: 0
            ))
            let drained = DispatchSemaphore(value: 0)
            engine.drain { drained.signal() }
            _ = drained.wait(timeout: .now() + 1)
        }
    }
    check(harness.emitted.count == 0, "the next key makes the correction stale")
    check((harness.screen?.queries ?? 0) <= 1, "and stops the retries, got \(harness.screen?.queries ?? -1)")
}

run("screen check: shadow mode logs but corrects") {
    let harness = screenChecked(.selection(length: 5), emits: true, mode: .shadow)
    check(harness.emitted.count == 1, "shadow never cancels")
    check(harness.screen?.queries == 1, "but still reads the field")
    let off = screenChecked(.selection(length: 5), emits: true, mode: .off)
    check(off.emitted.count == 1 && off.screen?.queries == 0, "off does not read the field")
}

run("screen check: not asked when an earlier guard cancels") {
    var harness = LearningHarness(screen: ScreenStub(.text(before: "ghbdtn\n")))
    harness.type("ghbdtn", boundary: "\n")
    check(!waitUntil(0.3) { harness.emitted.count > 0 }, "Enter is never corrected")
    check(harness.screen?.queries == 0, "so the field is not read")
}

run("screen check: a merged short word is checked as a whole") {
    var harness = shortWordHarness(screen: ScreenStub(.text(before: "сейчас на ше\u{00A0}цщклы ")))
    harness.type("ше")
    harness.type("цщклы")
    check(waitUntil { harness.emitted.count == 1 }, "the pair is corrected")
    check((harness.screen?.windows.last ?? 0) >= "ше цщклы ".utf16.count,
          "the window covers both words, got \(harness.screen?.windows ?? [])")

    var changed = shortWordHarness(screen: ScreenStub(.text(before: "сейчас на ше цщклы! ")))
    changed.type("ше")
    changed.type("цщклы")
    check(!waitUntil(0.4) { changed.emitted.count > 0 }, "text inserted without a key event is not deleted")
}

run("screen check: the hotkey") {
    var harness = LearningHarness(screen: ScreenStub(.text(before: "ujnjdj")))
    harness.type("ujnjdj", boundary: nil)
    harness.send(.hotkey)
    check(waitUntil { harness.emitted.count == 1 }, "a buffered word the field shows is converted")
    check(harness.screen?.queries == 1, "after one check, got \(harness.screen?.queries ?? -1)")

    var cancelled = LearningHarness(screen: ScreenStub(.selection(length: 3)))
    cancelled.type("ujnjdj", boundary: nil)
    cancelled.send(.hotkey)
    check(!waitUntil(0.3) { cancelled.emitted.count > 0 }, "a selection after the caret cancels the hotkey too")

    var fromScreen = LearningHarness(screen: ScreenStub(.selection(length: 3)))
    fromScreen.caret.reply = .caret(textBefore: "ujnjdjk", startsAtTextStart: true, next: nil)
    fromScreen.selectAllAndDelete()
    fromScreen.type("ujnjdjk", boundary: nil)
    fromScreen.send(.hotkey)
    check(waitUntil { fromScreen.emitted.count == 1 }, "a word just read from the screen is converted")
    check(fromScreen.screen?.queries == 0, "without a second read")
}

if CommandLine.arguments.contains("--integration-smoke") {
    runIntegrationSmoke()
}

print("\nInput pipeline: \(passed) passed, \(failed) failed")
if failed > 0 {
    exit(1)
}
