import SwiftUI
import AppKit
import Carbon
import UniformTypeIdentifiers
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

class SettingsViewModel: ObservableObject {
    @Published var language: AppLanguage = PreferencesManager.shared.language {
        didSet { PreferencesManager.shared.language = language }
    }

    @Published var launchAtLogin: Bool = PreferencesManager.shared.launchAtLogin {
        didSet { PreferencesManager.shared.launchAtLogin = launchAtLogin }
    }
    
    @Published var correctionMode: CorrectionMode = PreferencesManager.shared.correctionMode {
        didSet { PreferencesManager.shared.correctionMode = correctionMode }
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
        if self.correctionMode != prefs.correctionMode {
            self.correctionMode = prefs.correctionMode
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
        if allowsModifierTap, let tap = TapModifierHotkey.configured(keyCode: keyCode) {
            return String(format: L10n.tr("%@ (tap)"), getModifierString(for: tap.flag.rawValue) + " " + tap.name)
        }
        let modStr = getModifierString(for: modifiers)
        let keyStr = getKeyString(for: keyCode)
        return modStr + keyStr
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

struct AppRow: Identifiable, Hashable {
    let id: String // bundle identifier
    let name: String
    let icon: NSImage?

    init(id: String, name: String, icon: NSImage?) {
        self.id = id
        self.name = name
        self.icon = icon
    }

    /// Resolves the display name and icon of an installed app, falling back to the bundle ID.
    init(bundleID: String) {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        self.init(
            id: bundleID,
            name: url.map { FileManager.default.displayName(atPath: $0.path) } ?? bundleID,
            icon: url.map { NSWorkspace.shared.icon(forFile: $0.path) }
        )
    }

    static func byName(_ lhs: AppRow, _ rhs: AppRow) -> Bool {
        lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
}

class ExclusionsViewModel: ObservableObject {
    @Published var apps: [AppRow] = []
    @Published var selection: Set<String> = []

    init() {
        reload()
        NotificationCenter.default.addObserver(self, selector: #selector(reload), name: .appFilterDidChange, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc func reload() {
        apps = AppFilter.shared.allBlacklisted.map(AppRow.init(bundleID:)).sorted(by: AppRow.byName)
        // Drop selections that no longer exist (e.g. removed via the menu-bar toggle).
        selection.formIntersection(apps.map { $0.id })
    }

    func addBundleIDs<S: Sequence>(_ bundleIDs: S) where S.Element == String {
        for bundleID in bundleIDs {
            AppFilter.shared.addToBlacklist(bundleID)
        }
        reload()
    }

    func removeSelected() {
        for bundleID in selection {
            AppFilter.shared.removeFromBlacklist(bundleID)
        }
        selection.removeAll()
        reload()
    }
}

class AppCompatibilityViewModel: ObservableObject {
    @Published var apps: [AppRow] = []
    @Published var selection: Set<String> = []
    // Stored overrides. Listed apps missing here were switched to Default in this
    // window; they stay in the list until it is reopened so the choice can be undone.
    @Published private(set) var modes: [String: AppPostMode] = [:]

    init() {
        modes = PreferencesManager.shared.postModeByApp
        apps = modes.keys.map(AppRow.init(bundleID:)).sorted(by: AppRow.byName)
    }

    func setMode(_ mode: AppPostMode?, for bundleID: String) {
        modes[bundleID] = mode
        PreferencesManager.shared.postModeByApp = modes
    }

    /// Newly added apps start with the session event tap, the mode that fixes Telegram.
    func addBundleIDs<S: Sequence>(_ bundleIDs: S) where S.Element == String {
        for bundleID in bundleIDs where !apps.contains(where: { $0.id == bundleID }) {
            apps.append(AppRow(bundleID: bundleID))
            modes[bundleID] = .session
        }
        apps.sort(by: AppRow.byName)
        PreferencesManager.shared.postModeByApp = modes
    }

    func removeSelected() {
        apps.removeAll { selection.contains($0.id) }
        for bundleID in selection {
            modes[bundleID] = nil
        }
        selection.removeAll()
        PreferencesManager.shared.postModeByApp = modes
    }
}

struct RunningAppPickerView: View {
    let runningApps: [AppRow]
    let emptyText: String
    let onAdd: (Set<String>) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selection: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.tr("Choose Running Apps")).font(.headline)

            if runningApps.isEmpty {
                Text(emptyText)
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .frame(width: 360, height: 260, alignment: .center)
            } else {
                List(runningApps, selection: $selection) { app in
                    HStack(spacing: 6) {
                        if let icon = app.icon {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 16, height: 16)
                        }
                        Text(app.name)
                    }
                    .tag(app.id)
                }
                .frame(width: 360, height: 260)
            }

            HStack {
                Spacer()
                Button(L10n.tr("Cancel")) { dismiss() }
                Button(L10n.tr("Add")) {
                    onAdd(selection)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selection.isEmpty)
            }
        }
        .padding(20)
    }
}

/// Bordered list of apps with +/- controls; apps are added from running apps or the Applications folder.
struct AppListEditor<Accessory: View>: View {
    let apps: [AppRow]
    @Binding var selection: Set<String>
    /// Shown in the running-apps picker when every running app is already listed.
    let allListedText: String
    let onAdd: ([String]) -> Void
    let onRemoveSelected: () -> Void
    @ViewBuilder let accessory: (AppRow) -> Accessory

    @State private var runningApps: [AppRow] = []
    @State private var showingRunningAppsPicker = false

