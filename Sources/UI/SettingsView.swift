import SwiftUI
import AppKit
import Combine
import Carbon
import Core
import Utils

// Helpers
func getModifierString(for modifiers: UInt64) -> String {
    var str = ""
    let flags = CGEventFlags(rawValue: modifiers)
    if flags.contains(.maskControl) { str += "⌃" }
    if flags.contains(.maskAlternate) { str += "⌥" }
    if flags.contains(.maskShift) { str += "⇧" }
    if flags.contains(.maskCommand) { str += "⌘" }
    return str
}

func getKeyString(for key: UInt16) -> String {
    switch key {
    case 49: return L10n.tr("Space")
    case 36: return "Return"
    case 48: return "Tab"
    case 53: return "Esc"
    case 51: return "Delete"
    case 57: return "Caps Lock"
    case 123: return L10n.tr("Left")
    case 124: return L10n.tr("Right")
    case 125: return L10n.tr("Down")
    case 126: return L10n.tr("Up")
    default:
        if let char = KeyCodeMapping.characterForKeyCode(key)?.uppercased(), !char.isEmpty {
            return char
        }
        return String(format: L10n.tr("Key %@"), "\(key)")
    }
}

/// How a hotkey reads in the UI, e.g. "⌃⇧Space" or "⌥ Option (tap)".
/// - Parameters:
///   - allowsModifierTap: read a lone Control/Option key code as a tap hotkey.
///   - marksTap: append the "(tap)" marker to a tap hotkey.
func hotkeyDisplayString(keyCode: UInt16, modifiers: UInt64, allowsModifierTap: Bool, marksTap: Bool = true) -> String {
    if allowsModifierTap, let tap = TapModifierHotkey.configured(keyCode: keyCode) {
        let name = getModifierString(for: tap.flag.rawValue) + " " + tap.name
        return marksTap ? String(format: L10n.tr("%@ (tap)"), name) : name
    }
    return getModifierString(for: modifiers) + getKeyString(for: keyCode)
}

class SettingsViewModel: ObservableObject {
    @Published var language: AppLanguage = PreferencesManager.shared.language {
        didSet { PreferencesManager.shared.language = language }
    }

    @Published var isEnabled: Bool = PreferencesManager.shared.isEnabled {
        didSet { PreferencesManager.shared.isEnabled = isEnabled }
    }

    @Published var launchAtLogin: Bool = PreferencesManager.shared.launchAtLogin {
        didSet { PreferencesManager.shared.launchAtLogin = launchAtLogin }
    }
    
    @Published var correctionMode: CorrectionMode = PreferencesManager.shared.correctionMode {
        didSet { PreferencesManager.shared.correctionMode = correctionMode }
    }
    
    /// Slider value (whole steps 0…4); stored as an Int position.
    @Published var detectionSensitivity = Double(PreferencesManager.shared.detectionSensitivity) {
        didSet { PreferencesManager.shared.detectionSensitivity = Int(detectionSensitivity.rounded()) }
    }

    @Published var hotkeyKeyCode: UInt16 = PreferencesManager.shared.hotkeyKeyCode {
        didSet { PreferencesManager.shared.hotkeyKeyCode = hotkeyKeyCode }
    }
    
    @Published var hotkeyModifiers: UInt64 = PreferencesManager.shared.hotkeyModifiers {
        didSet { PreferencesManager.shared.hotkeyModifiers = hotkeyModifiers }
    }
    
    @Published var revertHotkeyKeyCode: UInt16 = PreferencesManager.shared.revertHotkeyKeyCode {
        didSet { PreferencesManager.shared.revertHotkeyKeyCode = revertHotkeyKeyCode }
    }
    
    @Published var revertHotkeyModifiers: UInt64 = PreferencesManager.shared.revertHotkeyModifiers {
        didSet { PreferencesManager.shared.revertHotkeyModifiers = revertHotkeyModifiers }
    }

