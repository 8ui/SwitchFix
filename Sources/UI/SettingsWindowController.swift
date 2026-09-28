import AppKit
import SwiftUI

public enum SettingsTab: Int, CaseIterable {
    case general
    case correction
    case apps
    case about

    /// Width shared by all tabs, so switching tabs only changes the window height.
    static let contentWidth: CGFloat = 520

    var title: String {
        switch self {
        case .general: return L10n.tr("General")
        case .correction: return L10n.tr("Correction")
        case .apps: return L10n.tr("Apps")
        case .about: return L10n.tr("About")
        }
    }

    var symbolName: String {
        switch self {
        case .general: return "gearshape"
        case .correction: return "character.cursor.ibeam"
        case .apps: return "square.grid.2x2"
        case .about: return "info.circle"
        }
    }

    func rootView(model: SettingsViewModel) -> AnyView {
        switch self {
        case .general: return AnyView(GeneralSettingsView(model: model))
        case .correction: return AnyView(CorrectionSettingsView(model: model))
        case .apps: return AnyView(AppsSettingsView(settings: model))
        case .about: return AnyView(AboutSettingsView(model: model))
        }
    }
}

/// Toolbar-style tabs; the window takes the height of the selected tab's content.
final class SettingsTabViewController: NSTabViewController {
    private let model = SettingsViewModel()

    init() {
        super.init(nibName: nil, bundle: nil)
        tabStyle = .toolbar
        transitionOptions = []

        for tab in SettingsTab.allCases {
            let hosting = NSHostingController(rootView: tab.rootView(model: model))
            // Report the SwiftUI content size so the window can follow it.
            hosting.sizingOptions = .preferredContentSize
            let item = NSTabViewItem(viewController: hosting)
            item.image = NSImage(systemSymbolName: tab.symbolName, accessibilityDescription: nil)
            addTabViewItem(item)
        }
        applyTitles()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applyTitles),
            name: .preferencesDidChange,
            object: nil
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    var selectedTab: SettingsTab {
        get { SettingsTab(rawValue: selectedTabViewItemIndex) ?? .general }
        set { selectedTabViewItemIndex = newValue.rawValue }
    }

    /// Keeps tab labels and the window title in the current interface language.
    @objc private func applyTitles() {
        for (tab, item) in zip(SettingsTab.allCases, tabViewItems) {
            item.label = tab.title
            item.viewController?.title = tab.title
        }
        title = selectedTab.title
        view.window?.title = selectedTab.title
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        // The toolbar is installed once the view is in the window, which changes the chrome height.
        fitWindowToSelectedTab(animate: false)
    }

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        view.window?.title = selectedTab.title
        fitWindowToSelectedTab(animate: true)
    }

    override func preferredContentSizeDidChange(for viewController: NSViewController) {
        super.preferredContentSizeDidChange(for: viewController)
        guard viewController === tabView.selectedTabViewItem?.viewController else { return }
        fitWindowToSelectedTab(animate: true)
    }

    /// Resizes the window to the selected tab's content, keeping its top edge in place.
    func fitWindowToSelectedTab(animate: Bool) {
        guard let window = view.window,
              let contentView = window.contentView,
              let hosting = tabView.selectedTabViewItem?.viewController as? NSHostingController<AnyView> else { return }

        let size = hosting.sizeThatFits(in: NSSize(width: SettingsTab.contentWidth, height: 10_000))
        guard size.width > 0, size.height > 0 else { return }

        // Title bar and toolbar sit outside the content view.
        let chromeHeight = window.frame.height - contentView.frame.height
        var frame = window.frame
        let newHeight = (size.height + chromeHeight).rounded()
        guard abs(frame.height - newHeight) > 0.5 || abs(frame.width - size.width) > 0.5 else { return }
        frame.origin.y += frame.height - newHeight
        frame.size = NSSize(width: size.width, height: newHeight)
        window.setFrame(frame, display: true, animate: animate && window.isVisible)
    }
}

public class SettingsWindowController: NSObject {
    public static let shared = SettingsWindowController()

    private var windowController: NSWindowController?
    private var tabViewController: SettingsTabViewController?

    /// Shows the Settings window, switching to `tab` when given.
    public func showSettings(tab: SettingsTab? = nil) {
        if windowController == nil {
            createWindow()
        }
        if let tab {
            tabViewController?.selectedTab = tab
        }
        windowController?.showWindow(nil)
        windowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func createWindow() {
        let tabs = SettingsTabViewController()
        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.toolbarStyle = .preference
        window.title = tabs.selectedTab.title
        // Ensure window is released when closed so we can recreate it cleanly
        window.isReleasedWhenClosed = false
        tabs.fitWindowToSelectedTab(animate: false)
        window.center()

        windowController = NSWindowController(window: window)
        tabViewController = tabs

        // Observe window close to clear reference
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: window
        )
    }

    @objc private func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: window)
        }
        windowController = nil
        tabViewController = nil
    }
}
