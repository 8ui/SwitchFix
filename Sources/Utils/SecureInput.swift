import AppKit
import Carbon

public extension Notification.Name {
    /// Posted on the main thread when Secure Event Input turns on or off.
    static let secureInputDidChange = Notification.Name("SwitchFix.secureInputDidChange")
}

/// Secure Event Input (password fields, 1Password, Terminal's Secure Keyboard Entry): while
/// it is on, the event tap receives no key presses, so the word buffer no longer matches
/// the screen and SwitchFix is effectively paused.
public enum SecureInput {
    public static func isEnabled() -> Bool {
        IsSecureEventInputEnabled()
    }

    /// Best effort: the session dictionary names the process that turned Secure Input on,
    /// but the PID may be stale or point at loginwindow.
    public static func ownerPID() -> pid_t? {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any],
              let pid = (session["kCGSSessionSecureInputPID"] as? NSNumber)?.int32Value,
              pid > 0 else {
            return nil
        }
        return pid
    }

    public static func ownerName() -> String? {
        guard let pid = ownerPID() else { return nil }
        guard let app = NSRunningApplication(processIdentifier: pid),
              app.activationPolicy == .regular else {
            // loginwindow keeps the PID after unlock, and background PIDs are often stale.
            return nil
        }
        return app.localizedName
    }
}

/// Polls Secure Event Input on the main run loop (there is no notification for it) and
/// reports transitions.
public final class SecureInputMonitor {
    private var timer: Timer?
    private var lastState: Bool
    private let onChange: (Bool) -> Void

    public init(onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
        lastState = SecureInput.isEnabled()
    }

    /// Short enough that a password prompt blinking on and off between two polls is rare.
    public func start(interval: TimeInterval = 0.5) {
        stop()
        lastState = SecureInput.isEnabled()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.poll()
        }
        timer.tolerance = interval / 4
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        let state = SecureInput.isEnabled()
        guard state != lastState else { return }
        lastState = state
        SwitchFixLog.app.notice(
            "secure input \(state ? "on" : "off") owner=\(state ? SecureInput.ownerName() ?? "unknown" : "-")"
        )
        onChange(state)
        NotificationCenter.default.post(name: .secureInputDidChange, object: nil)
    }
}
