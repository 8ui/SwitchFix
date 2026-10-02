import Foundation
import os
import Utils

public struct DetectionRequest: Equatable {
    public let word: String
    public let boundary: String
    public let sequence: UInt64
    public let editGeneration: UInt64
    public let correctionEpoch: UInt64
    public let context: InputContextSnapshot
    /// See `InputStateCommand.flush`; false for hotkey requests.
    public let continuesPreviousWord: Bool
    /// The word was just read from the screen before the caret: no second field-text check.
    public let screenVerified: Bool
    /// The field-text check must see the word: an unreadable field cancels instead of
    /// failing open (a word read after a bare caret move, which nothing typed confirms).
    public let requiresScreenMatch: Bool

    public init(
        word: String,
        boundary: String,
        sequence: UInt64,
        editGeneration: UInt64,
        correctionEpoch: UInt64,
        context: InputContextSnapshot,
        continuesPreviousWord: Bool = false,
        screenVerified: Bool = false,
        requiresScreenMatch: Bool = false
    ) {
        self.word = word
        self.boundary = boundary
        self.sequence = sequence
        self.editGeneration = editGeneration
        self.correctionEpoch = correctionEpoch
        self.context = context
        self.continuesPreviousWord = continuesPreviousWord
        self.screenVerified = screenVerified
        self.requiresScreenMatch = requiresScreenMatch
    }
}

public final class InputEngine {
    public typealias ExactDetection = (DetectionRequest) -> DetectionResult?
    public typealias CorrectionEmission = (CorrectionPlan) -> Bool
    public typealias SelectedTextRequest = (pid_t, UInt64, @escaping (String?) -> Void) -> Void
    /// Selection or, when `wantsCaretText`, text around the caret (Accessibility); used by
    /// the manual hotkey. Without `wantsCaretText` only the selection is read.
    public typealias CaretContextRequest = (pid_t, UInt64, Bool, @escaping (CaretContext) -> Void) -> Void
    /// The focused field's text before the caret (pid, epoch, window in UTF-16 units), read
    /// before a correction or a revert deletes; the completion may run on any queue.
    public typealias ScreenTextRequest = (pid_t, UInt64, Int, @escaping (FieldTextProbe) -> Void) -> Void
    /// Posts a revert claimed from the corrector; returns whether it reached the app (tests
    /// replace `TextCorrector.postUndo`).
    public typealias RevertEmission = (RevertPlan) -> Bool

    public var onFocusMayChange: ((pid_t, UInt64) -> Void)?

    private struct DetectionConfiguration {
        var allowedLayouts = Set(Layout.allCases)
        var keyboardTables: KeyboardTables = .pc
        var thresholds: DetectionThresholds = .default
    }

    private let inputQueue = DispatchQueue(label: "com.switchfix.input-engine", qos: .userInteractive)
    private let detectionQueue = DispatchQueue(label: "com.switchfix.detection", qos: .userInitiated)
    private let correctionQueue = DispatchQueue(label: "com.switchfix.correction", qos: .userInteractive)
    private let selectionQueue = DispatchQueue(label: "com.switchfix.selection", qos: .userInitiated)
    private let captureState: CaptureStateStore
    private var stateMachine: InputStateMachine
    private let detector: LayoutDetector
    private let corrector: TextCorrector
    private let customDetection: ExactDetection?
    private let customEmission: CorrectionEmission?
    private let selectedTextRequest: SelectedTextRequest?
    private let caretContextRequest: CaretContextRequest?
    private let screenTextRequest: ScreenTextRequest?
    private let screenCheckMode: ScreenCheckMode
    private let readsScreenAfterCaretMove: ((pid_t) -> Bool)?
    private let revertEmission: RevertEmission?
    private let lexicon: PersonalLexicon?
    private let detectionConfiguration = OSAllocatedUnfairLock(initialState: DetectionConfiguration())
    private var correctionEpoch: UInt64
    private var latestProcessedSequence: UInt64 = 0
    /// Uptime when the last caret move (a click, an arrow key) was processed.
    private var caretMoveUptime: UInt64 = 0
    /// Uptime when the state machine set aside a word at a Globe press.
    private var layoutSwitchWordUptime: UInt64 = 0
    /// A switch notification later than this is not the Globe press's: Globe may
    /// have started dictation and the layout changed by an uncaptured path.
    static let layoutSwitchWordLifetimeNanoseconds: UInt64 = 500_000_000
    /// How long a correction waits for the field to show the typed text before deciding.
    /// Soft: checked when an answer arrives, and one read of a busy app can take ~250 ms.
    static let screenCheckDeadlineNanoseconds: UInt64 = 150_000_000
    static let screenCheckRetryInterval: DispatchTimeInterval = .milliseconds(20)
    /// How long after a caret move the hotkey waits before reading the word before the caret:
    /// Accessibility (Chromium) may still report the previous caret position.
    static let caretSettleNanoseconds: UInt64 = 200_000_000
    private var maximumQueueDepth = 0
    private let logger = Logger(subsystem: "com.switchfix", category: "input-engine")

