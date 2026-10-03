import AppKit
import CoreGraphics
import Foundation
import os
import Utils

/// Why a correction happened; decides whether applying or reverting it teaches the
/// personal lexicon. Staleness checks (`isEligible`) never read it.
public enum CorrectionProvenance: Equatable, Sendable {
    /// Boundary-triggered automatic detection.
    case automatic
    /// Hotkey, and the detector itself recognized the word.
    case hotkey
    /// Hotkey converted a word the detector did not recognize.
    case hotkeyForced
    /// Selected text replaced via paste.
    case selection
    /// Correction on a system layout switch.
    case layoutSwitch
}

public struct CorrectionPlan: Equatable {
    public let boundarySequence: UInt64
    public let contextEpoch: UInt64
    public let targetPID: pid_t
    public let editGeneration: UInt64
    public let correctionEpoch: UInt64
    public let deleteCount: Int
    public let replacementText: String
    public let originalText: String
    public let correctedText: String
    public let boundaryText: String
    public let originalLayout: Layout
    public let targetLayout: Layout?
    public let provenance: CorrectionProvenance

    public init(
        boundarySequence: UInt64,
        contextEpoch: UInt64,
        targetPID: pid_t,
        editGeneration: UInt64,
        correctionEpoch: UInt64,
        deleteCount: Int,
        replacementText: String,
        originalText: String,
        correctedText: String,
        boundaryText: String,
        originalLayout: Layout,
        targetLayout: Layout?,
        provenance: CorrectionProvenance = .automatic
    ) {
        self.boundarySequence = boundarySequence
        self.contextEpoch = contextEpoch
        self.targetPID = targetPID
        self.editGeneration = editGeneration
        self.correctionEpoch = correctionEpoch
        self.deleteCount = deleteCount
        self.replacementText = replacementText
        self.originalText = originalText
        self.correctedText = correctedText
        self.boundaryText = boundaryText
        self.originalLayout = originalLayout
        self.targetLayout = targetLayout
        self.provenance = provenance
    }

    /// The same correction deleting `count` characters (the field changed what was typed).
    /// Undo still retypes `originalText` + boundary; a field may autocorrect it again, which
    /// gives back what it showed before the correction.
    public func deleting(_ count: Int) -> CorrectionPlan {
        CorrectionPlan(
            boundarySequence: boundarySequence,
            contextEpoch: contextEpoch,
            targetPID: targetPID,
            editGeneration: editGeneration,
            correctionEpoch: correctionEpoch,
            deleteCount: count,
            replacementText: replacementText,
            originalText: originalText,
            correctedText: correctedText,
            boundaryText: boundaryText,
            originalLayout: originalLayout,
            targetLayout: targetLayout,
            provenance: provenance
        )
    }

    public func isEligible(using state: CaptureStateSnapshot) -> Bool {
        state.latestPhysicalSequence == boundarySequence &&
            state.editGeneration == editGeneration &&
            state.correctionEpoch == correctionEpoch &&
            state.context.epoch == contextEpoch &&
            state.context.frontmostPID == targetPID &&
            state.context.appAllowed &&
            state.context.secureFocus == .notSecure &&
            state.correctionAllowed
    }
}

/// The revert of the last correction, prepared before its field-text check.
public struct RevertPlan: Equatable {
    /// The correction being reverted (what learning reads).
    public let recorded: CorrectionPlan
    /// Deletes `recorded.correctedText` + boundary and types `recorded.originalText` + boundary.
    public let inverse: CorrectionPlan
    /// Which recorded correction this is: the undo state may be replaced while the field is read.
    let undoID: UInt64

    /// The same revert deleting `count` characters (an inline suggestion follows the corrected text).
    func deleting(_ count: Int) -> RevertPlan {
        RevertPlan(recorded: recorded, inverse: inverse.deleting(count), undoID: undoID)
    }
}

public struct CorrectionEventDescriptor: Equatable {
    public enum Kind: Equatable {
        case deleteKeyDown
        case deleteKeyUp
        case unicodeKeyDown(String)
        case unicodeKeyUp(String)
    }

    public let kind: Kind
    public let sourceUserData: Int64
}

public final class TextCorrector {
    private struct UndoState {
        /// Kept by `rebaseUndoContext`; a new correction gets a new one.
        let id: UInt64
        let plan: CorrectionPlan
    }