    init() {
        NotificationCenter.default.addObserver(self, selector: #selector(syncFromPreferences), name: .preferencesDidChange, object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func syncFromPreferences() {
        // Sync back only if different to avoid loops
        let prefs = PreferencesManager.shared
        if self.language != prefs.language {
            self.language = prefs.language
        }
        if self.isEnabled != prefs.isEnabled {
            self.isEnabled = prefs.isEnabled
        }
        if self.correctionMode != prefs.correctionMode {
            self.correctionMode = prefs.correctionMode
        }
        if Int(self.detectionSensitivity.rounded()) != prefs.detectionSensitivity {
            self.detectionSensitivity = Double(prefs.detectionSensitivity)
        }
        if self.hotkeyKeyCode != prefs.hotkeyKeyCode {
            self.hotkeyKeyCode = prefs.hotkeyKeyCode
        }
        if self.hotkeyModifiers != prefs.hotkeyModifiers {
            self.hotkeyModifiers = prefs.hotkeyModifiers
        }
        if self.revertHotkeyKeyCode != prefs.revertHotkeyKeyCode {
            self.revertHotkeyKeyCode = prefs.revertHotkeyKeyCode
        }
        if self.revertHotkeyModifiers != prefs.revertHotkeyModifiers {
            self.revertHotkeyModifiers = prefs.revertHotkeyModifiers
        }
    }
}

class RecorderState: ObservableObject {
    @Published var isRecording = false
    private var monitor: Any?
    // A lone tap-hotkey modifier press awaiting its release.
    private var pendingTap: TapModifierHotkey?

    deinit {
        stop()
    }

    /// - Parameter allowsModifierTap: also record a lone Control/Option press-and-release,
    ///   reported as the modifier's left-side key code with no modifiers.
    func start(allowsModifierTap: Bool, completion: @escaping (UInt16, UInt64) -> Void) {
        stop()
        isRecording = true

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self = self else { return event }

            // Handle CapsLock specifically
            if event.type == .flagsChanged && event.keyCode == 57 {
                completion(57, 0)
                self.stop()
                return nil
            }
            // Pass through other modifier transitions so app-wide modifier state stays intact.
            if event.type == .flagsChanged {
                guard allowsModifierTap, let tap = TapModifierHotkey.containing(keyCode: event.keyCode) else {
                    self.pendingTap = nil
                    return event
                }
                let flags = CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue))
                if flags.contains(tap.flag) {
                    let others = CGEventFlags([.maskCommand, .maskControl, .maskAlternate, .maskShift])
                        .subtracting(tap.flag)
                    self.pendingTap = flags.intersection(others).isEmpty ? tap : nil
                } else if self.pendingTap?.keyCode == tap.keyCode {
                    completion(tap.keyCode, 0)
                    self.stop()
                } else {
                    self.pendingTap = nil
                }
                return event
            }

            if event.type == .keyDown {
                // A key pressed while the modifier is held makes it a combo, not a tap.
                self.pendingTap = nil
                if event.keyCode == 53 { // ESC
                    self.stop()
                    return nil
                }
                
                var flags: UInt64 = 0
                if event.modifierFlags.contains(.command) { flags |= CGEventFlags.maskCommand.rawValue }
                if event.modifierFlags.contains(.control) { flags |= CGEventFlags.maskControl.rawValue }
                if event.modifierFlags.contains(.option) { flags |= CGEventFlags.maskAlternate.rawValue }
                if event.modifierFlags.contains(.shift) { flags |= CGEventFlags.maskShift.rawValue }
                
                completion(event.keyCode, flags)
                self.stop()
                return nil
            }
            
            return nil
        }
    }
    
    func stop() {
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
        pendingTap = nil
        isRecording = false
    }
}

struct HotkeyRecorder: View {
    @Binding var keyCode: UInt16
    @Binding var modifiers: UInt64
    /// Whether a lone Control/Option tap can be recorded (KeyboardMonitor supports it for the correction hotkey only).
    var allowsModifierTap = false
    @StateObject private var recorder = RecorderState()
    
    var displayText: String {
        if recorder.isRecording {
            return L10n.tr("Type Key...")
        }
        return hotkeyDisplayString(keyCode: keyCode, modifiers: modifiers, allowsModifierTap: allowsModifierTap)
    }
    
