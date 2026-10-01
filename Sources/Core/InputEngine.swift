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

    public init(
        word: String,
        boundary: String,
        sequence: UInt64,
        editGeneration: UInt64,
        correctionEpoch: UInt64,
        context: InputContextSnapshot,
        continuesPreviousWord: Bool = false,
        screenVerified: Bool = false
    ) {
        self.word = word
        self.boundary = boundary
        self.sequence = sequence
        self.editGeneration = editGeneration
        self.correctionEpoch = correctionEpoch
        self.context = context
        self.continuesPreviousWord = continuesPreviousWord
        self.screenVerified = screenVerified
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
    /// before a correction deletes; the completion may run on any queue.
    public typealias ScreenTextRequest = (pid_t, UInt64, Int, @escaping (FieldTextProbe) -> Void) -> Void
    /// Reverts the last correction; returns the reverted plan (tests replace `TextCorrector.undo`).
    public typealias RevertEmission = (UInt64, InputContextSnapshot) -> CorrectionPlan?

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
    private let revertEmission: RevertEmission?
    private let lexicon: PersonalLexicon?
    private let detectionConfiguration = OSAllocatedUnfairLock(initialState: DetectionConfiguration())
    private var correctionEpoch: UInt64
    private var latestProcessedSequence: UInt64 = 0
    /// Uptime when the state machine set aside a word at a Globe press.
    private var layoutSwitchWordUptime: UInt64 = 0
    /// A switch notification later than this is not the Globe press's: Globe may
    /// have started dictation and the layout changed by an uncaptured path.
    static let layoutSwitchWordLifetimeNanoseconds: UInt64 = 500_000_000
    /// How long a correction waits for the field to show the typed text before deciding.
    /// Soft: checked when an answer arrives, and one read of a busy app can take ~250 ms.
    static let screenCheckDeadlineNanoseconds: UInt64 = 150_000_000
    static let screenCheckRetryInterval: DispatchTimeInterval = .milliseconds(20)
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
                let reverted: CorrectionPlan?
                if let revertEmission = self.revertEmission {
                    reverted = revertEmission(sequence, context)
                } else {
                    reverted = self.corrector.undo(
                        sequence: sequence,
                        context: context,
                        latestCaptureState: self.captureState.snapshot
                    )
                }
                if let reverted {
                    self.learnFromReverted(reverted)
                } else {
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
            verifyScreen(
                plan,
                request: request,
                query: screenTextRequest,
                startedAt: DispatchTime.now().uptimeNanoseconds,
                attempt: 1
            )
        } else {
            emit(plan)
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

    /// Reads the text before the caret and emits `plan` only if the field still ends with
    /// what it deletes (inline autocomplete, predictions and autocorrect change the field
    /// behind the buffer). Runs on the input queue; retries while the field lags behind.
    private func verifyScreen(
        _ plan: CorrectionPlan,
        request: DetectionRequest,
        query: @escaping ScreenTextRequest,
        startedAt: UInt64,
        attempt: Int
    ) {
        guard isCurrent(request) else {
            SwitchFixLog.engine.notice("correction cancelled reason=stale-during-screen-check attempts=\(attempt - 1) provenance=\(String(describing: plan.provenance))")
            return
        }
        // AX ranges are UTF-16; the margin covers a decomposed accent in the field, and an
        // autocorrected word up to two characters longer plus the separator before it. Only
        // the suffix is compared, so a character cut at the window's start does not matter.
        let window = (plan.originalText + plan.boundaryText).utf16.count + 6
        selectionQueue.async {
            query(request.context.frontmostPID, request.context.epoch, window) { [weak self] probe in
                self?.inputQueue.async {
                    guard let self else { return }
                    guard self.isCurrent(request) else {
                        SwitchFixLog.engine.notice("correction cancelled reason=stale-during-screen-check attempts=\(attempt) provenance=\(String(describing: plan.provenance))")
                        return
                    }
                    let elapsed = DispatchTime.now().uptimeNanoseconds &- startedAt
                    let verdict = ScreenVerification.verdict(
                        word: plan.originalText,
                        boundary: plan.boundaryText,
                        probe: probe,
                        final: elapsed >= Self.screenCheckDeadlineNanoseconds
                    )
                    // Shadow reads once and corrects as before: waiting for a lagging field
                    // would delay corrections and lose them to the next keystroke.
                    let shadow = self.screenCheckMode == .shadow
                    if verdict == .retry, !shadow {
                        self.inputQueue.asyncAfter(deadline: .now() + Self.screenCheckRetryInterval) { [weak self] in
                            self?.verifyScreen(plan, request: request, query: query, startedAt: startedAt, attempt: attempt + 1)
                        }
                        return
                    }
                    SwitchFixLog.engine.notice(
                        "screen check verdict=\(String(describing: verdict)) probe=\(Self.logDescription(probe)) attempts=\(attempt) ms=\(Double(elapsed) / 1_000_000.0) mode=\(self.screenCheckMode.rawValue) provenance=\(String(describing: plan.provenance)) pid=\(request.context.frontmostPID)"
                    )
                    if verdict == .mismatch, !shadow {
                        SwitchFixLog.engine.notice("correction cancelled reason=screen-mismatch")
                        return
                    }
                    if case .replaced(let deleteCount) = verdict, !shadow {
                        self.emit(plan.deleting(deleteCount))
                        return
                    }
                    self.emit(plan)
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

    private func emit(_ plan: CorrectionPlan) {
        correctionQueue.async { [weak self] in
            guard let self else { return }
            guard plan.isEligible(using: self.captureState.snapshot()) else {
                SwitchFixLog.corrector.debug("emission skipped: state changed before apply \(SwitchFixLog.text(plan.originalText))")
                return
            }
            let applied = self.customEmission.map { $0(plan) }
                ?? self.corrector.apply(plan, latestCaptureState: self.captureState.snapshot)
            if applied {
                self.learnFromApplied(plan)
            }
        }
    }

    // MARK: - Learning (plan/005 §4.5, §12.1, §12.6)

    /// Shortest word a forced hotkey conversion may teach.
    static let minimumLearnedLength = 3

    /// Only single-token automatic corrections and forced hotkey conversions teach the
    /// personal lexicon; selection, layout-switch and merged multi-word corrections don't.
    public static func isLearnable(_ plan: CorrectionPlan) -> Bool {
        guard !plan.originalText.isEmpty,
              !plan.originalText.contains(where: \.isWhitespace) else { return false }
        switch plan.provenance {
        case .automatic, .hotkeyForced: return true
        case .hotkey, .selection, .layoutSwitch: return false
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
        case .hotkey, .selection, .layoutSwitch:
            break
        }
    }

    /// `screenSuffix`: the text before the caret must end with it (Chromium's accessibility
    /// text can lag behind typing); nil disables reading the word before the caret.
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
        let wantsCaretText = word == nil && screenSuffix != nil
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

        selectionQueue.async { [weak self] in
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
                    if wantsCaretText, let screenSuffix, before.hasSuffix(screenSuffix) {
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
                    "manual: selectionLen=\(selectedText?.count ?? -1) caretWordLen=\(caretWord?.count ?? -1)"
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
                    // weak evidence of intent, so it never teaches the lexicon. It was just
                    // checked against the screen, so the correction does not read it again.
                    self.runDetection(DetectionRequest(
                        word: target,
                        boundary: "",
                        sequence: sequence,
                        editGeneration: generation,
                        correctionEpoch: requestCorrectionEpoch,
                        context: context,
                        screenVerified: word == nil
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
        case .navigation, .focusMayChange:
            return true
        default:
            return false
        }
    }

    var recordsUserEdit: Bool {
        switch self {
        case .character, .boundary, .delete, .navigation, .inputSourceKey, .focusMayChange, .undo:
            return true
        default:
            return false
        }
    }
}
