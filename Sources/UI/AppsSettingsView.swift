import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Utils

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

/// Every app with its own settings: excluded from correction (AppFilter) and/or
/// a text input override (postModeByApp).
class AppsSettingsViewModel: ObservableObject {
    @Published var apps: [AppRow] = []
    @Published var selection: Set<String> = []
    @Published private(set) var excluded: Set<String> = []
    // Listed apps back on the defaults (corrected, standard input) stay in the list
    // until the window is reopened, so the change can be undone.
    @Published private(set) var modes: [String: AppPostMode] = [:]

    init() {
        excluded = Set(AppFilter.shared.allBlacklisted)
        modes = PreferencesManager.shared.postModeByApp
        apps = excluded.union(modes.keys).map(AppRow.init(bundleID:)).sorted(by: AppRow.byName)
        NotificationCenter.default.addObserver(self, selector: #selector(syncExclusions), name: .appFilterDidChange, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func syncExclusions() {
        excluded = Set(AppFilter.shared.allBlacklisted)
        let listed = Set(apps.map { $0.id })
        let unlisted = excluded.subtracting(listed)
        if !unlisted.isEmpty {
            apps = (apps + unlisted.map(AppRow.init(bundleID:))).sorted(by: AppRow.byName)
        }
    }

    func isCorrected(_ bundleID: String) -> Bool {
        !excluded.contains(bundleID)
    }

    func setCorrected(_ corrected: Bool, for bundleID: String) {
        if corrected {
            AppFilter.shared.removeFromBlacklist(bundleID)
        } else {
            AppFilter.shared.addToBlacklist(bundleID)
        }
    }

    func setMode(_ mode: AppPostMode?, for bundleID: String) {
        modes[bundleID] = mode
        PreferencesManager.shared.postModeByApp = modes
    }

    /// Newly added apps start excluded from correction, the most common reason to list one.
    func addBundleIDs<S: Sequence>(_ bundleIDs: S) where S.Element == String {
        for bundleID in bundleIDs where !apps.contains(where: { $0.id == bundleID }) {
            apps.append(AppRow(bundleID: bundleID))
            AppFilter.shared.addToBlacklist(bundleID)
        }
        apps.sort(by: AppRow.byName)
    }

    /// Removing an app returns it to the defaults: corrected, standard text input.
    func removeSelected() {
        apps.removeAll { selection.contains($0.id) }
        for bundleID in selection {
            AppFilter.shared.removeFromBlacklist(bundleID)
            modes[bundleID] = nil
        }
        selection.removeAll()
        PreferencesManager.shared.postModeByApp = modes
    }
}

struct RunningAppPickerView: View {
    let runningApps: [AppRow]
    let onAdd: (Set<String>) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selection: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.tr("Choose Running Apps")).font(.headline)

            if runningApps.isEmpty {
                Text(L10n.tr("All running apps are already listed."))
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

struct AppsSettingsView: View {
    @ObservedObject var settings: SettingsViewModel
    @StateObject private var model = AppsSettingsViewModel()
    @State private var runningApps: [AppRow] = []
    @State private var showingRunningAppsPicker = false

    var body: some View {
        SettingsTabContainer(language: settings.language) {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.tr("Per-App Settings")).font(.headline)

                VStack(spacing: 0) {
                    table
                    Divider()
                    addRemoveBar
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )

                SettingsNote(text: L10n.tr("SwitchFix doesn't correct text in apps with Correct unchecked."))
                SettingsNote(text: L10n.tr("If an app loses corrected text (e.g. Telegram), set its Text Input to System Stream; if that doesn't help, try System Stream (HID)."))
            }
        }
        .sheet(isPresented: $showingRunningAppsPicker) {
            RunningAppPickerView(runningApps: runningApps) { model.addBundleIDs($0) }
        }
    }

    private var table: some View {
        Table(model.apps, selection: $model.selection) {
            TableColumn(L10n.tr("App")) { app in
                HStack(spacing: 6) {
                    if let icon = app.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 16, height: 16)
                    }
                    Text(app.name)
                }
                .help(app.id)
            }

            TableColumn(L10n.tr("Correct")) { app in
                Toggle("", isOn: Binding(
                    get: { model.isCorrected(app.id) },
                    set: { model.setCorrected($0, for: app.id) }
                ))
                .labelsHidden()
            }
            .width(70)

            TableColumn(L10n.tr("Text Input")) { app in
                Picker("", selection: Binding(
                    get: { model.modes[app.id] },
                    set: { model.setMode($0, for: app.id) }
                )) {
                    Text(L10n.tr("Standard")).tag(AppPostMode?.none)
                    Text(L10n.tr("System Stream")).tag(AppPostMode?.some(.session))
                    Text(L10n.tr("System Stream (HID)")).tag(AppPostMode?.some(.hid))
                }
                .labelsHidden()
            }
            .width(190)
        }
        .frame(height: 260)
    }

    private var addRemoveBar: some View {
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

            Button(action: model.removeSelected) {
                Image(systemName: "minus")
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.borderless)
            .disabled(model.selection.isEmpty)

            Spacer()
        }
        .padding(4)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    /// Refreshes the list of currently running apps eligible to be added (excludes ones already listed and SwitchFix itself).
    private func refreshRunningApps() {
        let alreadyListed = Set(model.apps.map { $0.id })
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
        let model = self.model
        panel.begin { response in
            guard response == .OK else { return }
            model.addBundleIDs(panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier })
        }
    }
}