    var body: some View {
        Button(action: {
            if recorder.isRecording {
                recorder.stop()
            } else {
                recorder.start(allowsModifierTap: allowsModifierTap) { newKey, newMods in
                    self.keyCode = newKey
                    self.modifiers = newMods
                }
            }
        }) {
            Text(displayText)
                .frame(minWidth: 100)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(recorder.isRecording ? Color.accentColor.opacity(0.1) : Color.clear)
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(recorder.isRecording ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: 1)
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
}


// MARK: - Layout building blocks

/// A titled box of related settings.
struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    content
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// Secondary explanatory text under a setting.
struct SettingsNote: View {
    let text: String
    var color: Color = .secondary

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundColor(color)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Root of a Settings tab: fixed width, as tall as its content (the window follows
/// the height), rebuilt in full when the interface language changes.
struct SettingsTabContainer<Content: View>: View {
    let language: AppLanguage
    var width: CGFloat = SettingsTab.contentWidth
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            content
        }
        .padding(20)
        .frame(width: width, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        // Rebuild every section (including their own models) in the new language.
        .id(language)
    }
}

// MARK: - General

struct PermissionRow: View {
    let title: String
    let isGranted: Bool
    let openSettings: () -> Void

    var body: some View {
        HStack {
            Image(systemName: isGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(isGranted ? .green : .orange)
            Text(title)
            Spacer()
            if isGranted {
                Text(L10n.tr("Granted")).foregroundColor(.secondary)
            } else {
                Button(L10n.tr("Open System Settings…"), action: openSettings)
            }
        }
    }
}

struct GeneralSettingsView: View {
    @ObservedObject var model: SettingsViewModel
    @State private var accessibilityGranted = Permissions.isAccessibilityGranted()
    @State private var inputMonitoringGranted = Permissions.isInputMonitoringGranted()
    // Permissions are granted in System Settings, so poll while the tab is shown.
    private let permissionsTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        SettingsTabContainer(language: model.language) {
            SettingsSection(title: L10n.tr("General")) {
                Toggle(L10n.tr("Enable SwitchFix"), isOn: $model.isEnabled)
                Toggle(L10n.tr("Launch at Login"), isOn: $model.launchAtLogin)
                Picker(L10n.tr("Interface Language:"), selection: $model.language) {
                    ForEach(AppLanguage.allCases, id: \.self) { language in
                        Text(language.nativeName).tag(language)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }

            SettingsSection(title: L10n.tr("Permissions")) {
                PermissionRow(
                    title: L10n.tr("Accessibility"),
                    isGranted: accessibilityGranted,
                    openSettings: Permissions.openAccessibilitySettings
                )
                PermissionRow(
                    title: L10n.tr("Input Monitoring"),
                    isGranted: inputMonitoringGranted,
                    openSettings: Permissions.openInputMonitoringSettings
                )
                SettingsNote(text: L10n.tr("SwitchFix needs both to see what you type and replace mistyped words."))
            }
        }
        .onReceive(permissionsTimer) { _ in
            accessibilityGranted = Permissions.isAccessibilityGranted()
            inputMonitoringGranted = Permissions.isInputMonitoringGranted()
        }
    }
}

// MARK: - Correction

struct CorrectionSettingsView: View {
    @ObservedObject var model: SettingsViewModel

    private var correctionModeDescription: String {
        switch model.correctionMode {
        case .automatic:
            return L10n.tr("Auto-corrects on word boundaries (space, enter).")
        case .hotkey:
            return L10n.tr("Corrects only when triggered via hotkey.")
        case .layoutSwitch:
            return L10n.tr("Corrects the current word (or selection) when you switch the system keyboard layout.")
        }
    }

    private var sensitivityDescription: String {
        switch Int(model.detectionSensitivity.rounded()) {
        case 0: return L10n.tr("Corrects only clear cases.")
        case 1: return L10n.tr("Fewer corrections, fewer mistakes.")
        case 3: return L10n.tr("Corrects more words, occasionally by mistake.")
        case 4: return L10n.tr("Corrects as much as possible; undo mistakes with Revert Last.")
        default: return L10n.tr("Balanced (recommended).")
        }
    }

    var body: some View {
        SettingsTabContainer(language: model.language) {
            SettingsSection(title: L10n.tr("Correction Mode")) {
                Picker("", selection: $model.correctionMode) {
                    Text(L10n.tr("Automatic (Space / Enter)")).tag(CorrectionMode.automatic)
                    Text(L10n.tr("Hotkey Only")).tag(CorrectionMode.hotkey)
                    Text(L10n.tr("On Layout Switch")).tag(CorrectionMode.layoutSwitch)
                }
                .pickerStyle(RadioGroupPickerStyle())
                .labelsHidden()

                SettingsNote(text: correctionModeDescription)
            }

            SettingsSection(title: L10n.tr("Sensitivity")) {
                Slider(value: $model.detectionSensitivity, in: 0...4, step: 1) {
                    EmptyView()
                } minimumValueLabel: {
                    Text(L10n.tr("Cautious"))
                } maximumValueLabel: {
                    Text(L10n.tr("Bold"))
                }
                SettingsNote(text: sensitivityDescription)
            }
            .disabled(model.correctionMode != .automatic)

            SettingsSection(title: L10n.tr("Shortcuts")) {
                Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 12) {
                    GridRow {
                        Text(L10n.tr("Trigger Correction:"))
                            .gridColumnAlignment(.trailing)
                        HotkeyRecorder(
                            keyCode: $model.hotkeyKeyCode,
                            modifiers: $model.hotkeyModifiers,
                            allowsModifierTap: true
                        )
                    }

                    GridRow {
                        Text(L10n.tr("Revert Last:"))
                        HotkeyRecorder(
                            keyCode: $model.revertHotkeyKeyCode,
                            modifiers: $model.revertHotkeyModifiers
                        )
                    }
                }

                SettingsNote(text: L10n.tr("Trigger Correction can be a single Option or Control press: click its field, then press and release the key."))

                if TapModifierHotkey.configured(keyCode: model.hotkeyKeyCode)?.flag == .maskControl {
                    SettingsNote(
                        text: L10n.tr("Double-pressing Control is the macOS Dictation shortcut. Consider Option instead."),
                        color: .orange
                    )
                }

                if SystemHotkeyConflicts.hasCapsLockConflict(revertHotkeyKeyCode: model.revertHotkeyKeyCode) {
                    SettingsNote(
                        text: L10n.tr("macOS also switches input sources with Caps Lock, so Revert Last may not fire. Pick another key, or turn off switching input sources with Caps Lock in System Settings → Keyboard."),
                        color: .orange
                    )
                }
            }
        }
    }
}

// MARK: - About

struct AboutSettingsView: View {
    @ObservedObject var model: SettingsViewModel

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "–"
        guard let build = info?["CFBundleVersion"] as? String else { return short }
        return "\(short) (\(build))"
    }

    var body: some View {
        let sourcesByLayout = InputSourceManager.shared.availableInputSourcesByLayout()
        let currentID = InputSourceManager.shared.currentInputSourceID()
        let layouts = Layout.allCases.filter { !(sourcesByLayout[$0] ?? []).isEmpty }

        SettingsTabContainer(language: model.language) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text("SwitchFix").font(.title2).bold()
                    Text(String(format: L10n.tr("Version %@"), version))
                        .foregroundColor(.secondary)
                    if let url = URL(string: "https://github.com/8ui/SwitchFix") {
                        Link("github.com/8ui/SwitchFix", destination: url)
                    }
                }
            }

            SettingsSection(title: L10n.tr("Installed Layouts")) {
                if layouts.isEmpty {
                    Text(L10n.tr("No supported layouts found"))
                        .foregroundColor(.secondary)
                }
                ForEach(layouts, id: \.self) { layout in
                    HStack(alignment: .firstTextBaseline) {
                        Text(L10n.tr(layout.displayName))
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            ForEach(sourcesByLayout[layout] ?? [], id: \.id) { source in
                                HStack(spacing: 4) {
                                    if source.id == currentID {
                                        Image(systemName: "checkmark")
                                    }
                                    Text(source.name)
                                }
                                .foregroundColor(source.id == currentID ? .primary : .secondary)
                                .help(source.id)
                            }
                        }
                    }
                }
                SettingsNote(text: L10n.tr("SwitchFix corrects between English, Ukrainian and Russian layouts."))
            }
        }
    }
}