    public init(
        captureState: CaptureStateStore,
        initialContext: InputContextSnapshot,
        preferences: InputPreferencesSnapshot,
        detector: LayoutDetector = LayoutDetector(),
        corrector: TextCorrector = TextCorrector(),
        exactDetection: ExactDetection? = nil,
        correctionEmission: CorrectionEmission? = nil,
        selectedTextRequest: SelectedTextRequest? = nil,
        caretContextRequest: CaretContextRequest? = nil,
        screenTextRequest: ScreenTextRequest? = nil,
        screenCheckMode: ScreenCheckMode = .enforce,
        readsScreenAfterCaretMove: ((pid_t) -> Bool)? = nil,
        lexicon: PersonalLexicon? = nil,
        revertEmission: RevertEmission? = nil
    ) {
        self.captureState = captureState
        self.stateMachine = InputStateMachine(context: initialContext, preferences: preferences)
        self.detector = detector
        self.corrector = corrector
        self.customDetection = exactDetection
        self.customEmission = correctionEmission
        self.selectedTextRequest = selectedTextRequest
        self.caretContextRequest = caretContextRequest
        self.screenTextRequest = screenCheckMode == .off ? nil : screenTextRequest
        self.screenCheckMode = screenCheckMode
        self.readsScreenAfterCaretMove = readsScreenAfterCaretMove
        self.lexicon = lexicon
        self.revertEmission = revertEmission
        detector.lexicon = lexicon
        correctionEpoch = captureState.updateCorrectionEnabled(preferences.isEnabled)
    }

    public func enqueue(_ input: CapturedInput) {
        guard input.sourceUserData != switchFixEventMarker else { return }
        switch captureState.reserveEnqueue(for: input) {
        case .drop:
            return
        case .enqueue(let reservedInput):
            let depth = captureState.snapshot().pendingInputCount
            inputQueue.async { [weak self] in
                guard let self else { return }
                defer { self.captureState.completeEnqueue() }
                self.maximumQueueDepth = max(self.maximumQueueDepth, depth)
                self.process(reservedInput)
            }
        }
    }

    public func updateContext(_ context: InputContextSnapshot) {
        inputQueue.async { [weak self] in
            _ = self?.stateMachine.updateContext(context)
            self?.resetDetectorState()
        }
    }

    /// Focus resolution for the current epoch (see `InputStateMachine.focusResolved`).
    public func focusResolved(_ context: InputContextSnapshot) {
        inputQueue.async { [weak self] in
            _ = self?.stateMachine.focusResolved(context)
            self?.resetDetectorState()
        }
    }

    /// The focused element changed in the same app (see `InputStateMachine.focusMoved`).
    public func focusMoved(_ context: InputContextSnapshot) {
        inputQueue.async { [weak self] in
            guard let self else { return }
            _ = self.stateMachine.focusMoved(context)
            // The new field may still be settling: count from the focus move.
            if self.stateMachine.hasPlacedCaret {
                self.caretMoveUptime = DispatchTime.now().uptimeNanoseconds
            }
            self.resetDetectorState()
        }
    }

    public func updatePreferences(_ preferences: InputPreferencesSnapshot) {
        let correctionEpoch = captureState.updateCorrectionEnabled(preferences.isEnabled)
        inputQueue.async { [weak self] in
            guard let self else { return }
            self.correctionEpoch = correctionEpoch
            if !self.stateMachine.updatePreferences(preferences).isEmpty {
                self.resetDetectorState()
            }
        }
    }

    public func handleGeneratedLayoutContext(_ context: InputContextSnapshot) {
        let generation = captureState.snapshot().editGeneration
        inputQueue.async { [weak self] in
            _ = self?.stateMachine.updateContext(context)
            self?.resetDetectorState()
        }
        correctionQueue.async { [weak self] in
            self?.corrector.rebaseUndoContext(context, editGeneration: generation)
        }
    }

    public func handleLayoutChange(
        from oldLayout: Layout,
        to newLayout: Layout,
        context: InputContextSnapshot,
        keyboardTables: KeyboardTables
    ) {
        inputQueue.async { [weak self] in
            guard let self else { return }
            let switchWordAge = DispatchTime.now().uptimeNanoseconds &- self.layoutSwitchWordUptime
            let bufferedWord = self.stateMachine.layoutSwitchWord.isEmpty
                ? self.stateMachine.currentBuffer
                : switchWordAge <= Self.layoutSwitchWordLifetimeNanoseconds ? self.stateMachine.layoutSwitchWord : ""
            let preferences = self.stateMachine.preferences
            _ = self.stateMachine.updateContext(context)
            self.resetDetectorState()
            guard preferences.isEnabled,
                  preferences.correctionMode == .layoutSwitch,
                  context.appAllowed,
                  context.secureFocus == .notSecure,
                  oldLayout != newLayout else {
                return
            }

            let latest = self.captureState.snapshot()
            let requestCorrectionEpoch = self.correctionEpoch
            let applyBufferedCorrection = {
                guard self.latestProcessedSequence == latest.latestPhysicalSequence,
                      !bufferedWord.isEmpty,
                      bufferedWord.count <= 64 else { return }
                let converted = LayoutMapper.convert(
                    bufferedWord,
                    from: oldLayout,
                    to: newLayout,
                    tables: keyboardTables
                )
                guard converted != bufferedWord else { return }
                let result = DetectionResult(
                    sourceLayout: oldLayout,
                    targetLayout: newLayout,
                    convertedWord: converted,
                    originalWord: bufferedWord,
                    shouldSwitchLayout: false
                )
                self.prepareCorrection(
                    result: result,
                    request: DetectionRequest(
                        word: bufferedWord,
                        boundary: "",
                        sequence: latest.latestPhysicalSequence,
                        editGeneration: latest.editGeneration,
                        correctionEpoch: requestCorrectionEpoch,
                        context: context
                    ),
                    provenance: .layoutSwitch
                )
            }

            guard let selectedTextRequest = self.selectedTextRequest else {
                applyBufferedCorrection()
                return
            }
            self.selectionQueue.async {
                selectedTextRequest(context.frontmostPID, context.epoch) { [weak self] selectedText in
                    guard let self else { return }
                    self.inputQueue.async {
                        let current = self.captureState.snapshot()
                        guard current.latestPhysicalSequence == latest.latestPhysicalSequence,
                              current.editGeneration == latest.editGeneration,
                              current.correctionEpoch == requestCorrectionEpoch,
                              current.context == context else {
                            return
                        }
                        if let selectedText, !selectedText.isEmpty {
                            guard ScriptAnalyzer.containsScript(for: oldLayout, in: selectedText) else {
                                return
                            }
                            let converted = LayoutMapper.convert(
                                selectedText,
                                from: oldLayout,
                                to: newLayout,
                                tables: keyboardTables
                            )
                            guard converted != selectedText else { return }
                            self.corrector.performSelectionCorrection(
                                selectedText: selectedText,
                                convertedText: converted,
                                targetLayout: newLayout,
                                shouldSwitchLayout: false,
                                originalLayout: oldLayout,
                                sequence: latest.latestPhysicalSequence,
                                context: context,
                                editGeneration: latest.editGeneration,
                                correctionEpoch: requestCorrectionEpoch,
                                latestCaptureState: self.captureState.snapshot
                            )
                        } else {
                            applyBufferedCorrection()
                        }
                    }
                }
            }
        }
    }

