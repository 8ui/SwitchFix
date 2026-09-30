import AppKit
import ApplicationServices
import Carbon
import os

public class Permissions {
    public static func ensureRequiredPermissions(completion: @escaping () -> Void) {
        ensureAccessibility {
            completion()
            if !isInputMonitoringGranted() {
                _ = requestInputMonitoring()
            }
        }
    }

    public static func isAccessibilityGranted() -> Bool {
        return AXIsProcessTrusted()
    }

    public static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    public static func isInputMonitoringGranted() -> Bool {
        return CGPreflightListenEventAccess()
    }

    @discardableResult
    public static func requestInputMonitoring() -> Bool {
        return CGRequestListenEventAccess()
    }

    /// Shows an alert prompting the user to grant accessibility access,
    /// then polls until permission is granted, calling the completion handler on main thread.
    public static func ensureAccessibility(completion: @escaping () -> Void) {
        if isAccessibilityGranted() {
            completion()
            return
        }

        SwitchFixLog.permissions.notice("Permissions: Accessibility not granted, requesting access")
        NSApplication.shared.activate(ignoringOtherApps: true)
        requestAccessibility()
        openAccessibilitySettings()
        pollForAccessibilityAccess(completion: completion)
    }

    public static func ensureInputMonitoring(completion: @escaping () -> Void) {
        if isInputMonitoringGranted() {
            completion()
            return
        }

        SwitchFixLog.permissions.notice("Permissions: Input Monitoring not granted, requesting access")
        NSApplication.shared.activate(ignoringOtherApps: true)
        _ = requestInputMonitoring()
        openInputMonitoringSettings()
        pollForInputMonitoringAccess(completion: completion)
    }

    public static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    public static func openInputMonitoringSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            if NSWorkspace.shared.open(url) {
                return
            }
        }

        if let fallback = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
            NSWorkspace.shared.open(fallback)
        }
    }

    private static func pollForAccessibilityAccess(completion: @escaping () -> Void) {
        guard !isAccessibilityGranted() else {
            SwitchFixLog.permissions.info("Permissions: Accessibility granted")
            completion()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            pollForAccessibilityAccess(completion: completion)
        }
    }

    private static func pollForInputMonitoringAccess(completion: @escaping () -> Void) {
        guard !isInputMonitoringGranted() else {
            SwitchFixLog.permissions.info("Permissions: Input Monitoring granted")
            completion()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            pollForInputMonitoringAccess(completion: completion)
        }
    }
}

public enum AccessibilityFocusState: Equatable {
    case unknown
    case secure
    case notSecure
}

public struct AccessibilityFocusResolution: Equatable {
    public let pid: pid_t
    public let epoch: UInt64
    public let state: AccessibilityFocusState

    public init(pid: pid_t, epoch: UInt64, state: AccessibilityFocusState) {
        self.pid = pid
        self.epoch = epoch
        self.state = state
    }
}

public final class AccessibilityFocusCoordinator {
    public typealias FocusInvalidation = (pid_t) -> UInt64?
    public typealias FocusResolutionHandler = (AccessibilityFocusResolution) -> Void

    private let queryQueue = DispatchQueue(label: "com.switchfix.accessibility", qos: .userInitiated)
    private let onFocusInvalidated: FocusInvalidation
    private let onResolved: FocusResolutionHandler
    private struct QueryIdentity: Equatable {
        var pid: pid_t = 0
        var epoch: UInt64 = 0
        var generation: UInt64 = 0
    }
    private let queryIdentity = OSAllocatedUnfairLock(initialState: QueryIdentity())
    private var observedPID: pid_t = 0
    private var observedEpoch: UInt64 = 0
    private var observer: AXObserver?
    private var applicationElement: AXUIElement?
    private var fallbackQuery: DispatchWorkItem?
    private var queryGeneration: UInt64 = 0
    private var unknownFocusRetryCount = 0
    private static let maximumUnknownFocusRetries = 8

    public init(
        onFocusInvalidated: @escaping FocusInvalidation,
        onResolved: @escaping FocusResolutionHandler
    ) {
        self.onFocusInvalidated = onFocusInvalidated
        self.onResolved = onResolved
    }

    public static func classifyFocus(
        role: String?,
        subrole: String?,
        subroleQueryDefinitive: Bool
    ) -> AccessibilityFocusState {
        guard role != nil else { return .unknown }
        if subrole == (kAXSecureTextFieldSubrole as String) {
            return .secure
        }
        return subroleQueryDefinitive ? .notSecure : .unknown
    }

