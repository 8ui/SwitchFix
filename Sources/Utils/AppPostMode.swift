import Foundation

/// Per-app override for how synthetic correction keystrokes are delivered.
/// Apps without an override get them posted straight to their process; some
/// toolkits (e.g. Qt in Telegram) drop those, so they go through the system
/// event stream instead.
public enum AppPostMode: String, CaseIterable {
    case session // session event tap
    case hid     // HID event tap

    /// Stored as [bundleID: rawValue], e.g.
    /// `defaults write com.switchfix.app SwitchFix_postModeByApp -dict com.tdesktop.Telegram session`.
    public static let defaultsKey = "SwitchFix_postModeByApp"

    /// Used until the overrides are first saved, so Telegram works out of the box.
    public static let defaultOverrides: [String: AppPostMode] = ["com.tdesktop.Telegram": .session]

    public static func overrides(in defaults: UserDefaults = .standard) -> [String: AppPostMode] {
        guard defaults.object(forKey: defaultsKey) != nil else { return defaultOverrides }
        let raw = defaults.dictionary(forKey: defaultsKey) as? [String: String] ?? [:]
        return raw.compactMapValues(AppPostMode.init(rawValue:))
    }
}