    public func updateDetectionConfiguration(
        allowedLayouts: Set<Layout>,
        keyboardTables: KeyboardTables = .pc,
        thresholds: DetectionThresholds = .default
    ) {
        detectionConfiguration.withLock { value in
            value.allowedLayouts = allowedLayouts
            value.keyboardTables = keyboardTables
            value.thresholds = thresholds
        }
    }

    public func drain(completion: @escaping () -> Void) {
        inputQueue.async { completion() }
    }

    /// Runs `completion` once queued detections, the input work they posted and the detector
    /// work that posted in turn are done (tests: a not-applied report reaches the detector).
    public func drainDetection(completion: @escaping () -> Void) {
        detectionQueue.async { [weak self] in
            guard let self else { return completion() }
            self.inputQueue.async {
                self.detectionQueue.async { completion() }
            }
        }
    }

    public func inspectState(
        completion: @escaping (_ buffer: String, _ invalidUntilBoundary: Bool, _ sequence: UInt64) -> Void
    ) {
        inputQueue.async { [weak self] in
            guard let self else { return }
            completion(
                self.stateMachine.currentBuffer,
                self.stateMachine.isInvalidUntilBoundary,
                self.latestProcessedSequence
            )
        }
    }

    /// The key code of a typed character identifies the character, so it is logged only
    /// with the text itself.
    private static func logDescription(_ input: CapturedInput) -> String {
        if !SwitchFixLog.logsTypedText {
            switch input.kind {
            case .character(let text): return "character(\(SwitchFixLog.text(text)))"
            case .boundary(let text): return "boundary(\(SwitchFixLog.text(text)))"
            default: break
            }
        }
        return "\(input.kind) keyCode=\(input.keyCode)"
    }

    private func process(_ input: CapturedInput) {
        latestProcessedSequence = input.sequence
        logger.debug("input seq=\(input.sequence) kind=\(Self.logDescription(input), privacy: .public) autorepeat=\(input.isAutorepeat) srcPid=\(input.sourcePID)")

        if input.kind.recordsUserEdit {
            correctionQueue.async { [weak self] in
                self?.corrector.noteUserEdit(generation: input.editGeneration)
            }
        }

        let liveContext = captureState.snapshot().context
        guard input.context == liveContext else {
            _ = stateMachine.updateContext(liveContext)
            // The dropped event may have reached the app; don't let a partial
            // word buffer up and get "corrected" with a wrong delete count.
            stateMachine.invalidateUntilBoundary()
            resetDetectorState()
            logger.debug("buffer invalidated reason=stale-capture-context captured=\(String(describing: input.context)) live=\(String(describing: liveContext))")
            return
        }

        if input.kind.invalidatesCaptureContext,
           input.context.epoch >= stateMachine.context.epoch {
            _ = stateMachine.updateContext(input.context)
            onFocusMayChange?(input.context.frontmostPID, input.context.epoch)
        }

        if case .caretMove = input.kind {
            caretMoveUptime = DispatchTime.now().uptimeNanoseconds
        }
        for command in stateMachine.consume(input) {
            handle(command)
        }
        if !stateMachine.layoutSwitchWord.isEmpty {
            layoutSwitchWordUptime = DispatchTime.now().uptimeNanoseconds
        }
    }

