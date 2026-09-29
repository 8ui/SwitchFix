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

    public init(
        word: String,
        boundary: String,
        sequence: UInt64,
        editGeneration: UInt64,
        correctionEpoch: UInt64,
        context: InputContextSnapshot
    ) {
        self.word = word
        self.boundary = boundary
        self.sequence = sequence
        self.editGeneration = editGeneration
        self.correctionEpoch = correctionEpoch
        self.context = context
    }
}

public final class InputEngine {
    public typealias ExactDetection = (DetectionRequest) -> DetectionResult?
    public typealias CorrectionEmission = (CorrectionPlan) -> Bool
    public typealias SelectedTextRequest = (pid_t, UInt64, @escaping (String?) -> Void) -> Void
    /// Reverts the last correction; returns the reverted plan (tests replace `TextCorrector.undo`).
    public typealias RevertEmission = (UInt64, InputContextSnapshot) -> CorrectionPlan?

    public var onFocusMayChange: ((pid_t, UInt64) -> Void)?

    private struct DetectionConfiguration {
        var allowedLayouts = Set(Layout.allCases)
        var ukrainianFromVariant: UkrainianKeyboardVariant = .standard
        var ukrainianToVariant: UkrainianKeyboardVariant = .standard
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
    private let revertEmission: RevertEmission?
    private let lexicon: PersonalLexicon?
    private let detectionConfiguration = OSAllocatedUnfairLock(initialState: DetectionConfiguration())
    private var correctionEpoch: UInt64
    private var latestProcessedSequence: UInt64 = 0
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
        fromVariant: UkrainianKeyboardVariant,
        toVariant: UkrainianKeyboardVariant
    ) {
        inputQueue.async { [weak self] in
            guard let self else { return }
            let bufferedWord = self.stateMachine.currentBuffer
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
                    ukrainianFromVariant: fromVariant,
                    ukrainianToVariant: toVariant
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
                                ukrainianFromVariant: fromVariant,
                                ukrainianToVariant: toVariant
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
        ukrainianFromVariant: UkrainianKeyboardVariant,
        ukrainianToVariant: UkrainianKeyboardVariant,
        thresholds: DetectionThresholds = .default
    ) {
        detectionConfiguration.withLock { value in
            value.allowedLayouts = allowedLayouts
            value.ukrainianFromVariant = ukrainianFromVariant
            value.ukrainianToVariant = ukrainianToVariant
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

    private func process(_ input: CapturedInput) {
        latestProcessedSequence = input.sequence
        logger.debug("input seq=\(input.sequence) kind=\(String(describing: input.kind)) keyCode=\(input.keyCode) autorepeat=\(input.isAutorepeat) srcPid=\(input.sourcePID)")

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
    }

    private func handle(_ command: InputStateCommand) {
        switch command {
        case .append(let text):
            logger.debug("buffer '\(self.stateMachine.currentBuffer)' (+ '\(text)')")
        case .deleteLast:
            logger.debug("buffer '\(self.stateMachine.currentBuffer)' (backspace)")
        case .invalidate(let reason):
            resetDetectorState()
            logger.debug("buffer invalidated reason=\(String(describing: reason))")
        case .flush(let word, let boundary, let sequence, let context):
            logger.notice("word flushed '\(word)' boundary='\(boundary)' seq=\(sequence) layout=\(context.layout.rawValue)")
            let latest = captureState.snapshot()
            runDetection(DetectionRequest(
                word: word,
                boundary: boundary,
                sequence: sequence,
                editGeneration: latest.editGeneration,
                correctionEpoch: correctionEpoch,
                context: context
            ))
        case .requestManualCorrection(let word, let sequence, let context):
            logger.notice("hotkey correction requested word='\(word ?? "nil")' seq=\(sequence)")
            requestManualCorrection(word: word, sequence: sequence, context: context)
        case .requestRevert(let word, let sequence, let context):
            logger.notice("revert hotkey pressed word='\(word ?? "nil")' seq=\(sequence)")
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
                        self.requestManualCorrection(word: word, sequence: sequence, context: context, teaches: false)
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
                self.detector.ukrainianFromVariant = configuration.ukrainianFromVariant
                self.detector.ukrainianToVariant = configuration.ukrainianToVariant
                self.detector.thresholds = configuration.thresholds
                self.detector.discardBuffer()
                self.detector.addCharacter(request.word)
                result = self.detector.flushBuffer(
                    boundaryCharacter: request.boundary.isEmpty ? nil : request.boundary
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
                        ukrainianFromVariant: configuration.ukrainianFromVariant,
                        ukrainianToVariant: configuration.ukrainianToVariant
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
                    "detect '\(result.originalWord)' -> '\(result.convertedWord)' source=\(result.sourceLayout.rawValue) target=\(result.targetLayout.rawValue) switch=\(result.shouldSwitchLayout) ms=\(Double(duration) / 1_000_000.0)"
                )
            } else {
                SwitchFixLog.detector.info(
                    "detect '\(request.word)' -> keep (no correction, ms=\(Double(duration) / 1_000_000.0))"
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
        }
        guard cancelReason == nil else {
            SwitchFixLog.engine.notice("correction cancelled reason=\(cancelReason!)")
            logger.debug("correction cancelled reason=\(cancelReason!) word='\(result.originalWord)'")
            return
        }

        let boundary = request.boundary
        logger.notice(
            "correction planned '\(result.originalWord)' -> '\(result.convertedWord)' deletes=\(result.originalWord.count + boundary.count) pid=\(request.context.frontmostPID)"
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

        correctionQueue.async { [weak self] in
            guard let self else { return }
            guard plan.isEligible(using: self.captureState.snapshot()) else {
                SwitchFixLog.corrector.debug("emission skipped: state changed before apply '\(plan.originalText)'")
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

    private func requestManualCorrection(
        word: String?,
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
        guard let selectedTextRequest else {
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
            selectedTextRequest(context.frontmostPID, context.epoch) { [weak self] selectedText in
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
                SwitchFixLog.engine.notice("manual: selectionLen=\(selectedText?.count ?? -1)")

                let configuration = self.detectionConfiguration.withLock { $0 }
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
                } else if let word {
                    self.runDetection(DetectionRequest(
                        word: word,
                        boundary: "",
                        sequence: sequence,
                        editGeneration: generation,
                        correctionEpoch: requestCorrectionEpoch,
                        context: context
                    ), forceConversion: true, teaches: teaches)
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
        // Try the layout matching the text's dominant script first, otherwise e.g.
        // "привет, мир" "converted" from English only turns the comma into "б".
        let cyrillic = text.unicodeScalars.filter { (0x0400...0x04FF).contains($0.value) }.count
        let latin = text.unicodeScalars.filter { $0.isASCII && CharacterSet.letters.contains($0) }.count
        let scriptLayouts: [Layout] = cyrillic > latin
            ? (currentLayout == .english ? [.russian, .ukrainian] : [currentLayout, .russian, .ukrainian])
            : [.english]
        var sources: [Layout] = []
        for layout in scriptLayouts + [currentLayout] + Layout.allCases where !sources.contains(layout) {
            sources.append(layout)
        }
        for source in sources {
            let alternatives = LayoutMapper.convertToAlternatives(
                text,
                from: source,
                ukrainianFromVariant: configuration.ukrainianFromVariant,
                ukrainianToVariant: configuration.ukrainianToVariant
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
        case .character, .boundary, .delete, .navigation, .focusMayChange, .undo:
            return true
        default:
            return false
        }
    }
}