    /// Falls back to macOS secure-input mode when an app does not expose its focused field.
    public static func resolveFocus(
        accessibilityState: AccessibilityFocusState,
        secureInputEnabled: Bool
    ) -> AccessibilityFocusState {
        guard accessibilityState == .unknown else { return accessibilityState }
        return secureInputEnabled ? .secure : .notSecure
    }

    public func observeApplication(pid: pid_t, epoch: UInt64) {
        runOnMain { [weak self] in
            guard let self else { return }
            self.stopObserving()
            self.observedPID = pid
            self.observedEpoch = epoch
            self.unknownFocusRetryCount = 0
            guard pid > 0 else { return }

            let application = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(application, 0.05)
            var newObserver: AXObserver?
            guard AXObserverCreate(pid, Self.observerCallback, &newObserver) == .success,
                  let newObserver else {
                self.scheduleQuery(pid: pid, epoch: epoch, delay: 0)
                return
            }

            let refcon = Unmanaged.passUnretained(self).toOpaque()
            let status = AXObserverAddNotification(
                newObserver,
                application,
                kAXFocusedUIElementChangedNotification as CFString,
                refcon
            )
            guard status == .success else {
                self.scheduleQuery(pid: pid, epoch: epoch, delay: 0)
                return
            }

            self.observer = newObserver
            self.applicationElement = application
            CFRunLoopAddSource(
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(newObserver),
                .commonModes
            )
            self.scheduleQuery(pid: pid, epoch: epoch, delay: 0)
        }
    }

    public func focusMayChange(pid: pid_t, epoch: UInt64) {
        runOnMain { [weak self] in
            guard let self, self.observedPID == pid else { return }
            self.observedEpoch = epoch
            self.unknownFocusRetryCount = 0
            self.scheduleQuery(pid: pid, epoch: epoch, delay: 0.025)
        }
    }

    public func requestSelectedText(
        pid: pid_t,
        epoch: UInt64,
        completion: @escaping (String?) -> Void
    ) {
        queryQueue.async {
            let text = Self.selectedText(pid: pid)
            DispatchQueue.main.async {
                completion(text)
            }
        }
    }

    /// Selection or, with none, the text around the caret of the focused element, in one query.
    /// `maxWordLength` nil reads only the selection.
    public func requestCaretContext(
        pid: pid_t,
        epoch: UInt64,
        maxWordLength: Int?,
        completion: @escaping (CaretContext) -> Void
    ) {
        queryQueue.async {
            let context = Self.caretContext(pid: pid, window: maxWordLength.map { $0 + 1 })
            DispatchQueue.main.async {
                completion(context)
            }
        }
    }

    /// The text before the caret of the focused field, to verify a correction before it
    /// deletes. Never turns AXManualAccessibility on (it runs on every correction): a field
    /// that is invisible without it reads as unavailable. The completion runs on the query queue.
    public func requestFieldText(
        pid: pid_t,
        length: Int,
        completion: @escaping (FieldTextProbe) -> Void
    ) {
        queryQueue.async {
            completion(Self.fieldText(pid: pid, window: length))
        }
    }

    public func stop() {
        runOnMain { [weak self] in self?.stopObserving() }
        Self.resetManualAccessibility()
    }

    private func handleObserverNotification() {
        guard observedPID > 0, let epoch = onFocusInvalidated(observedPID) else { return }
        observedEpoch = epoch
        scheduleQuery(pid: observedPID, epoch: epoch, delay: 0)
    }