    private func handle(_ command: InputStateCommand) {
        switch command {
        case .append(let text):
            logger.debug("buffer \(SwitchFixLog.text(self.stateMachine.currentBuffer), privacy: .public) (+ \(SwitchFixLog.text(text), privacy: .public))")
        case .deleteLast:
            logger.debug("buffer \(SwitchFixLog.text(self.stateMachine.currentBuffer), privacy: .public) (backspace)")
        case .invalidate(let reason):
            resetDetectorState()
            logger.debug("buffer invalidated reason=\(String(describing: reason))")
        case .flush(let word, let boundary, let sequence, let context, let continuesPreviousWord):
            logger.notice("word flushed \(SwitchFixLog.text(word), privacy: .public) boundary=\(SwitchFixLog.text(boundary), privacy: .public) seq=\(sequence) layout=\(context.layout.rawValue)")
            let latest = captureState.snapshot()
            runDetection(DetectionRequest(
                word: word,
                boundary: boundary,
                sequence: sequence,
                editGeneration: latest.editGeneration,
                correctionEpoch: correctionEpoch,
                context: context,
                continuesPreviousWord: continuesPreviousWord
            ))
        case .requestManualCorrection(let word, let screenSuffix, let sequence, let context):
            logger.notice("hotkey correction requested word=\(SwitchFixLog.text(word), privacy: .public) seq=\(sequence)")
            requestManualCorrection(word: word, screenSuffix: screenSuffix, sequence: sequence, context: context)
        case .requestRevert(let word, let sequence, let context):
            logger.notice("revert hotkey pressed word=\(SwitchFixLog.text(word), privacy: .public) seq=\(sequence)")
            correctionQueue.async { [weak self] in
                guard let self else { return }
                guard let revert = self.corrector.prepareUndo(
                    sequence: sequence,
                    context: context,
                    latestCaptureState: self.captureState.snapshot
                ) else {
                    self.inputQueue.async {
                        // Nothing to revert: convert instead, but the user asked to reject,
                        // so this conversion must not teach "always correct".
                        // Nor read a word from the screen: the default revert key is Caps Lock,
                        // pressed to type capitals, not to convert the word before the caret.
                        self.requestManualCorrection(
                            word: word,
                            screenSuffix: nil,
                            sequence: sequence,
                            context: context,
                            teaches: false
                        )
                    }
                    return
                }
                guard let screenTextRequest = self.screenTextRequest else {
                    self.applyRevert(revert)
                    return
                }
                // A revert the field refuses is not turned into a conversion: it would be one
                // more change to text the field shows differently.
                let inverse = revert.inverse
                let check = ScreenCheck(
                    kind: .revert,
                    word: inverse.originalText,
                    boundary: inverse.boundaryText,
                    pid: inverse.targetPID,
                    epoch: inverse.contextEpoch,
                    provenance: revert.recorded.provenance,
                    acceptsReplacement: false,
                    retriesMismatch: true,
                    requiresMatch: false,
                    isCurrent: { [weak self] in
                        guard let self else { return false }
                        return self.corrector.refreshedRevert(revert, latest: self.captureState.snapshot()) != nil
                    },
                    proceed: { [weak self] _ in
                        self?.correctionQueue.async { self?.applyRevert(revert) }
                    },
                    reject: { [weak self] in
                        // The field no longer shows the corrected text: a later revert cannot be right.
                        self?.corrector.discardUndo(revert)
                    },
                    cancelled: {}
                )
                self.inputQueue.async { [weak self] in
                    self?.verifyScreen(
                        check,
                        query: screenTextRequest,
                        startedAt: DispatchTime.now().uptimeNanoseconds,
                        attempt: 1
                    )
                }
            }
        case .nativeUndo:
            correctionQueue.async { [weak self] in
                self?.corrector.clearUndo()
            }
        }
    }

    /// - Parameter teaches: whether a forced conversion may teach the personal lexicon.
    private func runDetection(_ request: DetectionRequest, forceConversion: Bool = false, teaches: Bool = true) {
        detectionQueue.async { [weak self] in
            guard let self else { return }
            let startedAt = DispatchTime.now().uptimeNanoseconds
            var result: DetectionResult?
            var provenance: CorrectionProvenance = forceConversion ? .hotkey : .automatic
            if let customDetection = self.customDetection {
                result = customDetection(request)
            } else {
                let configuration = self.detectionConfiguration.withLock { $0 }
                self.detector.currentLayout = request.context.layout
                self.detector.allowedLayouts = configuration.allowedLayouts
                self.detector.keyboardTables = configuration.keyboardTables
                self.detector.thresholds = configuration.thresholds
                self.detector.discardBuffer()
                self.detector.addCharacter(request.word)
                result = self.detector.flushBuffer(
                    boundaryCharacter: request.boundary.isEmpty ? nil : request.boundary,
                    continuesPreviousWord: request.continuesPreviousWord
                )
                let detectorResult = result
                // Manual hotkey = explicit user intent: convert even when the
                // model does not recognize the word (typos, rare words).
                // The source layout comes from the word's script, not the current input
                // source: the two can differ (e.g. Cyrillic word, English layout active).
                let sourceLayout = ScriptAnalyzer.resolvedSourceLayout(
                    for: request.word,
                    currentLayout: request.context.layout,
                    allowedLayouts: configuration.allowedLayouts
                )
                let alternatives = forceConversion && result == nil
                    ? LayoutMapper.convertToAlternatives(
                        request.word,
                        from: sourceLayout,
                        tables: configuration.keyboardTables
                    ).filter { $0.1 != request.word }
                    : []
                if forceConversion, result == nil {
                    SwitchFixLog.engine.notice(
                        "force: source=\(sourceLayout.rawValue) current=\(request.context.layout.rawValue) allowed=\(configuration.allowedLayouts.map(\.rawValue).sorted()) alternatives=\(alternatives.map { $0.0.rawValue })"
                    )
                }
                // Prefer the Cyrillic layout typed on last, then any installed layout,
                // then any conversion.
                // (only for Latin words: a Cyrillic word must never go Russian ↔ Ukrainian).
                let preferred = sourceLayout == .english ? self.detector.preferredCyrillicLayout : nil
                let allowed = configuration.allowedLayouts
                if detectorResult == nil,
                   let (target, converted) = alternatives.first(where: { $0.0 == preferred && allowed.contains($0.0) })
                    ?? alternatives.first(where: { allowed.contains($0.0) })
                    ?? alternatives.first {
                    result = DetectionResult(
                        sourceLayout: sourceLayout,
                        targetLayout: target,
                        convertedWord: converted,
                        originalWord: request.word,
                        shouldSwitchLayout: true
                    )
                    provenance = teaches ? .hotkeyForced : .hotkey
                }
            }
            let duration = DispatchTime.now().uptimeNanoseconds &- startedAt
            if let result {
                SwitchFixLog.detector.notice(
                    "detect \(SwitchFixLog.text(result.originalWord)) -> \(SwitchFixLog.text(result.convertedWord)) source=\(result.sourceLayout.rawValue) target=\(result.targetLayout.rawValue) switch=\(result.shouldSwitchLayout) ms=\(Double(duration) / 1_000_000.0)"
                )
            } else {
                SwitchFixLog.detector.info(
                    "detect \(SwitchFixLog.text(request.word)) -> keep (no correction, ms=\(Double(duration) / 1_000_000.0))"
                )
            }
            guard let result else { return }
            let resultProvenance = provenance
            self.inputQueue.async {
                self.prepareCorrection(result: result, request: request, provenance: resultProvenance)
            }
        }
    }

