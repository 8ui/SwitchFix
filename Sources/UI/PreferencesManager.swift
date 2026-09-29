import Foundation
import CoreGraphics
import ServiceManagement
import Core
import Utils

public enum CorrectionMode: String {
    case automatic
    case hotkey
    case layoutSwitch
}

public class PreferencesManager {
    public static let shared = PreferencesManager()

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let isEnabled = "SwitchFix_isEnabled"
        static let launchAtLogin = "SwitchFix_launchAtLogin"
        static let correctionMode = "SwitchFix_correctionMode"
        static let hotkeyKeyCode = "SwitchFix_hotkeyKeyCode"
        static let hotkeyModifiers = "SwitchFix_hotkeyModifiers"
        static let revertHotkeyKeyCode = "SwitchFix_revertHotkeyKeyCode"
        static let revertHotkeyModifiers = "SwitchFix_revertHotkeyModifiers"
        static let language = "SwitchFix_language"
        static let detectionSensitivity = "SwitchFix_detectionSensitivity"
    }

    /// Detection sensitivity slider position: 0 (Cautious) … 4 (Bold); the middle is
    /// the calibrated default (`DetectionThresholds.forSensitivity`).
    public var detectionSensitivity: Int {
        get {
            let range = DetectionThresholds.sensitivityPositions
            guard let value = defaults.object(forKey: Keys.detectionSensitivity) as? Int else {
                return DetectionThresholds.defaultSensitivity
            }
            return min(max(value, range.lowerBound), range.upperBound)
        }
        set {
            let range = DetectionThresholds.sensitivityPositions
            let clamped = min(max(newValue, range.lowerBound), range.upperBound)
            guard clamped != detectionSensitivity else { return }
            defaults.set(clamped, forKey: Keys.detectionSensitivity)
            NotificationCenter.default.post(name: .preferencesDidChange, object: nil)
        }
    }

    /// Interface language (default: follows the system language).
    public var language: AppLanguage {
        get {
            guard let raw = defaults.string(forKey: Keys.language),
                  let language = AppLanguage(rawValue: raw) else {
                return .systemDefault
            }
            return language
        }
        set {
            guard newValue != self.language else { return }
            defaults.set(newValue.rawValue, forKey: Keys.language)
            NotificationCenter.default.post(name: .preferencesDidChange, object: nil)
        }
    }

    public var isEnabled: Bool {
        get { defaults.object(forKey: Keys.isEnabled) as? Bool ?? true }
        set {
            guard newValue != isEnabled else { return }
            defaults.set(newValue, forKey: Keys.isEnabled)
            NotificationCenter.default.post(name: .preferencesDidChange, object: nil)
        }
    }

    public var launchAtLogin: Bool {
        get { defaults.bool(forKey: Keys.launchAtLogin) }
        set {
            defaults.set(newValue, forKey: Keys.launchAtLogin)
            NotificationCenter.default.post(name: .preferencesDidChange, object: nil)
            
            if #available(macOS 13.0, *) {
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    SwitchFixLog.preferences.error("Failed to toggle launch at login: \(error)")
                }
            }
        }
    }

    public var correctionMode: CorrectionMode {
        get {
            guard let raw = defaults.string(forKey: Keys.correctionMode),
                  let mode = CorrectionMode(rawValue: raw) else {
                return .automatic
            }
            return mode
        }
        set {
            guard newValue != self.correctionMode else { return }
            defaults.set(newValue.rawValue, forKey: Keys.correctionMode)
            NotificationCenter.default.post(name: .preferencesDidChange, object: nil)
        }
    }

    /// Hotkey virtual key code (default: Space = 49)
    public var hotkeyKeyCode: UInt16 {
        get {
            // Key code 0 is the letter "A"; only fall back when the key is truly unset.
            guard let val = defaults.object(forKey: Keys.hotkeyKeyCode) as? Int else { return 49 }
            return UInt16(truncatingIfNeeded: val)
        }
        set {
            guard newValue != self.hotkeyKeyCode else { return }
            defaults.set(Int(newValue), forKey: Keys.hotkeyKeyCode)
            NotificationCenter.default.post(name: .preferencesDidChange, object: nil)
        }
    }

    /// Hotkey modifier flags as raw UInt64 (default: Ctrl+Shift)
    public var hotkeyModifiers: UInt64 {
        get {
            let val = defaults.object(forKey: Keys.hotkeyModifiers) as? UInt64
            // Default: Control + Shift
            return val ?? (CGEventFlags.maskControl.rawValue | CGEventFlags.maskShift.rawValue)
        }
        set {
            guard newValue != self.hotkeyModifiers else { return }
            defaults.set(newValue, forKey: Keys.hotkeyModifiers)
            NotificationCenter.default.post(name: .preferencesDidChange, object: nil)
        }
    }

    /// Revert-hotkey virtual key code (default: CapsLock = 57)
    public var revertHotkeyKeyCode: UInt16 {
        get {
            // Key code 0 is the letter "A"; only fall back when the key is truly unset.
            guard let val = defaults.object(forKey: Keys.revertHotkeyKeyCode) as? Int else { return 57 }
            return UInt16(truncatingIfNeeded: val)
        }
        set {
            guard newValue != self.revertHotkeyKeyCode else { return }
            defaults.set(Int(newValue), forKey: Keys.revertHotkeyKeyCode)
            NotificationCenter.default.post(name: .preferencesDidChange, object: nil)
        }
    }

    /// Revert-hotkey modifier flags as raw UInt64 (default: none)
    public var revertHotkeyModifiers: UInt64 {
        get {
            let val = defaults.object(forKey: Keys.revertHotkeyModifiers) as? UInt64
            return val ?? 0
        }
        set {
            guard newValue != self.revertHotkeyModifiers else { return }
            defaults.set(newValue, forKey: Keys.revertHotkeyModifiers)
            NotificationCenter.default.post(name: .preferencesDidChange, object: nil)
        }
    }

    /// Per-app keystroke delivery overrides [bundleID: mode]; apps not listed use the default.
    public var postModeByApp: [String: AppPostMode] {
        get { AppPostMode.overrides(in: defaults) }
        set {
            guard newValue != self.postModeByApp else { return }
            defaults.set(newValue.mapValues(\.rawValue), forKey: AppPostMode.defaultsKey)
            NotificationCenter.default.post(name: .preferencesDidChange, object: nil)
        }
    }

    private init() {}
}

public extension Notification.Name {
    static let preferencesDidChange = Notification.Name("SwitchFix_PreferencesDidChange")
}
