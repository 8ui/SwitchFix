import AppKit
import Core
import Utils

public class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let menu: NSMenu
    private var enableMenuItem: NSMenuItem!
    private var modeHeaderItem: NSMenuItem!
    private var automaticModeItem: NSMenuItem!
    private var hotkeyModeItem: NSMenuItem!
    private var layoutSwitchModeItem: NSMenuItem!
    private var settingsMenuItem: NSMenuItem!
    private var quitMenuItem: NSMenuItem!
    /// Missing permissions and hotkey conflicts, shown above everything else.
    private var warningItems: [NSMenuItem] = []

    public override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menu = NSMenu()
        // Explicit isEnabled writes (e.g. the fallback section header) only take
        // effect when AppKit's auto-enablement is off.
        menu.autoenablesItems = false

        super.init()

        setupIcon()
        setupMenu()

        statusItem.menu = menu

        // The Settings window can toggle SwitchFix too.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(preferencesDidChange),
            name: .preferencesDidChange,
            object: nil
        )
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
        menu.delegate = self

        // Enable/Disable toggle (titles are set in refreshTitles)
        enableMenuItem = NSMenuItem(title: "", action: #selector(toggleEnabled), keyEquivalent: "")
        enableMenuItem.target = self
        menu.addItem(enableMenuItem)

        menu.addItem(NSMenuItem.separator())

        // Correction mode, inline so the current one is visible at a glance
        modeHeaderItem = Self.makeSectionHeader()
        menu.addItem(modeHeaderItem)

        automaticModeItem = NSMenuItem(title: "", action: #selector(setAutomaticMode), keyEquivalent: "")
        automaticModeItem.target = self
        menu.addItem(automaticModeItem)

        hotkeyModeItem = NSMenuItem(title: "", action: #selector(setHotkeyMode), keyEquivalent: "")
        hotkeyModeItem.target = self
        menu.addItem(hotkeyModeItem)

        layoutSwitchModeItem = NSMenuItem(title: "", action: #selector(setLayoutSwitchMode), keyEquivalent: "")
        layoutSwitchModeItem.target = self
        menu.addItem(layoutSwitchModeItem)

        menu.addItem(NSMenuItem.separator())

        // Settings
        settingsMenuItem = NSMenuItem(title: "", action: #selector(openSettings), keyEquivalent: ",")
        settingsMenuItem.target = self
        menu.addItem(settingsMenuItem)

        // Quit
        quitMenuItem = NSMenuItem(title: "", action: #selector(quit), keyEquivalent: "q")
        quitMenuItem.target = self
        menu.addItem(quitMenuItem)

        refreshTitles()
        refreshModeMenu()
        refreshWarnings()
        updateIcon()
    }

    private static func makeSectionHeader() -> NSMenuItem {
        if #available(macOS 14.0, *) {
            return NSMenuItem.sectionHeader(title: "")
        }
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    /// Applies the current interface language and hotkey to the fixed menu items.
    private func refreshTitles() {
        let prefs = PreferencesManager.shared
        enableMenuItem.title = L10n.tr("SwitchFix Enabled")
        enableMenuItem.state = prefs.isEnabled ? .on : .off
        modeHeaderItem.title = L10n.tr("Correction Mode")
        automaticModeItem.title = L10n.tr("Automatic")
        let hotkey = hotkeyDisplayString(
            keyCode: prefs.hotkeyKeyCode,
            modifiers: prefs.hotkeyModifiers,
            allowsModifierTap: true,
            marksTap: false
        )
        hotkeyModeItem.title = String(format: L10n.tr("Hotkey Only (%@)"), hotkey)
        layoutSwitchModeItem.title = L10n.tr("On Layout Switch")
        settingsMenuItem.title = L10n.tr("Settings...")
        quitMenuItem.title = L10n.tr("Quit SwitchFix")
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.showSettings()
    }

    @objc private func openCorrectionSettings() {
        SettingsWindowController.shared.showSettings(tab: .correction)
    }

    @objc private func toggleEnabled() {
        let prefs = PreferencesManager.shared
        prefs.isEnabled = !prefs.isEnabled
        enableMenuItem.state = prefs.isEnabled ? .on : .off
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

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    @objc private func preferencesDidChange() {
        updateIcon()
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

    /// Rebuilds the warnings block at the top of the menu and the menu bar tooltip.
    private func refreshWarnings() {
        warningItems.forEach { menu.removeItem($0) }
        warningItems.removeAll()

        var items: [NSMenuItem] = []

        let accessibilityGranted = Permissions.isAccessibilityGranted()
        let inputMonitoringGranted = Permissions.isInputMonitoringGranted()

        if !accessibilityGranted {
            items.append(makeWarningItem(
                title: L10n.tr("Grant Accessibility Permission…"),
                toolTip: L10n.tr("SwitchFix needs Accessibility access to monitor keyboard input and replace mistyped words."),
                action: #selector(openAccessibilityPermissionSettings)
            ))
        }

        if !inputMonitoringGranted {
            items.append(makeWarningItem(
                title: L10n.tr("Grant Input Monitoring Permission…"),
                toolTip: L10n.tr("SwitchFix needs Input Monitoring access to observe keystrokes."),
                action: #selector(openInputMonitoringPermissionSettings)
            ))
        }

        let hasConflict = SystemHotkeyConflicts.hasCapsLockConflict(
            revertHotkeyKeyCode: PreferencesManager.shared.revertHotkeyKeyCode
        )
        if hasConflict {
            items.append(makeWarningItem(
                title: L10n.tr("Fix CapsLock Conflict…"),
                toolTip: L10n.tr("CapsLock is configured both in SwitchFix (revert) and in macOS (input source switch)."),
                action: #selector(openCorrectionSettings)
            ))
        }

        if !items.isEmpty {
            items.append(NSMenuItem.separator())
        }
        for (index, item) in items.enumerated() {
            menu.insertItem(item, at: index)
        }
        warningItems = items

        if !accessibilityGranted || !inputMonitoringGranted {
            statusItem.button?.toolTip = L10n.tr("SwitchFix (missing permissions)")
        } else if hasConflict {
            statusItem.button?.toolTip = L10n.tr("SwitchFix (CapsLock conflict detected)")
        } else {
            statusItem.button?.toolTip = "SwitchFix"
        }
    }

    private func makeWarningItem(title: String, toolTip: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.toolTip = toolTip
        item.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)
        return item
    }

    @objc private func openAccessibilityPermissionSettings() {
        Permissions.openAccessibilitySettings()
    }

    @objc private func openInputMonitoringPermissionSettings() {
        Permissions.openInputMonitoringSettings()
    }

    public func menuWillOpen(_ menu: NSMenu) {
        if menu === self.menu {
            // Titles first: the language or hotkey may have changed in the Settings window.
            refreshTitles()
            refreshWarnings()
            refreshModeMenu()
            updateIcon()
        }
    }
}