    private let inputSourceManager: InputSourceManager
    private let eventSource: CGEventSource?
    private let undoState = OSAllocatedUnfairLock<UndoState?>(initialState: nil)
    private let lastUndoID = OSAllocatedUnfairLock<UInt64>(initialState: 0)
    /// The most recently queued layout switch: an older one still waiting on main is
    /// superseded (a revert queued before the correction's switch ran must win).
    private let lastLayoutSwitch = OSAllocatedUnfairLock<UInt64>(initialState: 0)
    private let logger = Logger(subsystem: "com.switchfix", category: "correction")

    public init(inputSourceManager: InputSourceManager = .shared) {
        self.inputSourceManager = inputSourceManager
        let source = CGEventSource(stateID: .privateState)
        source?.userData = switchFixEventMarker
        source?.localEventsSuppressionInterval = 0
        eventSource = source
    }

    public var canUndo: Bool {
        undoState.withLock { $0 != nil }
    }

    /// Makes `plan` the correction the revert hotkey undoes (`apply` and the selection paste
    /// call it; public for the pipeline tests, which replace posting).
    public func recordUndo(_ plan: CorrectionPlan) {
        let id = lastUndoID.withLock { value -> UInt64 in
            value &+= 1
            return value
        }
        undoState.withLock { $0 = UndoState(id: id, plan: plan) }
    }

    public static func isUndoEligible(
        recordedPlan: CorrectionPlan,
        sequence: UInt64,
        context: InputContextSnapshot,
        latest: CaptureStateSnapshot
    ) -> Bool {
        latest.latestPhysicalSequence == sequence &&
            latest.editGeneration == recordedPlan.editGeneration &&
            latest.correctionEpoch == recordedPlan.correctionEpoch &&
            latest.context.frontmostPID == recordedPlan.targetPID &&
            latest.context.frontmostPID == context.frontmostPID &&
            latest.context.epoch == recordedPlan.contextEpoch &&
            latest.context.appAllowed &&
            latest.context.secureFocus == .notSecure &&
            latest.correctionAllowed
    }

    /// Whether a layout switch queued on the main thread after `plan` reached the app may
    /// still run: the focus and app it was made for are unchanged and that app is still in
    /// front (`frontmostPID`, read on main). Typing after the correction does not cancel it:
    /// the next keys belong to the new layout.
    public static func mayFinishLayoutSwitch(
        for plan: CorrectionPlan,
        latest: CaptureStateSnapshot,
        frontmostPID: pid_t?
    ) -> Bool {
        frontmostPID == plan.targetPID &&
            latest.context.frontmostPID == plan.targetPID &&
            latest.context.epoch == plan.contextEpoch &&
            latest.context.appAllowed &&
            latest.context.secureFocus == .notSecure
    }

    /// Runs on the main thread (TIS APIs are main-thread-only).
    private func finishLayoutSwitch(
        to layout: Layout,
        after plan: CorrectionPlan,
        latestCaptureState: @escaping () -> CaptureStateSnapshot
    ) {
        let token = lastLayoutSwitch.withLock { value -> UInt64 in
            value &+= 1
            return value
        }
        DispatchQueue.main.async { [inputSourceManager, logger, lastLayoutSwitch] in
            // Every switch bumps the context epoch, so a newer queued switch would fail the
            // epoch check after this one ran: run only the newest.
            guard lastLayoutSwitch.withLock({ $0 }) == token else {
                logger.notice("layout switch skipped: superseded by a newer one")
                return
            }
            let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
            guard Self.mayFinishLayoutSwitch(for: plan, latest: latestCaptureState(), frontmostPID: frontmostPID) else {
                logger.notice("layout switch skipped: focus or app changed since the correction pid=\(plan.targetPID, privacy: .public) frontmost=\(frontmostPID ?? -1, privacy: .public)")
                return
            }
            inputSourceManager.switchTo(layout)
        }
    }

    public static func eventDescriptors(for plan: CorrectionPlan) -> [CorrectionEventDescriptor] {
        guard plan.deleteCount >= 0, plan.deleteCount <= 128, !plan.replacementText.isEmpty else {
            return []
        }
        var events: [CorrectionEventDescriptor] = []
        events.reserveCapacity(plan.deleteCount * 2 + plan.replacementText.count * 2)
        for _ in 0..<plan.deleteCount {
            events.append(CorrectionEventDescriptor(kind: .deleteKeyDown, sourceUserData: switchFixEventMarker))
            events.append(CorrectionEventDescriptor(kind: .deleteKeyUp, sourceUserData: switchFixEventMarker))
        }
        for char in plan.replacementText {
            let str = String(char)
            events.append(CorrectionEventDescriptor(
                kind: .unicodeKeyDown(str),
                sourceUserData: switchFixEventMarker
            ))
            events.append(CorrectionEventDescriptor(
                kind: .unicodeKeyUp(str),
                sourceUserData: switchFixEventMarker
            ))
        }
        return events
    }