    private func prepareCorrection(
        result: DetectionResult,
        request: DetectionRequest,
        provenance: CorrectionProvenance
    ) {
        let latest = captureState.snapshot()
        var cancelReason: String?
        if latest.latestPhysicalSequence != request.sequence {
            cancelReason = "stale-sequence"
        } else if latest.editGeneration != request.editGeneration {
            cancelReason = "edit-generation-changed"
        } else if latest.correctionEpoch != request.correctionEpoch {
            cancelReason = "correction-epoch-changed"
        } else if latest.context != request.context {
            cancelReason = "context-changed"
        } else if latest.context.secureFocus != .notSecure {
            cancelReason = "secure-focus"
        } else if !latest.context.appAllowed {
            cancelReason = "app-not-allowed"
        } else if !latest.correctionAllowed {
            cancelReason = "correction-disallowed"
        } else if result.originalWord.count > 64 {
            cancelReason = "word-too-long"
        } else if request.boundary.contains("\n") {
            // Enter has already submitted the text in chats and terminals: deleting now
            // erases the wrong thing and retyping the newline would submit it again.
            cancelReason = "word-ended-by-enter"
        }
        guard cancelReason == nil else {
            noteNotApplied(result.detectionID)
            SwitchFixLog.engine.notice("correction cancelled reason=\(cancelReason!)")
            logger.debug("correction cancelled reason=\(cancelReason!) word=\(SwitchFixLog.text(result.originalWord), privacy: .public)")
            return
        }

        let boundary = request.boundary
        logger.notice(
            "correction planned \(SwitchFixLog.text(result.originalWord), privacy: .public) -> \(SwitchFixLog.text(result.convertedWord), privacy: .public) deletes=\(result.originalWord.count + boundary.count) pid=\(request.context.frontmostPID)"
        )
        let plan = CorrectionPlan(
            boundarySequence: request.sequence,
            contextEpoch: request.context.epoch,
            targetPID: request.context.frontmostPID,
            editGeneration: request.editGeneration,
            correctionEpoch: request.correctionEpoch,
            deleteCount: result.originalWord.count + boundary.count,
            replacementText: result.convertedWord + boundary,
            originalText: result.originalWord,
            correctedText: result.convertedWord,
            boundaryText: boundary,
            originalLayout: result.sourceLayout,
            targetLayout: result.shouldSwitchLayout ? result.targetLayout : nil,
            provenance: provenance
        )

        if let screenTextRequest, !request.screenVerified {
            let check = ScreenCheck(
                kind: .correction,
                word: plan.originalText,
                boundary: plan.boundaryText,
                pid: request.context.frontmostPID,
                epoch: request.context.epoch,
                provenance: plan.provenance,
                acceptsReplacement: true,
                retriesMismatch: false,
                requiresMatch: request.requiresScreenMatch,
                isCurrent: { [weak self] in self?.isCurrent(request) ?? false },
                proceed: { [weak self] deleteCount in
                    self?.emit(deleteCount.map(plan.deleting) ?? plan, detectionID: result.detectionID)
                },
                reject: {},
                cancelled: { [weak self] in self?.noteNotApplied(result.detectionID) }
            )
            verifyScreen(
                check,
                query: screenTextRequest,
                startedAt: DispatchTime.now().uptimeNanoseconds,
                attempt: 1
            )
        } else {
            emit(plan, detectionID: result.detectionID)
        }
    }

    /// Whether nothing changed since `request` was captured (runs on the input queue).
    private func isCurrent(_ request: DetectionRequest) -> Bool {
        let latest = captureState.snapshot()
        return latest.latestPhysicalSequence == request.sequence
            && latest.editGeneration == request.editGeneration
            && latest.correctionEpoch == request.correctionEpoch
            && latest.context == request.context
    }

    private enum ScreenCheckKind: String {
        case correction
        case revert
    }

    /// What the field-text check compares and what it does with the verdict.
    private struct ScreenCheck {
        let kind: ScreenCheckKind
        /// The text about to be deleted (a merged pair includes its bridge) and the boundary after it.
        let word: String
        let boundary: String
        let pid: pid_t
        let epoch: UInt64
        let provenance: CorrectionProvenance
        /// Whether a `.replaced` verdict deletes the field's word instead; otherwise it rejects.
        let acceptsReplacement: Bool
        /// Whether a mismatch is read again until the deadline: a revert pressed right after a
        /// correction can read the field before the app has applied that correction.
        let retriesMismatch: Bool
        /// Whether an unreadable field (`.unknown`) cancels instead of proceeding.
        let requiresMatch: Bool
        /// Runs on the input queue before and after every read.
        let isCurrent: () -> Bool
        /// Runs on the input queue: nil deletes what was planned, a count the field's word instead.
        let proceed: (Int?) -> Void
        /// Runs on the input queue when the field refuses the text in enforce mode (never on staleness).
        let reject: () -> Void
        /// Runs on the input queue whenever the check ends without proceeding (refusal or staleness).
        let cancelled: () -> Void
    }

