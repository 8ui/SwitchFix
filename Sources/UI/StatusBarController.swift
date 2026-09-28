import AppKit
import ServiceManagement
import Core
import Utils

public class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let menu: NSMenu
    private var languageMenuItem: NSMenuItem!
    private var enableMenuItem: NSMenuItem!
    private var modeMenuItem: NSMenuItem!
    private var automaticModeItem: NSMenuItem!
    private var hotkeyModeItem: NSMenuItem!
    private var layoutSwitchModeItem: NSMenuItem!
    private var appFilterMenuItem: NSMenuItem!
    private var installedLayoutsMenuItem: NSMenuItem!
    private var settingsMenuItem: NSMenuItem!
    private var loginMenuItem: NSMenuItem!
    private var quitMenuItem: NSMenuItem!
    private var conflictMenuItem: NSMenuItem?
    private var conflictSeparatorItem: NSMenuItem?
    private var permissionMenuItems: [NSMenuItem] = []
    private var permissionSeparatorItem: NSMenuItem?

    public override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menu = NSMenu()
        // Explicit isEnabled writes (e.g. "App Filtering Unavailable") only take
        // effect when AppKit's auto-enablement is off.
        menu.autoenablesItems = false

        super.init()

        setupIcon()
        setupMenu()

        statusItem.menu = menu
    }

    private func setupIcon() {
        guard let button = statusItem.button else { return }

        // Create a template image with "Ab" text for menu bar
        let image = NSImage(size: NSSize(width: 22, height: 22), flipped: false) { rect in
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: NSColor.black
            ]
            let str = NSAttributedString(string: "Ab", attributes: attrs)
            let strSize = str.size()
            let origin = NSPoint(
                x: (rect.width - strSize.width) / 2,
                y: (rect.height - strSize.height) / 2
            )
            str.draw(at: origin)
            return true
        }
        image.isTemplate = true
        button.image = image
        button.toolTip = "SwitchFix"
    }

    private func setupMenu() {
        let prefs = PreferencesManager.shared

        menu.delegate = self

        // Interface language submenu (titles are set in refreshTitles)
        let languageMenu = NSMenu()
        for language in AppLanguage.allCases {
            let item = NSMenuItem(title: language.nativeName, action: #selector(setLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = language.rawValue
            languageMenu.addItem(item)
        }
        languageMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        languageMenuItem.submenu = languageMenu
        menu.addItem(languageMenuItem)

        menu.addItem(NSMenuItem.separator())

        // Enable/Disable toggle
        enableMenuItem = NSMenuItem(title: "", action: #selector(toggleEnabled), keyEquivalent: "")
        enableMenuItem.target = self
        menu.addItem(enableMenuItem)

        menu.addItem(NSMenuItem.separator())

        // Correction mode submenu
        let modeMenu = NSMenu()
        automaticModeItem = NSMenuItem(title: "", action: #selector(setAutomaticMode), keyEquivalent: "")
        automaticModeItem.target = self
        modeMenu.addItem(automaticModeItem)

        hotkeyModeItem = NSMenuItem(title: "", action: #selector(setHotkeyMode), keyEquivalent: "")
        hotkeyModeItem.target = self
        modeMenu.addItem(hotkeyModeItem)

        layoutSwitchModeItem = NSMenuItem(title: "", action: #selector(setLayoutSwitchMode), keyEquivalent: "")
        layoutSwitchModeItem.target = self
        modeMenu.addItem(layoutSwitchModeItem)

        modeMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        modeMenuItem.submenu = modeMenu
        menu.addItem(modeMenuItem)

        menu.addItem(NSMenuItem.separator())

        // App filter toggle for current app
        appFilterMenuItem = NSMenuItem(title: L10n.tr("Enable in Current App"), action: #selector(toggleCurrentAppFilter), keyEquivalent: "")
        appFilterMenuItem.target = self
        menu.addItem(appFilterMenuItem)

        menu.addItem(NSMenuItem.separator())

        // Installed layouts submenu
        installedLayoutsMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        installedLayoutsMenuItem.submenu = buildInstalledLayoutsMenu()
        menu.addItem(installedLayoutsMenuItem)

        menu.addItem(NSMenuItem.separator())

        // Settings
        settingsMenuItem = NSMenuItem(title: "", action: #selector(openSettings), keyEquivalent: ",")
        settingsMenuItem.target = self
        menu.addItem(settingsMenuItem)

        menu.addItem(NSMenuItem.separator())
        
        // Launch at Login
        loginMenuItem = NSMenuItem(title: "", action: #selector(toggleLaunchAtLogin(_:)), keyEquivalent: "")
        loginMenuItem.target = self
        loginMenuItem.state = prefs.launchAtLogin ? .on : .off
        menu.addItem(loginMenuItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        quitMenuItem = NSMenuItem(title: "", action: #selector(quit), keyEquivalent: "q")
        quitMenuItem.target = self
        menu.addItem(quitMenuItem)

        refreshTitles()
        refreshModeMenu()
        refreshSystemHotkeyConflictIndicator()
        refreshPermissionIndicators()
    }

    /// Applies the current interface language to the fixed menu items.
    private func refreshTitles() {
        let prefs = PreferencesManager.shared
        languageMenuItem.title = L10n.tr("Language")
        for item in languageMenuItem.submenu?.items ?? [] {
            item.state = item.representedObject as? String == prefs.language.rawValue ? .on : .off
        }
        enableMenuItem.title = prefs.isEnabled ? L10n.tr("Disable") : L10n.tr("Enable")
        modeMenuItem.title = L10n.tr("Correction Mode")
        automaticModeItem.title = L10n.tr("Automatic")
        hotkeyModeItem.title = L10n.tr("Hotkey Only")
        layoutSwitchModeItem.title = L10n.tr("On Layout Switch")
        installedLayoutsMenuItem.title = L10n.tr("Installed Layouts")
        settingsMenuItem.title = L10n.tr("Settings...")
        loginMenuItem.title = L10n.tr("Launch at Login")
        quitMenuItem.title = L10n.tr("Quit SwitchFix")
    }

    @objc private func setLanguage(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let language = AppLanguage(rawValue: raw) else { return }
        PreferencesManager.shared.language = language
        refreshTitles()
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.showSettings()
    }
    
    @objc private func toggleEnabled() {
        let prefs = PreferencesManager.shared
        prefs.isEnabled = !prefs.isEnabled
        enableMenuItem.title = prefs.isEnabled ? L10n.tr("Disable") : L10n.tr("Enable")
        updateIcon()
    }

    @objc private func setAutomaticMode() {
        PreferencesManager.shared.correctionMode = .automatic
        refreshModeMenu()
    }

    @objc private func setHotkeyMode() {
        PreferencesManager.shared.correctionMode = .hotkey
        refreshModeMenu()
    }

    @objc private func setLayoutSwitchMode() {
        PreferencesManager.shared.correctionMode = .layoutSwitch
        refreshModeMenu()
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        let prefs = PreferencesManager.shared
        prefs.launchAtLogin = !prefs.launchAtLogin
        // The sender state will update in menuWillOpen, but we can update it immediately too for feedback
        sender.state = prefs.launchAtLogin ? .on : .off
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func refreshModeMenu() {
        let mode = PreferencesManager.shared.correctionMode
        automaticModeItem.state = mode == .automatic ? .on : .off
        hotkeyModeItem.state = mode == .hotkey ? .on : .off
        layoutSwitchModeItem.state = mode == .layoutSwitch ? .on : .off
    }

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        let isEnabled = PreferencesManager.shared.isEnabled
        button.appearsDisabled = !isEnabled
    }

    @objc private func toggleCurrentAppFilter(_ sender: NSMenuItem) {
        guard let bundleID = sender.representedObject as? String else { return }
        if AppFilter.shared.isBlacklisted(bundleID) {
            AppFilter.shared.removeFromBlacklist(bundleID)
        } else {
            AppFilter.shared.addToBlacklist(bundleID)
        }
        refreshAppFilterMenuItem()
    }

    private func refreshAppFilterMenuItem() {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier else {
            appFilterMenuItem.title = L10n.tr("App Filtering Unavailable")
            appFilterMenuItem.isEnabled = false
            appFilterMenuItem.representedObject = nil
            return
        }

        let name = app.localizedName ?? L10n.tr("Current App")
        appFilterMenuItem.isEnabled = true
        appFilterMenuItem.representedObject = bundleID

        if AppFilter.shared.isBlacklisted(bundleID) {
            appFilterMenuItem.title = String(format: L10n.tr("Enable in %@"), name)
        } else {
            appFilterMenuItem.title = String(format: L10n.tr("Disable in %@"), name)
        }
    }

    private func buildInstalledLayoutsMenu() -> NSMenu {
        let sub = NSMenu()
        let sourcesByLayout = InputSourceManager.shared.availableInputSourcesByLayout()
        let currentID = InputSourceManager.shared.currentInputSourceID()

        var added = false
        for layout in Layout.allCases {
            guard let sources = sourcesByLayout[layout], !sources.isEmpty else { continue }
            let layoutItem = NSMenuItem(title: L10n.tr(layout.displayName), action: nil, keyEquivalent: "")
            let layoutMenu = NSMenu()
            for source in sources {
                let item = NSMenuItem(title: source.name, action: nil, keyEquivalent: "")
                item.toolTip = source.id
                if source.id == currentID {
                    item.state = .on
                }
                layoutMenu.addItem(item)
            }
            layoutItem.submenu = layoutMenu
            sub.addItem(layoutItem)
            added = true
        }

        if !added {
            let item = NSMenuItem(title: L10n.tr("No supported layouts found"), action: nil, keyEquivalent: "")
            item.isEnabled = false
            sub.addItem(item)
        }

        return sub
    }

    private func refreshInstalledLayoutsMenu() {
        installedLayoutsMenuItem.submenu = buildInstalledLayoutsMenu()
    }

    private func refreshPermissionIndicators() {
        permissionMenuItems.forEach { menu.removeItem($0) }
        permissionMenuItems.removeAll()
        if let separator = permissionSeparatorItem {
            menu.removeItem(separator)
            permissionSeparatorItem = nil
        }

        var itemsToInsert: [NSMenuItem] = []

        if !Permissions.isAccessibilityGranted() {
            let item = NSMenuItem(
                title: L10n.tr("Grant Accessibility Permission…"),
                action: #selector(openAccessibilityPermissionSettings),
                keyEquivalent: ""
            )
            item.target = self
            item.toolTip = L10n.tr("SwitchFix needs Accessibility access to monitor keyboard input and replace mistyped words.")
            itemsToInsert.append(item)
        }

        if !Permissions.isInputMonitoringGranted() {
            let item = NSMenuItem(
                title: L10n.tr("Grant Input Monitoring Permission…"),
                action: #selector(openInputMonitoringPermissionSettings),
                keyEquivalent: ""
            )
            item.target = self
            item.toolTip = L10n.tr("SwitchFix needs Input Monitoring access to observe keystrokes.")
            itemsToInsert.append(item)
        }

        guard !itemsToInsert.isEmpty else {
            updateMenuBarTooltipForPermissions()
            return
        }

        for (index, item) in itemsToInsert.enumerated() {
            menu.insertItem(item, at: index)
        }
        let separator = NSMenuItem.separator()
        menu.insertItem(separator, at: itemsToInsert.count)

        permissionMenuItems = itemsToInsert
        permissionSeparatorItem = separator

        updateMenuBarTooltipForPermissions()
    }

    private func updateMenuBarTooltipForPermissions() {
        guard permissionMenuItems.isEmpty else {
            statusItem.button?.toolTip = L10n.tr("SwitchFix (missing permissions)")
            return
        }

        let hasConflict = SystemHotkeyConflicts.hasCapsLockConflict(
            revertHotkeyKeyCode: PreferencesManager.shared.revertHotkeyKeyCode
        )
        statusItem.button?.toolTip = hasConflict
            ? L10n.tr("SwitchFix (CapsLock conflict detected)")
            : "SwitchFix"
    }

    @objc private func openAccessibilityPermissionSettings() {
        Permissions.openAccessibilitySettings()
    }

    @objc private func openInputMonitoringPermissionSettings() {
        Permissions.openInputMonitoringSettings()
    }

    private func refreshSystemHotkeyConflictIndicator() {
        let hasConflict = SystemHotkeyConflicts.hasCapsLockConflict(
            revertHotkeyKeyCode: PreferencesManager.shared.revertHotkeyKeyCode
        )

        if hasConflict {
            if conflictMenuItem == nil {
                let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
                item.isEnabled = false

                let separator = NSMenuItem.separator()
                menu.insertItem(item, at: 0)
                menu.insertItem(separator, at: 1)
                conflictMenuItem = item
                conflictSeparatorItem = separator
            }
            // Retitled on every refresh so a language switch reaches an existing item.
            conflictMenuItem?.title = L10n.tr("Warning: CapsLock conflicts with macOS input switching")
            conflictMenuItem?.toolTip = L10n.tr("CapsLock is configured both in SwitchFix (revert) and in macOS (input source switch).")
            statusItem.button?.toolTip = L10n.tr("SwitchFix (CapsLock conflict detected)")
        } else {
            if let item = conflictMenuItem {
                menu.removeItem(item)
                conflictMenuItem = nil
            }
            if let separator = conflictSeparatorItem {
                menu.removeItem(separator)
                conflictSeparatorItem = nil
            }
            statusItem.button?.toolTip = "SwitchFix"
        }
    }

    public func menuWillOpen(_ menu: NSMenu) {
        if menu === self.menu {
            // Titles first: the language may have changed in the Settings window.
            refreshTitles()
            refreshSystemHotkeyConflictIndicator()
            refreshPermissionIndicators()
            refreshAppFilterMenuItem()
            refreshInstalledLayoutsMenu()
            refreshModeMenu()
            
            // Refresh Launch at Login state
            loginMenuItem.state = PreferencesManager.shared.launchAtLogin ? .on : .off
            updateIcon()
        }
    }
}