    var body: some View {
        VStack(spacing: 0) {
            List(apps, selection: $selection) { app in
                HStack(spacing: 6) {
                    if let icon = app.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 16, height: 16)
                    }
                    Text(app.name)
                    Spacer()
                    accessory(app)
                }
                .tag(app.id)
            }
            .frame(height: 140)

            Divider()

            HStack(spacing: 0) {
                Menu {
                    Button(L10n.tr("Choose from Running Apps…")) {
                        refreshRunningApps()
                        showingRunningAppsPicker = true
                    }
                    Button(L10n.tr("Choose from Applications Folder…")) {
                        addAppFromFileSystem()
                    }
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 20, height: 20)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()

                Divider().frame(height: 12)

                Button(action: onRemoveSelected) {
                    Image(systemName: "minus")
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.borderless)
                .disabled(selection.isEmpty)

                Spacer()
            }
            .padding(4)
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
        .sheet(isPresented: $showingRunningAppsPicker) {
            RunningAppPickerView(runningApps: runningApps, emptyText: allListedText) { onAdd(Array($0)) }
        }
    }

    /// Refreshes the list of currently running apps eligible to be added (excludes ones already listed and SwitchFix itself).
    private func refreshRunningApps() {
        let alreadyListed = Set(apps.map { $0.id })
        let ownBundleID = Bundle.main.bundleIdentifier

        runningApps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> AppRow? in
                guard let bundleID = app.bundleIdentifier,
                      bundleID != ownBundleID,
                      !alreadyListed.contains(bundleID) else { return nil }
                return AppRow(id: bundleID, name: app.localizedName ?? bundleID, icon: app.icon)
            }
            .sorted(by: AppRow.byName)
    }

    /// Presents an Open panel (defaulting to /Applications, but browsable anywhere) to pick app bundles.
    private func addAppFromFileSystem() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        // Non-blocking: runModal() would spin a modal session on the main run loop
        // and steal frontmost-app focus from the capture pipeline.
        let onAdd = self.onAdd
        panel.begin { response in
            guard response == .OK else { return }
            onAdd(panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier })
        }
    }
}

struct ExcludedAppsView: View {
    @StateObject private var model = ExclusionsViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.tr("Excluded Apps")).font(.headline)
            Text(L10n.tr("SwitchFix won't correct text while these apps are active."))
                .font(.caption)
                .foregroundColor(.secondary)

            AppListEditor(
                apps: model.apps,
                selection: $model.selection,
                allListedText: L10n.tr("All running apps are already excluded."),
                onAdd: { model.addBundleIDs($0) },
                onRemoveSelected: model.removeSelected
            ) { app in
                Text(app.id)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct AppCompatibilityView: View {
    @StateObject private var model = AppCompatibilityViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.tr("App Compatibility")).font(.headline)
            Text(L10n.tr("Some apps, such as Telegram, ignore text sent directly to them. For these apps SwitchFix types corrections through the system event stream instead."))
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            AppListEditor(
                apps: model.apps,
                selection: $model.selection,
                allListedText: L10n.tr("All running apps are already listed."),
                onAdd: { model.addBundleIDs($0) },
                onRemoveSelected: model.removeSelected
            ) { app in
                Picker("", selection: Binding(
                    get: { model.modes[app.id] },
                    set: { model.setMode($0, for: app.id) }
                )) {
                    Text(L10n.tr("Default")).tag(AppPostMode?.none)
                    Text(L10n.tr("Session event tap")).tag(AppPostMode?.some(.session))
                    Text(L10n.tr("HID event tap")).tag(AppPostMode?.some(.hid))
                }
                .labelsHidden()
                .fixedSize()
            }
        }
    }
}

struct SettingsView: View {
    @StateObject private var model = SettingsViewModel()

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

    var body: some View {
        // Scrolls so the app lists never get clipped by the fixed window height.
        ScrollView {
            content
                .padding(30)
                .frame(maxWidth: .infinity, alignment: .leading)
                // Rebuild every section (including their own models) in the new language.
                .id(model.language)
        }
        .frame(width: 480, height: 700)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 24) {

            // LANGUAGE
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.tr("Language")).font(.headline)
                Picker("", selection: $model.language) {
                    ForEach(AppLanguage.allCases, id: \.self) { language in
                        Text(language.nativeName).tag(language)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }

            Divider()

            // GENERAL
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.tr("General")).font(.headline)
                Toggle(L10n.tr("Launch at Login"), isOn: $model.launchAtLogin)
            }
            
            Divider()
            
            // CORRECTION MODE
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.tr("Correction Mode")).font(.headline)
                
                Picker("", selection: $model.correctionMode) {
                    Text(L10n.tr("Automatic (Space / Enter)")).tag(CorrectionMode.automatic)
                    Text(L10n.tr("Hotkey Only")).tag(CorrectionMode.hotkey)
                    Text(L10n.tr("On Layout Switch")).tag(CorrectionMode.layoutSwitch)
                }
                .pickerStyle(RadioGroupPickerStyle())
                
                Text(correctionModeDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            // SHORTCUTS
            VStack(alignment: .leading, spacing: 16) {
                Text(L10n.tr("Shortcuts")).font(.headline)
                
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
                
                if TapModifierHotkey.configured(keyCode: model.hotkeyKeyCode)?.flag == .maskControl {
                    Text(L10n.tr("Double-pressing Control is the macOS Dictation shortcut. Consider Option instead."))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text(L10n.tr("Recommended: Set 'Revert Last' to Caps Lock to avoid conflicts."))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            // EXCLUDED APPS
            ExcludedAppsView()

            Divider()

            // APP COMPATIBILITY
            AppCompatibilityView()
        }
    }
}