    /// Reads the text before the caret and proceeds only if the field still ends with what
    /// `check` deletes (inline autocomplete, predictions and autocorrect change the field
    /// behind the buffer). Runs on the input queue; retries while the field lags behind.
    private func verifyScreen(
        _ check: ScreenCheck,
        query: @escaping ScreenTextRequest,
        startedAt: UInt64,
        attempt: Int,
        replacedBefore: Int? = nil,
        sawReplacement: Bool = false
    ) {
        let kind = check.kind.rawValue
        let provenance = String(describing: check.provenance)
        guard check.isCurrent() else {
            SwitchFixLog.engine.notice("\(kind) cancelled reason=stale-during-screen-check attempts=\(attempt - 1) provenance=\(provenance)")
            check.cancelled()
            return
        }
        // AX ranges are UTF-16. The margin: 2 for a decomposed accent in the field, 2 for an
        // autocorrected word that is longer, 1 for the separator before it, 1 spare. Only the
        // suffix is compared, so a character cut at the window's start does not matter.
        let window = (check.word + check.boundary).utf16.count + 6
        selectionQueue.async {
            query(check.pid, check.epoch, window) { [weak self] probe in
                self?.inputQueue.async {
                    guard let self else { return }
                    guard check.isCurrent() else {
                        SwitchFixLog.engine.notice("\(kind) cancelled reason=stale-during-screen-check attempts=\(attempt) provenance=\(provenance)")
                        check.cancelled()
                        return
                    }
                    let elapsed = DispatchTime.now().uptimeNanoseconds &- startedAt
                    let final = elapsed >= Self.screenCheckDeadlineNanoseconds
                    // Shadow reads once and corrects as before: waiting for a lagging field
                    // would delay corrections and lose them to the next keystroke.
                    let shadow = self.screenCheckMode == .shadow
                    var verdict = ScreenVerification.verdict(
                        word: check.word,
                        boundary: check.boundary,
                        probe: probe,
                        final: final
                    )
                    if case .replaced = verdict, !check.acceptsReplacement {
                        verdict = .mismatch
                    }
                    // Only differing text: a selection or a changed word will not turn back into it.
                    if case .text = probe, verdict == .mismatch, check.retriesMismatch, !final, !shadow,
                       ScreenVerification.verdict(word: check.word, boundary: check.boundary, probe: probe, final: true) == .mismatch {
                        verdict = .retry
                    }
                    // A field a whole word behind can look autocorrected (its previous word):
                    // a replacement is deleted only when a second read agrees. One first seen
                    // at the deadline still gets that read; a disagreeing one then cancels.
                    var unconfirmed: Int?
                    if case .replaced(let deleteCount) = verdict, deleteCount != replacedBefore {
                        unconfirmed = deleteCount
                    }
                    if unconfirmed != nil, final, sawReplacement, !shadow {
                        SwitchFixLog.engine.notice("\(kind) cancelled reason=screen-replacement-unconfirmed attempts=\(attempt)")
                        check.cancelled()
                        return
                    }
                    // Once a replacement was seen (even before a retry), an unreadable field
                    // is no reason to delete the typed length.
                    if verdict == .unknown, sawReplacement, !shadow {
                        SwitchFixLog.engine.notice("\(kind) cancelled reason=screen-unreadable-after-replacement attempts=\(attempt)")
                        check.cancelled()
                        return
                    }
                    if verdict == .retry || unconfirmed != nil, !shadow {
                        self.inputQueue.asyncAfter(deadline: .now() + Self.screenCheckRetryInterval) { [weak self] in
                            self?.verifyScreen(
                                check, query: query, startedAt: startedAt,
                                attempt: attempt + 1, replacedBefore: unconfirmed,
                                sawReplacement: sawReplacement || unconfirmed != nil
                            )
                        }
                        return
                    }
                    SwitchFixLog.engine.notice(
                        "screen check \(kind) verdict=\(String(describing: verdict)) probe=\(Self.logDescription(probe)) attempts=\(attempt) ms=\(Double(elapsed) / 1_000_000.0) mode=\(self.screenCheckMode.rawValue) provenance=\(provenance) pid=\(check.pid)"
                    )
                    if verdict == .unknown, check.requiresMatch, !shadow {
                        SwitchFixLog.engine.notice("\(kind) cancelled reason=screen-unreadable-unconfirmed")
                        check.reject()
                        check.cancelled()
                        return
                    }
                    if verdict == .mismatch, !shadow {
                        SwitchFixLog.engine.notice("\(kind) cancelled reason=screen-mismatch")
                        check.reject()
                        check.cancelled()
                        return
                    }
                    if case .replaced(let deleteCount) = verdict, !shadow {
                        check.proceed(deleteCount)
                        return
                    }
                    check.proceed(nil)
                }
            }
        }
    }

    /// The probe without its text: only lengths are logged.
    private static func logDescription(_ probe: FieldTextProbe) -> String {
        switch probe {
        case .text(let before, let atTextStart):
            return "text(\(SwitchFixLog.text(before))\(atTextStart ? ", start" : ""))"
        case .selection(let length): return "selection(\(length))"
        case .unavailable(let transient): return transient ? "unavailable(transient)" : "unavailable"
        }
    }

    /// - Parameter detectionID: the detector's id of the result behind `plan` (0: none).
    private func emit(_ plan: CorrectionPlan, detectionID: UInt64) {
        correctionQueue.async { [weak self] in
            guard let self else { return }
            guard plan.isEligible(using: self.captureState.snapshot()) else {
                SwitchFixLog.corrector.debug("emission skipped: state changed before apply \(SwitchFixLog.text(plan.originalText))")
                self.noteNotApplied(detectionID)
                return
            }
            let applied = self.customEmission.map { $0(plan) }
                ?? self.corrector.apply(plan, latestCaptureState: self.captureState.snapshot)
            if applied {
                self.learnFromApplied(plan)
            } else {
                self.noteNotApplied(detectionID)
            }
        }
    }

