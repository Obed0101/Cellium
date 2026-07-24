import AppKit
import SwiftUI
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let viewModel = BatteryViewModel()
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var terminationFlushStarted = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.statusItem = statusItem
        statusItem.button?.image = statusImage()
        statusItem.button?.image?.isTemplate = true
        statusItem.button?.toolTip = viewModel.language == .spanish
            ? "Estado de batería de Cellium"
            : "Cellium battery status"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked(_:))
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 438, height: 800)
        popover.contentViewController = NSHostingController(
            rootView: QuickPanelView(model: viewModel)
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(popoverDidClose(_:)),
            name: NSPopover.didCloseNotification,
            object: popover
        )
        observeRuntimeNotifications()

        configureProactiveNotifications()
        viewModel.onProactiveAlert = { [weak self] alert in
            self?.deliverProactiveAlert(alert)
        }
        viewModel.startMonitoring()
    }

    private func configureProactiveNotifications() {
        // A SwiftPM executable has no .app bundle proxy for UserNotifications.
        // Keep direct development launches safe; packaged app builds still ask once.
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func deliverProactiveAlert(_ alert: ProactiveAlert) {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "cellium.proactive.\(alert.identifier)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminationFlushStarted else { return .terminateLater }
        terminationFlushStarted = true
        Task { @MainActor [weak self] in
            await self?.viewModel.stopMonitoring()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        presentPopover(showingSettings: false, sender: statusItem?.button)
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard !terminationFlushStarted else { return }
        terminationFlushStarted = true
        Task { @MainActor [weak self] in
            await self?.viewModel.stopMonitoring()
        }
    }

    private func observeRuntimeNotifications() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceCenter.addObserver(
            self,
            selector: #selector(systemWillSleep(_:)),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        workspaceCenter.addObserver(
            self,
            selector: #selector(systemDidWake(_:)),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(powerStateDidChange(_:)),
            name: Notification.Name("NSProcessInfoPowerStateDidChangeNotification"),
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(thermalStateDidChange(_:)),
            name: ProcessInfo.thermalStateDidChangeNotification,
            object: nil
        )
    }

    @objc nonisolated private func systemWillSleep(_ notification: Notification) {
        Task { @MainActor [weak self] in
            self?.viewModel.handleSleep()
        }
    }

    @objc nonisolated private func systemDidWake(_ notification: Notification) {
        Task { @MainActor [weak self] in
            self?.viewModel.handleWake()
        }
    }

    @objc nonisolated private func powerStateDidChange(_ notification: Notification) {
        Task { @MainActor [weak self] in
            self?.viewModel.handlePowerStateChange()
        }
    }

    @objc nonisolated private func thermalStateDidChange(_ notification: Notification) {
        Task { @MainActor [weak self] in
            self?.viewModel.handleThermalStateChange()
        }
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showStatusMenu()
        } else {
            presentPopover(showingSettings: false, sender: sender)
        }
    }

    private func showStatusMenu() {
        guard let button = statusItem?.button else { return }
        let menu = makeStatusMenu()
        menu.popUp(
            positioning: nil,
            at: NSPoint(x: button.bounds.midX, y: button.bounds.minY),
            in: button
        )
    }

    @objc private func openPopoverFromMenu(_ sender: Any?) {
        presentPopover(showingSettings: false, sender: sender)
    }

    @objc private func openSettingsFromMenu(_ sender: Any?) {
        presentPopover(showingSettings: true, sender: sender)
    }

    @objc private func quitFromMenu(_ sender: Any?) {
        NSApp.terminate(sender)
    }

    private func presentPopover(showingSettings: Bool, sender: Any?) {
        guard let button = statusItem?.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        let wasShown = popover.isShown
        viewModel.setShowingSettings(showingSettings)

        if !wasShown {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKeyAndOrderFront(nil)
        } else {
            popover.contentViewController?.view.window?.makeKeyAndOrderFront(nil)
        }

        // Let AppKit draw the panel before starting sampling, process inspection
        // and SQLite work needed to refresh its contents.
        Task { @MainActor [weak self] in
            guard let self else { return }
            await Task.yield()
            guard self.popover.isShown else { return }
            self.viewModel.setPanelVisible(true)
            self.viewModel.refresh()
        }
    }


    private func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let openItem = NSMenuItem(
            title: localizedMenuTitle(spanish: "Abrir Cellium", english: "Open Cellium"),
            action: #selector(openPopoverFromMenu(_:)),
            keyEquivalent: "o"
        )
        openItem.target = self
        openItem.keyEquivalentModifierMask = [.command]
        openItem.image = NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)
        menu.addItem(openItem)

        let settingsItem = NSMenuItem(
            title: localizedMenuTitle(spanish: "Configuración…", english: "Settings…"),
            action: #selector(openSettingsFromMenu(_:)),
            keyEquivalent: ","
        )
        settingsItem.target = self
        settingsItem.keyEquivalentModifierMask = [.command]
        settingsItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: localizedMenuTitle(spanish: "Salir de Cellium", english: "Quit Cellium"),
            action: #selector(quitFromMenu(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = self
        quitItem.keyEquivalentModifierMask = [.command]
        quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        menu.addItem(quitItem)
        return menu
    }

    private func localizedMenuTitle(spanish: String, english: String) -> String {
        viewModel.language == .spanish ? spanish : english
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard popover.isShown else { return }
        popover.contentViewController?.view.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func popoverDidClose(_ notification: Notification) {
        viewModel.setPanelVisible(false)
    }


    private func statusImage() -> NSImage? {
        if let url = CelliumAppResources.bundle.url(forResource: "Cellium_symbol_white", withExtension: "svg"),
           let image = NSImage(contentsOf: url) {
            image.size = NSSize(width: 18, height: 18)
            return image
        }
        return NSImage(systemSymbolName: "battery.100", accessibilityDescription: "Cellium")
    }
}
