import AppKit
import Carbon
import Core
import UI
import Utils

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var keyboardMonitor: KeyboardMonitor?
    private var inputEngine: InputEngine?
    private var captureState: CaptureStateStore?
    private var focusCoordinator: AccessibilityFocusCoordinator?
    private let inputSourceManager = InputSourceManager.shared
    private var observersRegistered = false
    private var readyLayouts: Set<Layout> = []
    private var modelsPrepared = false
    private var previousLayout: Layout = .english
    private var previousInputSourceID = "unknown"

    func applicationDidFinishLaunching(_ notification: Notification) {
        SwitchFixLog.app.notice("launched, pid=\(ProcessInfo.processInfo.processIdentifier)")
        statusBarController = StatusBarController()
        inputSourceManager.refreshCurrentInputSource()
        previousLayout = inputSourceManager.currentLayout()
        previousInputSourceID = inputSourceManager.currentInputSourceID()

        let frontmostApplication = NSWorkspace.shared.frontmostApplication
        let initialPID = frontmostApplication?.processIdentifier ?? 0
        let initialAllowed = frontmostApplication?.bundleIdentifier.map {
            !AppFilter.shared.isBlacklisted($0)
        } ?? false
        let initialContext = InputContextSnapshot(
            epoch: 1,
            frontmostPID: initialPID,
            appAllowed: initialAllowed,
            layout: previousLayout,
            inputSourceID: previousInputSourceID,
            secureFocus: .unknown
        )
        let state = CaptureStateStore(
            context: initialContext,
            hotkeys: currentHotkeyConfiguration()
        )
        captureState = state

        let coordinator = AccessibilityFocusCoordinator(
            onFocusInvalidated: { [weak self] pid in
                self?.publishUnknownFocus(for: pid)
            },
            onResolved: { [weak self] resolution in
                self?.publishFocusResolution(resolution)
            }
        )
        focusCoordinator = coordinator

        let engine = InputEngine(
            captureState: state,
            initialContext: initialContext,
            preferences: currentPreferencesSnapshot(),
            selectedTextRequest: { [weak self] pid, epoch, completion in
                self?.focusCoordinator?.requestSelectedText(
                    pid: pid,
                    epoch: epoch,
                    completion: completion
                ) ?? completion(nil)
            },
            lexicon: PersonalLexicon.shared
        )
        engine.onFocusMayChange = { [weak self] pid, epoch in
            DispatchQueue.main.async {
                self?.focusCoordinator?.focusMayChange(pid: pid, epoch: epoch)
            }
        }
        inputEngine = engine
        inputSourceManager.setSelectionCallbacks(
            willSelect: { [weak self] layout, sourceID in
                self?.generatedLayoutSelectionWillBegin(layout: layout, sourceID: sourceID)
            },
            selectionFailed: { [weak self] in
                self?.generatedLayoutSelectionFailed()
            }
        )

        registerConfigurationObservers()
        registerMonitoringObservers()
        prepareLanguageModels { [weak self] allowedLayouts in
            guard let self else { return }
            self.readyLayouts = allowedLayouts
            self.modelsPrepared = true
            self.updateDetectionConfiguration(allowedLayouts: allowedLayouts)
            Permissions.ensureRequiredPermissions { [weak self] in
                self?.startMonitoringAndFocusObservation()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        PersonalLexicon.shared.flush()
        focusCoordinator?.stop()
        keyboardMonitor?.stop()
    }

    /// Loads the language models of the installed layouts off the main thread; automatic
    /// correction is enabled only for layouts whose model (and the English one) loaded.
    private func prepareLanguageModels(completion: @escaping (Set<Layout>) -> Void) {
        let installedLayouts = inputSourceManager.availableLayouts()
        DispatchQueue.global(qos: .utility).async {
            var readyLayouts: Set<Layout> = []
            var unavailable: [String] = []
            for layout in installedLayouts {
                if LanguageModelReadiness.prepare(layout) {
                    readyLayouts.insert(layout)
                } else {
                    unavailable.append(layout.rawValue)
                }
            }
        DispatchQueue.main.async {
            if !unavailable.isEmpty {
                SwitchFixLog.app.notice(
                    "automatic correction unavailable for layouts: \(unavailable.joined(separator: ", "))"
                )
            }
            completion(readyLayouts)
        }
        }
    }

    private func startMonitoringAndFocusObservation() {
        guard let state = captureState, let engine = inputEngine else { return }
        refreshFrontmostContext()
        let monitor = KeyboardMonitor(captureState: state)
        monitor.refreshInputTranslations()
        monitor.onInput = { [weak engine] input in
            engine?.enqueue(input)
        }
        keyboardMonitor = monitor

        guard monitor.start() else {
            SwitchFixLog.app.error("Monitoring failed to start (event tap creation failed)")
            return
        }
        let context = state.snapshot().context
        focusCoordinator?.observeApplication(pid: context.frontmostPID, epoch: context.epoch)
        SwitchFixLog.app.notice("monitoring started pid=\(context.frontmostPID) layout=\(context.layout.rawValue) appAllowed=\(context.appAllowed)")
    }

    private func registerConfigurationObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(preferencesDidUpdate),
            name: .preferencesDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appFilterDidUpdate),
            name: .appFilterDidChange,
            object: nil
        )
    }

    private func registerMonitoringObservers() {
        guard !observersRegistered else { return }
        observersRegistered = true
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeApplicationChanged(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(selectedInputSourceChanged),
            name: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(enabledInputSourcesChanged),
            name: NSNotification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
    }

    /// A layout was added or removed in System Settings: rebuild the key tables.
    @objc private func enabledInputSourcesChanged() {
        inputSourceManager.refreshInstalledSources()
        inputSourceManager.refreshCurrentInputSource()
        keyboardMonitor?.refreshInputTranslations()
        updateDetectionConfiguration(allowedLayouts: readyLayouts)
    }

    @objc private func activeApplicationChanged(_ notification: Notification) {
        guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let state = captureState else {
            return
        }
        inputSourceManager.refreshCurrentInputSource()
        keyboardMonitor?.refreshInputTranslations()
        let layout = inputSourceManager.currentLayout()
        let sourceID = inputSourceManager.currentInputSourceID()
        previousLayout = layout
        previousInputSourceID = sourceID
        let allowed = application.bundleIdentifier.map {
            !AppFilter.shared.isBlacklisted($0)
        } ?? false
        let context = state.replaceContext(
            frontmostPID: application.processIdentifier,
            appAllowed: allowed,
            layout: layout,
            inputSourceID: sourceID,
            secureFocus: .unknown
        )
        inputEngine?.updateContext(context)
        updateDetectionConfiguration(allowedLayouts: readyLayouts)
        focusCoordinator?.observeApplication(pid: context.frontmostPID, epoch: context.epoch)
        SwitchFixLog.app.notice(
            "frontmost changed pid=\(context.frontmostPID) bundle=\(application.bundleIdentifier ?? "nil") allowed=\(allowed) layout=\(layout.rawValue)"
        )
    }

    @objc private func selectedInputSourceChanged() {
        guard let state = captureState else { return }
        let oldLayout = previousLayout
        let oldSourceID = previousInputSourceID
        inputSourceManager.refreshCurrentInputSource()
        keyboardMonitor?.refreshInputTranslations()
        let newLayout = inputSourceManager.currentLayout()
        let newSourceID = inputSourceManager.currentInputSourceID()
        let expectedGeneratedSelection = inputSourceManager.consumeExpectedSelection(sourceID: newSourceID)
        previousLayout = newLayout
        previousInputSourceID = newSourceID

        let current = state.snapshot().context
        guard oldSourceID != newSourceID || oldLayout != newLayout else { return }
        SwitchFixLog.app.notice(
            "layout changed old=\(oldLayout.rawValue) new=\(newLayout.rawValue) generated=\(expectedGeneratedSelection)"
        )
        let context = state.replaceContext(
            frontmostPID: current.frontmostPID,
            appAllowed: current.appAllowed,
            layout: newLayout,
            inputSourceID: newSourceID,
            secureFocus: expectedGeneratedSelection ? .unknown : current.secureFocus
        )
        // Not a dictionary literal: old and new can share a layout (RussianWin → Russian).
        var overrides = [oldLayout: oldSourceID]
        overrides[newLayout] = newSourceID
        let keyboardTables = inputSourceManager.keyboardTables(overrides: overrides)
        if expectedGeneratedSelection {
            inputEngine?.handleGeneratedLayoutContext(context)
            focusCoordinator?.focusMayChange(pid: context.frontmostPID, epoch: context.epoch)
        } else {
            inputEngine?.handleLayoutChange(
                from: oldLayout,
                to: newLayout,
                context: context,
                keyboardTables: keyboardTables
            )
            // A modifier shortcut (e.g. Control-Space) is captured as navigation and leaves focus
            // unknown; the new epoch orphans that pending query, so re-resolve here —
            // otherwise every keystroke is dropped until the next click.
            if context.secureFocus != .notSecure {
                focusCoordinator?.focusMayChange(pid: context.frontmostPID, epoch: context.epoch)
            }
        }
        updateDetectionConfiguration(allowedLayouts: readyLayouts)
    }

    private func generatedLayoutSelectionWillBegin(layout: Layout, sourceID: String) {
        guard let state = captureState else { return }
        let current = state.snapshot().context
        let context = state.replaceContext(
            frontmostPID: current.frontmostPID,
            appAllowed: current.appAllowed,
            layout: layout,
            inputSourceID: sourceID,
            secureFocus: .unknown
        )
        inputEngine?.handleGeneratedLayoutContext(context)
    }

    private func generatedLayoutSelectionFailed() {
        inputSourceManager.refreshCurrentInputSource()
        guard let state = captureState else { return }
        let current = state.snapshot().context
        let context = state.replaceContext(
            frontmostPID: current.frontmostPID,
            appAllowed: current.appAllowed,
            layout: inputSourceManager.currentLayout(),
            inputSourceID: inputSourceManager.currentInputSourceID(),
            secureFocus: .unknown
        )
        inputEngine?.updateContext(context)
        DispatchQueue.main.async { [weak self] in
            self?.focusCoordinator?.focusMayChange(pid: context.frontmostPID, epoch: context.epoch)
        }
    }

    @objc private func preferencesDidUpdate() {
        SwitchFixLog.preferences.notice(
            "preferences updated enabled=\(PreferencesManager.shared.isEnabled) mode=\(PreferencesManager.shared.correctionMode.rawValue)"
        )
        captureState?.updateHotkeys(currentHotkeyConfiguration())
        inputEngine?.updatePreferences(currentPreferencesSnapshot())
        // The Sensitivity slider; before the models are prepared there are no ready
        // layouts yet, and the completion pushes the configuration itself.
        if modelsPrepared {
            updateDetectionConfiguration(allowedLayouts: readyLayouts)
        }
    }

    @objc private func appFilterDidUpdate() {
        guard let state = captureState else { return }
        let current = state.snapshot().context
        let application = NSRunningApplication(processIdentifier: current.frontmostPID)
        let allowed = application?.bundleIdentifier.map {
            !AppFilter.shared.isBlacklisted($0)
        } ?? false
        guard allowed != current.appAllowed else { return }
        let context = state.replaceContext(
            frontmostPID: current.frontmostPID,
            appAllowed: allowed,
            layout: current.layout,
            inputSourceID: current.inputSourceID,
            secureFocus: current.secureFocus
        )
        inputEngine?.updateContext(context)
    }

    private func publishUnknownFocus(for pid: pid_t) -> UInt64? {
        guard let state = captureState,
              state.snapshot().context.frontmostPID == pid else {
            return nil
        }
        let context = state.invalidateFocus()
        inputEngine?.updateContext(context)
        return context.epoch
    }

    private func refreshFrontmostContext() {
        guard let state = captureState,
              let application = NSWorkspace.shared.frontmostApplication else {
            return
        }
        inputSourceManager.refreshCurrentInputSource()
        let layout = inputSourceManager.currentLayout()
        let sourceID = inputSourceManager.currentInputSourceID()
        previousLayout = layout
        previousInputSourceID = sourceID
        let allowed = application.bundleIdentifier.map {
            !AppFilter.shared.isBlacklisted($0)
        } ?? false
        let context = state.replaceContext(
            frontmostPID: application.processIdentifier,
            appAllowed: allowed,
            layout: layout,
            inputSourceID: sourceID,
            secureFocus: .unknown
        )
        inputEngine?.updateContext(context)
    }

    private func publishFocusResolution(_ resolution: AccessibilityFocusResolution) {
        guard let state = captureState else { return }
        let secureFocus: SecureFocusState
        switch resolution.state {
        case .unknown: secureFocus = .unknown
        case .secure: secureFocus = .secure
        case .notSecure: secureFocus = .notSecure
        }
        guard let context = state.resolveFocus(
            secureFocus,
            frontmostPID: resolution.pid,
            epoch: resolution.epoch
        ) else {
            return
        }
        SwitchFixLog.app.debug("focus resolved pid=\(resolution.pid) state=\(String(describing: secureFocus))")
        inputEngine?.updateContext(context)
    }

    private func updateDetectionConfiguration(allowedLayouts: Set<Layout>) {
        inputEngine?.updateDetectionConfiguration(
            allowedLayouts: allowedLayouts,
            keyboardTables: inputSourceManager.keyboardTables(),
            thresholds: .forSensitivity(PreferencesManager.shared.detectionSensitivity)
        )
    }

    private func currentPreferencesSnapshot() -> InputPreferencesSnapshot {
        let mode: InputCorrectionMode
        switch PreferencesManager.shared.correctionMode {
        case .automatic: mode = .automatic
        case .hotkey: mode = .hotkey
        case .layoutSwitch: mode = .layoutSwitch
        }
        return InputPreferencesSnapshot(
            isEnabled: PreferencesManager.shared.isEnabled,
            correctionMode: mode
        )
    }

    private func currentHotkeyConfiguration() -> HotkeyConfiguration {
        HotkeyConfiguration(
            hotkeyKeyCode: PreferencesManager.shared.hotkeyKeyCode,
            hotkeyModifiers: PreferencesManager.shared.hotkeyModifiers,
            revertHotkeyKeyCode: PreferencesManager.shared.revertHotkeyKeyCode,
            revertHotkeyModifiers: PreferencesManager.shared.revertHotkeyModifiers
        )
    }

}