    @discardableResult
    public func apply(
        _ plan: CorrectionPlan,
        latestCaptureState: @escaping () -> CaptureStateSnapshot
    ) -> Bool {
        guard plan.originalText.count <= 64,
              plan.deleteCount <= 128,
              let events = makeCorrectionEvents(plan: plan),
              plan.isEligible(using: latestCaptureState()) else {
            logger.debug("apply rejected \(SwitchFixLog.text(plan.originalText), privacy: .public) (oversized/no events/state changed)")
            return false
        }
        post(events, targetPID: plan.targetPID)

        recordUndo(plan)
        if let layout = plan.targetLayout,
           plan.isEligible(using: latestCaptureState()) {
            finishLayoutSwitch(to: layout, after: plan, latestCaptureState: latestCaptureState)
        }
        logger.notice(
            "correction APPLIED \(SwitchFixLog.text(plan.correctedText), privacy: .public) <- \(SwitchFixLog.text(plan.originalText), privacy: .public) deletes=\(plan.deleteCount) pid=\(plan.targetPID) layoutSwitch=\(plan.targetLayout?.rawValue ?? "none")"
        )
        return true
    }

    public func noteUserEdit(generation: UInt64) {
        undoState.withLock { value in
            guard let current = value else { return }
            if current.plan.editGeneration != generation {
                value = nil
            }
        }
    }

    public func clearUndo() {
        undoState.withLock { $0 = nil }
    }

    public func rebaseUndoContext(_ context: InputContextSnapshot, editGeneration: UInt64) {
        undoState.withLock { value in
            guard let current = value,
                  current.plan.targetPID == context.frontmostPID,
                  current.plan.editGeneration == editGeneration else {
                return
            }
            let plan = current.plan
            value = UndoState(id: current.id, plan: CorrectionPlan(
                boundarySequence: plan.boundarySequence,
                contextEpoch: context.epoch,
                targetPID: context.frontmostPID,
                editGeneration: plan.editGeneration,
                correctionEpoch: plan.correctionEpoch,
                deleteCount: plan.deleteCount,
                replacementText: plan.replacementText,
                originalText: plan.originalText,
                correctedText: plan.correctedText,
                boundaryText: plan.boundaryText,
                originalLayout: plan.originalLayout,
                targetLayout: plan.targetLayout,
                provenance: plan.provenance
            ))
        }
    }

    /// The inverse of `recorded`, built against the state at the revert hotkey. Its
    /// provenance stays `.automatic`: learning reads the recorded plan's.
    public static func inversePlan(
        of recorded: CorrectionPlan,
        sequence: UInt64,
        latest: CaptureStateSnapshot
    ) -> CorrectionPlan {
        CorrectionPlan(
            boundarySequence: sequence,
            contextEpoch: latest.context.epoch,
            targetPID: latest.context.frontmostPID,
            editGeneration: latest.editGeneration,
            correctionEpoch: latest.correctionEpoch,
            deleteCount: recorded.correctedText.count + recorded.boundaryText.count,
            replacementText: recorded.originalText + recorded.boundaryText,
            originalText: recorded.correctedText,
            correctedText: recorded.originalText,
            boundaryText: recorded.boundaryText,
            originalLayout: latest.context.layout,
            targetLayout: recorded.originalLayout
        )
    }

    /// The revert of the last correction when nothing changed since it; nil when there is
    /// none or it is stale (a stale one is forgotten). Posts nothing.
    public func prepareUndo(
        sequence: UInt64,
        context: InputContextSnapshot,
        latestCaptureState: () -> CaptureStateSnapshot
    ) -> RevertPlan? {
        guard let undo = undoState.withLock({ $0 }) else {
            logger.info("undo skipped: no recorded correction")
            return nil
        }
        let latest = latestCaptureState()
        guard Self.isUndoEligible(
            recordedPlan: undo.plan,
            sequence: sequence,
            context: context,
            latest: latest
        ) else {
            logger.info("undo skipped: state stale since correction \(SwitchFixLog.text(undo.plan.correctedText), privacy: .public)")
            discardUndo(id: undo.id)
            return nil
        }
        return RevertPlan(
            recorded: undo.plan,
            inverse: Self.inversePlan(of: undo.plan, sequence: sequence, latest: latest),
            undoID: undo.id
        )
    }