    /// Tells the detector that the correction it detected as `detectionID` never reached the
    /// field, so it does not count as corrected (any queue).
    private func noteNotApplied(_ detectionID: UInt64) {
        guard detectionID != 0 else { return }
        detectionQueue.async { [weak self] in
            self?.detector.noteCorrectionNotApplied(detectionID)
        }
    }

    /// Runs on the correction queue: posts `revert` unless the state changed or another
    /// correction replaced it, then learns from it.
    private func applyRevert(_ prepared: RevertPlan) {
        guard let revert = corrector.refreshedRevert(prepared, latest: captureState.snapshot()),
              revert.inverse.isEligible(using: captureState.snapshot()) else {
            SwitchFixLog.corrector.debug("revert skipped: stale \(SwitchFixLog.text(prepared.recorded.correctedText))")
            return
        }
        guard corrector.takeUndo(revert) else {
            SwitchFixLog.corrector.debug("revert skipped: the recorded correction changed")
            return
        }
        let applied = revertEmission.map { $0(revert) }
            ?? corrector.postUndo(revert, latestCaptureState: captureState.snapshot)
        if applied {
            learnFromReverted(revert.recorded)
        } else {
            // Not posted (state changed at the last moment): a stale revert is not a refusal.
            corrector.restoreUndo(revert)
        }
    }

    // MARK: - Learning (plan/005 §4.5, §12.1, §12.6)

    /// Shortest word a forced hotkey conversion may teach.
    static let minimumLearnedLength = 3

    /// Only single-token automatic, hotkey and forced hotkey corrections teach the personal
    /// lexicon (a plain hotkey correction only when reverted); selection, layout-switch and
    /// merged multi-word corrections don't.
    public static func isLearnable(_ plan: CorrectionPlan) -> Bool {
        guard !plan.originalText.isEmpty,
              !plan.originalText.contains(where: \.isWhitespace) else { return false }
        switch plan.provenance {
        case .automatic, .hotkey, .hotkeyForced: return true
        case .selection, .layoutSwitch: return false
        }
    }

    /// Runs on the correction queue after a correction reached the app.
    private func learnFromApplied(_ plan: CorrectionPlan) {
        guard let lexicon, Self.isLearnable(plan) else { return }
        // The key the detector looks up: the token without trailing punctuation.
        let word = LayoutDetector.lexiconWord(from: plan.originalText)
        guard !word.isEmpty else { return }
        switch plan.provenance {
        case .automatic:
            // Credit the rule only when it is what produced this correction (a rule to a
            // layout that is not installed falls through to the model).
            if let target = plan.targetLayout,
               lexicon.rule(for: word, sourceLayout: plan.originalLayout) == .alwaysCorrect(to: target) {
                lexicon.noteMatch(word: word, sourceLayout: plan.originalLayout)
            }
        case .hotkeyForced:
            // One or two keys ("b" → "и") are too little evidence to convert them forever.
            guard word.count >= Self.minimumLearnedLength,
                  let target = plan.targetLayout,
                  (plan.originalLayout == .english) != (target == .english) else { return }
            lexicon.recordAccepted(word: word, sourceLayout: plan.originalLayout, target: target)
        case .hotkey, .selection, .layoutSwitch:
            break
        }
    }

    /// Runs on the correction queue after the revert hotkey undid `plan`.
    private func learnFromReverted(_ plan: CorrectionPlan) {
        guard let lexicon, Self.isLearnable(plan) else { return }
        let word = LayoutDetector.lexiconWord(from: plan.originalText)
        guard !word.isEmpty else { return }
        switch plan.provenance {
        case .automatic:
            lexicon.recordRejected(word: word, sourceLayout: plan.originalLayout)
        case .hotkeyForced:
            lexicon.forgetAccepted(word: word, sourceLayout: plan.originalLayout)
        case .hotkey:
            // A rule converting the word to this target is what the detector applied (it
            // checks the lexicon before the model); reverting rejects a rule learned from the
            // hotkey (`forgetAccepted` leaves manual ones).
            if let target = plan.targetLayout,
               lexicon.rule(for: word, sourceLayout: plan.originalLayout) == .alwaysCorrect(to: target) {
                lexicon.forgetAccepted(word: word, sourceLayout: plan.originalLayout)
            }
        case .selection, .layoutSwitch:
            break
        }
    }