    private func scheduleQuery(pid: pid_t, epoch: UInt64, delay: TimeInterval) {
        fallbackQuery?.cancel()
        queryGeneration &+= 1
        let generation = queryGeneration
        queryIdentity.withLock {
            $0 = QueryIdentity(pid: pid, epoch: epoch, generation: generation)
        }
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.queryQueue.async {
                guard self.queryIdentity.withLock({ identity in
                    identity == QueryIdentity(pid: pid, epoch: epoch, generation: generation)
                }) else { return }
                let state = Self.focusState(pid: pid)
                DispatchQueue.main.async {
                    guard self.queryGeneration == generation,
                          self.observedPID == pid,
                          self.observedEpoch == epoch else {
                        return
                    }
                    let resolvedState = Self.resolveFocus(
                        accessibilityState: state,
                        secureInputEnabled: IsSecureEventInputEnabled()
                    )
                    if state == .unknown,
                       self.unknownFocusRetryCount < Self.maximumUnknownFocusRetries {
                        self.unknownFocusRetryCount += 1
                        self.scheduleQuery(pid: pid, epoch: epoch, delay: 0.25)
                    } else {
                        self.unknownFocusRetryCount = 0
                    }
                    self.onResolved(AccessibilityFocusResolution(pid: pid, epoch: epoch, state: resolvedState))
                }
            }
        }
        fallbackQuery = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func stopObserving() {
        fallbackQuery?.cancel()
        fallbackQuery = nil
        queryGeneration &+= 1
        queryIdentity.withLock {
            $0 = QueryIdentity(generation: queryGeneration)
        }
        if let observer, let applicationElement {
            AXObserverRemoveNotification(
                observer,
                applicationElement,
                kAXFocusedUIElementChangedNotification as CFString
            )
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(observer),
                .commonModes
            )
        }
        observer = nil
        applicationElement = nil
        observedPID = 0
        observedEpoch = 0
    }

    private static func focusState(pid: pid_t) -> AccessibilityFocusState {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.05)
        guard let focused = focusedElement(application: application) else { return .unknown }
        AXUIElementSetMessagingTimeout(focused, 0.05)

        var roleValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            focused,
            kAXRoleAttribute as CFString,
            &roleValue
        ) == .success,
        let role = roleValue as? String else {
            return .unknown
        }

        var subroleValue: CFTypeRef?
        let subroleResult = AXUIElementCopyAttributeValue(
            focused,
            kAXSubroleAttribute as CFString,
            &subroleValue
        )
        let definitive = subroleResult == .success ||
            subroleResult == .noValue ||
            subroleResult == .attributeUnsupported
        return classifyFocus(
            role: role,
            subrole: subroleValue as? String,
            subroleQueryDefinitive: definitive
        )
    }

    private static func selectedText(pid: pid_t) -> String? {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.05)
        guard let focused = focusedElementRequestingTree(application: application, pid: pid) else { return nil }
        AXUIElementSetMessagingTimeout(focused, 0.05)

        var selectedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            focused,
            kAXSelectedTextAttribute as CFString,
            &selectedValue
        ) == .success,
        let selected = selectedValue as? String,
        !selected.isEmpty else {
            return nil
        }
        return selected
    }

    /// Above this size the whole `AXValue` is not fetched: serializing it blocks the target app.
    private static let maxValueFallbackLength = 20_000

    private static func caretContext(pid: pid_t, window: Int?) -> CaretContext {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.05)
        guard let focused = focusedElementRequestingTree(application: application, pid: pid) else { return .unavailable }
        AXUIElementSetMessagingTimeout(focused, 0.05)
        if let selected = selectedString(of: focused) {
            return .selection(selected)
        }
        guard let window else { return .unavailable }

        var rangeValue: CFTypeRef?
        var range = CFRange()
        guard AXUIElementCopyAttributeValue(focused, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success,
              let rangeValue,
              CFGetTypeID(rangeValue) == AXValueGetTypeID(),
              AXValueGetValue(rangeValue as! AXValue, .cfRange, &range),
              range.location >= 0 else {
            return .unavailable
        }
        // A selection the app did not report as text: nothing trustworthy to convert.
        guard range.length == 0 else { return .unavailable }

        let caret = range.location
        let start = max(0, caret - window)
        let total = intAttribute(kAXNumberOfCharactersAttribute, of: focused)
        if let total, caret > total { return .unavailable }
        // Ask for one character after the caret too, unless it is known to be at the end.
        let wantsNext = total.map { caret < $0 } ?? true
        let text: NSString
        if let fetched = string(of: focused, location: start, length: caret - start + (wantsNext ? 1 : 0)) {
            text = fetched
        } else if let total, total <= maxValueFallbackLength,
                  let value = stringAttribute(kAXValueAttribute, of: focused) as NSString?,
                  value.length == total {
            text = value.substring(with: NSRange(location: start, length: caret - start + (wantsNext ? 1 : 0))) as NSString
        } else {
            return .unavailable
        }
        let beforeLength = caret - start
        let before = text.substring(to: beforeLength)
        // Without the character count the caret may be at the end: then the request above
        // fails (as it does on a timeout) and nothing is converted, so the inside-a-word
        // check is never skipped.
        let next = text.length > beforeLength ? text.substring(from: beforeLength).first : nil
        return .caret(textBefore: before, startsAtTextStart: start == 0, next: next)
    }

    /// Above this size the whole `AXValue` is not fetched when verifying a correction.
    private static let maxFieldCheckValueLength = 4_000

    private static func fieldText(pid: pid_t, window: Int) -> FieldTextProbe {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.05)
        var focusError: AXError = .success
        guard let focused = focusedElement(application: application, error: &focusError) else {
            return .unavailable(transient: focusError == .cannotComplete)
        }
        AXUIElementSetMessagingTimeout(focused, 0.05)

        // The range first: a container (Chromium without its tree) may report a document
        // selection unrelated to the field, and some fields report a range but no selected text.
        var rangeValue: CFTypeRef?
        var range = CFRange()
        let rangeError = AXUIElementCopyAttributeValue(focused, kAXSelectedTextRangeAttribute as CFString, &rangeValue)
        guard rangeError == .success,
              let rangeValue,
              CFGetTypeID(rangeValue) == AXValueGetTypeID(),
              AXValueGetValue(rangeValue as! AXValue, .cfRange, &range),
              range.location >= 0 else {
            return .unavailable(transient: rangeError == .cannotComplete)
        }
        if range.length > 0 { return .selection(length: range.length) }

        let caret = range.location
        let start = max(0, caret - window)
        let total = intAttribute(kAXNumberOfCharactersAttribute, of: focused)
        // The caret moved before the text was updated.
        if let total, caret > total { return .unavailable(transient: true) }
        if caret == start { return .text(before: "") }

        var parameterRange = CFRange(location: start, length: caret - start)
        var stringError = AXError.failure
        if let parameter = AXValueCreate(.cfRange, &parameterRange) {
            var value: CFTypeRef?
            stringError = AXUIElementCopyParameterizedAttributeValue(
                focused,
                kAXStringForRangeParameterizedAttribute as CFString,
                parameter,
                &value
            )
            if stringError == .success, let string = value as? String {
                // A different length: the text and the caret disagree for now.
                return (string as NSString).length == caret - start
                    ? .text(before: string)
                    : .unavailable(transient: true)
            }
        }
        if let total, total <= maxFieldCheckValueLength,
           let value = stringAttribute(kAXValueAttribute, of: focused) as NSString? {
            guard value.length == total else { return .unavailable(transient: true) }
            return .text(before: value.substring(with: NSRange(location: start, length: caret - start)))
        }
        return .unavailable(transient: stringError == .cannotComplete)
    }

    /// `AXStringForRange`; nil unless the app returns exactly the requested length.
    private static func string(of element: AXUIElement, location: Int, length: Int) -> NSString? {
        guard length >= 0 else { return nil }
        if length == 0 { return "" }
        var range = CFRange(location: location, length: length)
        guard let parameter = AXValueCreate(.cfRange, &range) else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXStringForRangeParameterizedAttribute as CFString,
            parameter,
            &value
        ) == .success,
        let string = value as? String else { return nil }
        let result = string as NSString
        return result.length == length ? result : nil
    }

    private static func selectedString(of element: AXUIElement) -> String? {
        guard let selected = stringAttribute(kAXSelectedTextAttribute, of: element), !selected.isEmpty else {
            return nil
        }
        return selected
    }

    private static func stringAttribute(_ name: String, of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func intAttribute(_ name: String, of element: AXUIElement) -> Int? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return (value as? NSNumber)?.intValue
    }

    private static let manualAccessibilityAttribute = "AXManualAccessibility" as CFString
    /// How long AXManualAccessibility stays on after the last query that needed it.
    private static let manualAccessibilityLifetime: TimeInterval = 30
    private static let manualAccessibilityLock = NSLock()
    /// Apps SwitchFix turned AXManualAccessibility on for, with the generation of the
    /// pending switch-off (a newer query supersedes it).
    private static var manualAccessibilityOwned: [pid_t: UInt64] = [:]
    private static var manualAccessibilityGeneration: UInt64 = 0

    private static func withManualAccessibilityState<T>(_ body: (inout [pid_t: UInt64], inout UInt64) -> T) -> T {
        manualAccessibilityLock.lock()
        defer { manualAccessibilityLock.unlock() }
        return body(&manualAccessibilityOwned, &manualAccessibilityGeneration)
    }

    /// Electron/Chromium apps build their accessibility tree only on request
    /// (AXManualAccessibility); without it the focused field and its selection are invisible.
    /// Left on, it switches VS Code into screen-reader mode, makes Chrome heavier and shows
    /// a screen-reader banner in Qt apps. So it is set only when focus is invisible without it,
    /// and switched back off a while after the last such query, unless it was on already.
    /// Runs on the query queue, never on main: a query that switches it on waits up to
    /// 150 ms for the tree.
    private static func focusedElementRequestingTree(application: AXUIElement, pid: pid_t) -> AXUIElement? {
        var focusError: AXError = .success
        if let focused = focusedElement(application: application, error: &focusError), exposesText(focused) {
            // Keep ownership fresh while queries still need it on.
            if withManualAccessibilityState({ owned, _ in owned[pid] != nil }) {
                scheduleManualAccessibilityReset(pid: pid)
            }
            return focused
        }
        // A busy app timing out says nothing about its tree; a running screen reader or
        // enhanced UI means the tree is someone else's to switch off.
        guard focusError != .cannotComplete,
              !NSWorkspace.shared.isVoiceOverEnabled,
              !attributeIsTrue(application, "AXEnhancedUserInterface" as CFString) else {
            return focusedElement(application: application)
        }
        let alreadyOurs = withManualAccessibilityState { owned, _ in owned[pid] != nil }
        if !alreadyOurs, attributeIsTrue(application, manualAccessibilityAttribute) {
            // Someone else (an assistive tool) turned it on: never take it over.
            return focusedElement(application: application)
        }
        // Also when already ours: the app or another tool may have switched it off meanwhile.
        guard AXUIElementSetAttributeValue(application, manualAccessibilityAttribute, kCFBooleanTrue) == .success else {
            return focusedElement(application: application)
        }
        if !alreadyOurs {
            SwitchFixLog.permissions.info("AXManualAccessibility on pid=\(pid)")
        }
        scheduleManualAccessibilityReset(pid: pid)
        // The tree is built asynchronously: give it a moment.
        for _ in 0..<3 {
            if let focused = focusedElement(application: application), exposesText(focused) { return focused }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return focusedElement(application: application)
    }

    /// Chromium and Electron may return a container (window, group, web area) while the tree
    /// is off: only an element with a text selection range is a usable field.
    private static func exposesText(_ element: AXUIElement) -> Bool {
        var range: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &range) == .success
    }

    private static func attributeIsTrue(_ element: AXUIElement, _ attribute: CFString) -> Bool {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute, &value) == .success && (value as? Bool) == true
    }

    private static func scheduleManualAccessibilityReset(pid: pid_t) {
        let generation = withManualAccessibilityState { owned, generation -> UInt64 in
            generation &+= 1
            owned[pid] = generation
            return generation
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + manualAccessibilityLifetime) {
            let expired = withManualAccessibilityState { owned, _ -> Bool in
                guard owned[pid] == generation else { return false }
                owned[pid] = nil
                return true
            }
            if expired { switchOffManualAccessibility(pid: pid) }
        }
    }

    private static func switchOffManualAccessibility(pid: pid_t) {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.05)
        AXUIElementSetAttributeValue(application, manualAccessibilityAttribute, kCFBooleanFalse)
        SwitchFixLog.permissions.info("AXManualAccessibility off pid=\(pid)")
    }

    /// Switches AXManualAccessibility back off in every app SwitchFix turned it on for.
    public static func resetManualAccessibility() {
        let pids = withManualAccessibilityState { owned, _ -> [pid_t] in
            defer { owned.removeAll() }
            return Array(owned.keys)
        }
        pids.forEach(switchOffManualAccessibility)
    }

    private static func focusedElement(application: AXUIElement) -> AXUIElement? {
        var error: AXError = .success
        return focusedElement(application: application, error: &error)
    }

    private static func focusedElement(application: AXUIElement, error: inout AXError) -> AXUIElement? {
        var focusedValue: CFTypeRef?
        error = AXUIElementCopyAttributeValue(
            application,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        )
        guard error == .success,
        let focusedValue,
        CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else {
            return nil
        }
        return (focusedValue as! AXUIElement)
    }

    private func runOnMain(_ block: @escaping () -> Void) {
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async(execute: block)
        }
    }

    private static let observerCallback: AXObserverCallback = { _, _, _, refcon in
        guard let refcon else { return }
        let coordinator = Unmanaged<AccessibilityFocusCoordinator>.fromOpaque(refcon).takeUnretainedValue()
        coordinator.handleObserverNotification()
    }

    deinit {
        if Thread.isMainThread {
            stopObserving()
        }
    }
}

/// What surrounds the caret in the focused text element.
public enum CaretContext: Equatable, Sendable {
    /// A non-empty selection.
    case selection(String)
    /// No selection: a window of text before the caret and the character right after it.
    case caret(textBefore: String, startsAtTextStart: Bool, next: Character?)
    /// No accessible text element, or an answer that cannot be trusted.
    case unavailable
}

/// The focused field's text before the caret, read to verify a correction before it deletes.
public enum FieldTextProbe: Equatable, Sendable {
    /// No selection: the text right before the caret (a window, possibly cut at its start).
    case text(before: String)
    /// A non-empty selection (e.g. an inline autocomplete suggestion): Backspace would delete it.
    case selection(length: Int)
    /// No readable text field. `transient`: a timeout or an inconsistent answer that a
    /// retry may resolve; otherwise the app does not expose the text at all.
    case unavailable(transient: Bool)
}