    /// `revert` against the undo state as it is now: a layout switch SwitchFix made after the
    /// correction rebases the recorded plan to the new context epoch (`rebaseUndoContext`),
    /// which would otherwise make a revert prepared before it look stale. Nil when the
    /// recorded correction changed or nothing may be reverted any more.
    public func refreshedRevert(_ revert: RevertPlan, latest: CaptureStateSnapshot) -> RevertPlan? {
        guard let current = undoState.withLock({ $0 }), current.id == revert.undoID else { return nil }
        let sequence = revert.inverse.boundarySequence
        guard Self.isUndoEligible(recordedPlan: current.plan, sequence: sequence, context: latest.context, latest: latest) else {
            return nil
        }
        return RevertPlan(
            recorded: current.plan,
            inverse: Self.inversePlan(of: current.plan, sequence: sequence, latest: latest),
            undoID: current.id
        )
    }

    /// Gives back a revert claimed by `takeUndo` that was not posted, unless another
    /// correction was recorded since.
    public func restoreUndo(_ revert: RevertPlan) {
        undoState.withLock { value in
            if value == nil { value = UndoState(id: revert.undoID, plan: revert.recorded) }
        }
    }

    /// Claims `revert` for posting: true only while it is still the recorded correction,
    /// which is then forgotten so the same revert cannot be applied twice.
    public func takeUndo(_ revert: RevertPlan) -> Bool {
        undoState.withLock { value in
            guard value?.id == revert.undoID else { return false }
            value = nil
            return true
        }
    }

    /// Forgets `revert` (the field no longer shows it) unless another correction replaced it.
    public func discardUndo(_ revert: RevertPlan) {
        discardUndo(id: revert.undoID)
    }

    private func discardUndo(id: UInt64) {
        undoState.withLock { value in
            if value?.id == id { value = nil }
        }
    }

    /// Posts a revert claimed by `takeUndo` and switches back to the original layout.
    @discardableResult
    public func postUndo(
        _ revert: RevertPlan,
        latestCaptureState: @escaping () -> CaptureStateSnapshot
    ) -> Bool {
        let inverse = revert.inverse
        guard let events = makeCorrectionEvents(plan: inverse),
              inverse.isEligible(using: latestCaptureState()) else {
            logger.debug("undo rejected: could not build inverse events or state changed")
            return false
        }
        post(events, targetPID: inverse.targetPID)
        logger.notice(
            "revert APPLIED \(SwitchFixLog.text(inverse.correctedText), privacy: .public) <- \(SwitchFixLog.text(inverse.originalText), privacy: .public) deletes=\(inverse.deleteCount) pid=\(inverse.targetPID)"
        )
        if inverse.isEligible(using: latestCaptureState()) {
            finishLayoutSwitch(to: revert.recorded.originalLayout, after: inverse, latestCaptureState: latestCaptureState)
        }
        return true
    }