    /// `screenSuffix`: the text before the caret must end with it (Chromium's accessibility
    /// text can lag behind typing); nil disables reading the word before the caret. Empty: the
    /// caret was only placed, so nothing typed proves the screen current — the word is read
    /// only with the enforced field check, after the caret settles, and checked again before
    /// it is deleted.
    private func requestManualCorrection(
        word: String?,
        screenSuffix: String?,
        sequence: UInt64,
        context: InputContextSnapshot,
        teaches: Bool = true
    ) {
        SwitchFixLog.engine.notice(
            "manual: bufferLen=\(word?.count ?? 0) secureFocus=\(String(describing: context.secureFocus)) appAllowed=\(context.appAllowed) seq=\(sequence)"
        )
        guard context.secureFocus == .notSecure, context.appAllowed else { return }
        let latest = captureState.snapshot()
        let generation = latest.editGeneration
        let requestCorrectionEpoch = correctionEpoch

        // The screen is read only when there is no word and it can be verified.
        let caretPlacedOnly = word == nil && screenSuffix?.isEmpty == true
        let verifiesPlacedCaret = screenCheckMode == .enforce
            && screenTextRequest != nil
            && readsScreenAfterCaretMove?(context.frontmostPID) ?? true
        let suffix = caretPlacedOnly && !verifiesPlacedCaret ? nil : screenSuffix
        let wantsCaretText = word == nil && suffix != nil
        var settleDelay: UInt64 = 0
        if caretPlacedOnly && wantsCaretText {
            let elapsed = DispatchTime.now().uptimeNanoseconds &- caretMoveUptime
            settleDelay = elapsed < Self.caretSettleNanoseconds ? Self.caretSettleNanoseconds - elapsed : 0
        }
        let query: ((@escaping (CaretContext) -> Void) -> Void)?
        if let caretContextRequest {
            query = { completion in
                caretContextRequest(context.frontmostPID, context.epoch, wantsCaretText, completion)
            }
        } else if let selectedTextRequest {
            query = { completion in
                selectedTextRequest(context.frontmostPID, context.epoch) { text in
                    completion(text.map(CaretContext.selection) ?? .unavailable)
                }
            }
        } else {
            query = nil
        }
        guard let query else {
            if let word {
                runDetection(DetectionRequest(
                    word: word,
                    boundary: "",
                    sequence: sequence,
                    editGeneration: generation,
                    correctionEpoch: requestCorrectionEpoch,
                    context: context
                ), forceConversion: true, teaches: teaches)
            }
            return
        }

        selectionQueue.asyncAfter(deadline: .now() + .nanoseconds(Int(settleDelay))) { [weak self] in
            query { [weak self] caret in
                guard let self else { return }
                self.inputQueue.async {
                let latest = self.captureState.snapshot()
                guard latest.latestPhysicalSequence == sequence,
                      latest.editGeneration == generation,
                      latest.correctionEpoch == requestCorrectionEpoch,
                      latest.context == context else {
                    SwitchFixLog.engine.notice(
                        "manual: dropped after selection query seqMatch=\(latest.latestPhysicalSequence == sequence) genMatch=\(latest.editGeneration == generation) epochMatch=\(latest.correctionEpoch == requestCorrectionEpoch) contextMatch=\(latest.context == context)"
                    )
                    return
                }
                let configuration = self.detectionConfiguration.withLock { $0 }
                var selectedText: String?
                var caretWord: String?
                switch caret {
                case .selection(let text):
                    selectedText = text
                case .caret(let before, let startsAtTextStart, let next):
                    if wantsCaretText, let suffix, before.hasSuffix(suffix) {
                        caretWord = CaretWordExtractor.word(
                            before: before,
                            prefixStartsAtTextStart: startsAtTextStart,
                            next: next,
                            tables: configuration.keyboardTables
                        )
                    }
                case .unavailable:
                    break
                }
                SwitchFixLog.engine.notice(
                    "manual: selectionLen=\(selectedText?.count ?? -1) caretWordLen=\(caretWord?.count ?? -1) caretPlacedOnly=\(caretPlacedOnly)"
                )

                if let selectedText, !selectedText.isEmpty,
                   let (sourceLayout, targetLayout, converted) = Self.selectionConversion(
                    selectedText,
                    currentLayout: context.layout,
                    configuration: configuration
                   ) {
                    self.corrector.performSelectionCorrection(
                        selectedText: selectedText,
                        convertedText: converted,
                        targetLayout: targetLayout,
                        shouldSwitchLayout: true,
                        originalLayout: sourceLayout,
                        sequence: sequence,
                        context: context,
                        editGeneration: generation,
                        correctionEpoch: requestCorrectionEpoch,
                        latestCaptureState: self.captureState.snapshot
                    )
                } else if let target = word ?? caretWord {
                    // A word read from the screen may have been pasted or typed long ago:
                    // weak evidence of intent, so it never teaches the lexicon. A typed suffix
                    // just checked it against the screen, so the correction does not read it
                    // again; after a bare caret move nothing did, so it does.
                    self.runDetection(DetectionRequest(
                        word: target,
                        boundary: "",
                        sequence: sequence,
                        editGeneration: generation,
                        correctionEpoch: requestCorrectionEpoch,
                        context: context,
                        screenVerified: word == nil && !caretPlacedOnly,
                        requiresScreenMatch: word == nil && caretPlacedOnly
                    ), forceConversion: true, teaches: teaches && word != nil)
                }
                }
            }
        }
    }

    private func resetDetectorState() {
        detectionQueue.async { [weak self] in
            self?.detector.reset()
        }
    }

    /// Converts selected text starting from the current layout, then from the others:
    /// the selection may already be in a different script than the active input source
    /// (e.g. converting the same selection back and forth). Installed targets win.
    private static func selectionConversion(
        _ text: String,
        currentLayout: Layout,
        configuration: DetectionConfiguration
    ) -> (source: Layout, target: Layout, converted: String)? {
        let sources = ScriptAnalyzer.selectionSourceOrder(for: text, currentLayout: currentLayout)
        for source in sources {
            let alternatives = LayoutMapper.convertToAlternatives(
                text,
                from: source,
                tables: configuration.keyboardTables
            ).filter { $0.1 != text }
            if let (target, converted) = alternatives.first(where: { configuration.allowedLayouts.contains($0.0) })
                ?? alternatives.first {
                return (source, target, converted)
            }
        }
        return nil
    }
}

private extension CapturedInput.Kind {
    var invalidatesCaptureContext: Bool {
        switch self {
        case .navigation, .caretMove, .focusMayChange:
            return true
        default:
            return false
        }
    }

    var recordsUserEdit: Bool {
        switch self {
        case .character, .boundary, .delete, .navigation, .caretMove, .inputSourceKey, .focusMayChange, .undo:
            return true
        default:
            return false
        }
    }
}