    public func performSelectionCorrection(
        selectedText: String,
        convertedText: String,
        targetLayout: Layout,
        shouldSwitchLayout: Bool,
        originalLayout: Layout,
        sequence: UInt64,
        context: InputContextSnapshot,
        editGeneration: UInt64,
        correctionEpoch: UInt64,
        latestCaptureState: @escaping () -> CaptureStateSnapshot
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let latest = latestCaptureState()
            guard latest.latestPhysicalSequence == sequence,
                  latest.editGeneration == editGeneration,
                  latest.correctionEpoch == correctionEpoch,
                  latest.context.epoch == context.epoch,
                  latest.context.frontmostPID == context.frontmostPID,
                  latest.context.secureFocus == .notSecure,
                  latest.context.appAllowed,
                  latest.correctionAllowed,
                  // Cmd+V goes to the process; the pasteboard trick is only for the app in front.
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == context.frontmostPID else {
                logger.debug("selection correction skipped: state changed before paste")
                return
            }

            logger.notice(
                "selection paste \(SwitchFixLog.text(convertedText), privacy: .public) <- \(SwitchFixLog.text(selectedText), privacy: .public) pid=\(context.frontmostPID) layoutSwitch=\(shouldSwitchLayout ? targetLayout.rawValue : "none")"
            )
            let pasteboard = NSPasteboard.general
            // Snapshot item data into fresh items: items read from a pasteboard are
            // invalidated by clearContents() and cannot be written back.
            let previousItems: [NSPasteboardItem] = (pasteboard.pasteboardItems ?? []).map { item in
                let copy = NSPasteboardItem()
                for type in item.types {
                    if let data = item.data(forType: type) {
                        copy.setData(data, forType: type)
                    }
                }
                return copy
            }
            pasteboard.clearContents()
            pasteboard.setString(convertedText, forType: .string)
            let replacementChangeCount = pasteboard.changeCount
            self.postPaste(targetPID: context.frontmostPID)
            let afterPaste = latestCaptureState()
            if shouldSwitchLayout,
               afterPaste.latestPhysicalSequence == sequence,
               afterPaste.editGeneration == editGeneration,
               afterPaste.correctionEpoch == correctionEpoch,
               afterPaste.correctionAllowed,
               afterPaste.context == context,
               NSWorkspace.shared.frontmostApplication?.processIdentifier == context.frontmostPID {
                self.inputSourceManager.switchTo(targetLayout)
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                guard pasteboard.changeCount == replacementChangeCount else { return }
                pasteboard.clearContents()
                if !previousItems.isEmpty {
                    pasteboard.writeObjects(previousItems)
                }
            }

            let plan = CorrectionPlan(
                boundarySequence: sequence,
                contextEpoch: context.epoch,
                targetPID: context.frontmostPID,
                editGeneration: editGeneration,
                correctionEpoch: correctionEpoch,
                deleteCount: selectedText.count,
                replacementText: convertedText,
                originalText: selectedText,
                correctedText: convertedText,
                boundaryText: "",
                originalLayout: originalLayout,
                targetLayout: shouldSwitchLayout ? targetLayout : nil,
                provenance: .selection
            )
            let finalState = latestCaptureState()
            if finalState.editGeneration == editGeneration,
               finalState.correctionEpoch == correctionEpoch,
               finalState.correctionAllowed {
                self.recordUndo(plan)
            }
        }
    }

    private func makeCorrectionEvents(plan: CorrectionPlan) -> [CGEvent]? {
        guard eventSource != nil, !plan.replacementText.isEmpty else { return nil }
        var events: [CGEvent] = []
        events.reserveCapacity(plan.deleteCount * 2 + plan.replacementText.count * 2)
        for _ in 0..<plan.deleteCount {
            guard let keyDown = makeKeyEvent(keyCode: 51, keyDown: true),
                  let keyUp = makeKeyEvent(keyCode: 51, keyDown: false) else {
                return nil
            }
            events.append(keyDown)
            events.append(keyUp)
        }

        for char in plan.replacementText {
            let str = String(char)
            guard let keyDown = makeUnicodeEvent(text: str, keyDown: true),
                  let keyUp = makeUnicodeEvent(text: str, keyDown: false) else {
                return nil
            }
            events.append(keyDown)
            events.append(keyUp)
        }
        return events
    }

    private func post(_ events: [CGEvent], targetPID: pid_t) {
        // Some toolkits (e.g. Qt in Telegram) drop Unicode-string events posted
        // straight to the process; per-app override routes them through the system
        // event stream instead. Read on every correction so settings apply immediately.
        let bundleID = NSRunningApplication(processIdentifier: targetPID)?.bundleIdentifier
        let modes = AppPostMode.overrides()
        let tap: CGEventTapLocation?
        switch bundleID.flatMap({ modes[$0] }) {
        case .session: tap = .cgSessionEventTap
        case .hid: tap = .cghidEventTap
        case nil: tap = nil
        }
        for event in events {
            if let tap {
                event.post(tap: tap)
                continue
            }
            event.postToPid(targetPID)
        }
    }

    private func makeKeyEvent(keyCode: UInt16, keyDown: Bool) -> CGEvent? {
        guard let event = CGEvent(keyboardEventSource: eventSource, virtualKey: keyCode, keyDown: keyDown) else {
            return nil
        }
        // A modifier-tap hotkey fires on release, and these events can reach the app
        // before that release does: without explicit flags Chromium sees Option held
        // and turns Backspace into delete-word.
        event.flags = []
        event.setIntegerValueField(.eventSourceUserData, value: switchFixEventMarker)
        return event
    }

    private func makeUnicodeEvent(text: String, keyDown: Bool) -> CGEvent? {
        guard let event = makeKeyEvent(keyCode: 0, keyDown: keyDown) else { return nil }
        let utf16 = Array(text.utf16)
        utf16.withUnsafeBufferPointer { buffer in
            event.keyboardSetUnicodeString(
                stringLength: buffer.count,
                unicodeString: buffer.baseAddress
            )
        }
        return event
    }

    private func postPaste(targetPID: pid_t) {
        guard let keyDown = makeKeyEvent(keyCode: 9, keyDown: true),
              let keyUp = makeKeyEvent(keyCode: 9, keyDown: false) else {
            return
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.postToPid(targetPID)
        keyUp.postToPid(targetPID)
    }
}
