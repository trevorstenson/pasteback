import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let captureHotkeyManager = HotkeyManager(id: 1)
    private let settingsHotkeyManager = HotkeyManager(id: 2)
    private let recallHotkeyManager = HotkeyManager(id: 3)
    private let historyHotkeyManager = HotkeyManager(id: 4)
    private let coordinator = CaptureCoordinator()
    private let hud = HUDPanelController()
    private let menuBar = MenuBarController()
    private let windows = WindowPresenter()
    private let builder = RepresentationBuilder()
    private let resolver = ActionResolver()
    private let settings = SettingsStore.shared

    private var defaultRepresentation: Representation { settings.defaultRepresentation }

    func applicationDidFinishLaunching(_ notification: Notification) {
        FrontmostAppTracker.shared.start()
        setupMenuBar()
        coordinator.onCaptured = { [weak self] capture in
            // Initial highlight = the default representation that was auto-copied.
            self?.presentHUD(for: capture, selectedRepresentation: self?.defaultRepresentation)
        }
        registerHotkey()
        NotificationCenter.default.addObserver(
            self, selector: #selector(settingsChanged), name: SettingsStore.didChange, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(clearHistoryRequested),
            name: SettingsView.clearHistoryRequested, object: nil)
        maybeShowOnboarding()
    }

    private func setupMenuBar() {
        menuBar.onCapture = { [weak self] in self?.triggerCapture() }
        menuBar.onShowLastCapture = { [weak self] in self?.showLastCapture() }
        menuBar.onRecopy = { [weak self] rep in self?.coordinator.recopy(as: rep) }
        menuBar.onOpenHistory = { [weak self] in self?.showHistory() }
        menuBar.onClearHistory = { [weak self] in self?.clearHistoryWithConfirmation() }
        menuBar.onOpenSettings = { [weak self] in self?.windows.showSettings() }
        menuBar.onOpenPermissions = { [weak self] in self?.windows.showPermissions() }
        menuBar.availableRepresentations = { [weak self] in
            guard let capture = self?.coordinator.lastCapture else { return [] }
            return self?.builder.availableRepresentations(for: capture) ?? []
        }
        menuBar.hasLastCapture = { [weak self] in self?.coordinator.lastCapture != nil }
        menuBar.hasHistory = { [weak self] in
            self?.coordinator.historyStore.records().isEmpty == false
        }
        menuBar.install()
    }

    private func registerHotkey() {
        captureHotkeyManager.register(settings.hotkey) { [weak self] in self?.triggerCapture() }
        settingsHotkeyManager.register(settings.settingsHotkey) { [weak self] in
            self?.hud.dismiss()
            self?.windows.showSettings()
        }
        if settings.recallHotkeyEnabled {
            recallHotkeyManager.register(settings.recallHotkey) { [weak self] in
                self?.showLastCapture()
            }
        } else {
            recallHotkeyManager.unregister()
        }
        if settings.historyHotkeyEnabled {
            historyHotkeyManager.register(settings.historyHotkey) { [weak self] in
                self?.hud.dismiss()
                self?.showHistory()
            }
        } else {
            historyHotkeyManager.unregister()
        }
    }

    private func triggerCapture() {
        hud.dismiss()
        coordinator.runCapture(primary: defaultRepresentation)
    }

    /// Resolves actions for a capture and shows the HUD. `selectedRepresentation`
    /// is highlighted when it matches a chip (nil = nothing highlighted, e.g.
    /// recalled from history without touching the clipboard).
    private func presentHUD(for capture: CapturedScreenshot,
                            selectedRepresentation: Representation?) {
        let actions = resolver.resolve(capture) { [weak self] rep in
            self?.coordinator.recopy(as: rep)
        }
        var selected: String?
        if let rep = selectedRepresentation {
            let id = "rep-\(rep.storageKey)"
            selected = actions.contains { $0.id == id } ? id
                : actions.first { $0.isStateful }?.id
        }
        hud.show(capture: capture, actions: actions, selectedID: selected)
    }

    /// The escape hatch: re-show the HUD for the last capture. The clipboard is
    /// untouched until a chip is tapped.
    private func showLastCapture() {
        guard let capture = coordinator.lastCapture else { return }
        presentHUD(for: capture,
                   selectedRepresentation: coordinator.lastWrittenRepresentation)
    }

    private func showHistory() {
        let store = coordinator.historyStore
        windows.showHistory { [weak self] in
            HistoryView(
                store: store,
                onRecopy: { record, rep in
                    guard let self, let capture = store.rehydrate(record) else { return }
                    self.coordinator.adopt(capture)
                    self.coordinator.recopy(as: rep)
                },
                onShowHUD: { record in
                    guard let self, let capture = store.rehydrate(record) else { return }
                    self.coordinator.adopt(capture)
                    self.presentHUD(for: capture, selectedRepresentation: nil)
                })
        }
    }

    private func clearHistoryWithConfirmation() {
        let alert = NSAlert()
        alert.messageText = "Clear capture history?"
        alert.informativeText = "Deletes all locally stored captures. This cannot be undone."
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            coordinator.historyStore.clear()
        }
    }

    @objc private func settingsChanged() { registerHotkey() }
    @objc private func clearHistoryRequested() { clearHistoryWithConfirmation() }

    private func maybeShowOnboarding() {
        let needScreen = settings.captureMode == .native && !PermissionService.hasScreenRecording()
        let needAX = !PermissionService.hasAccessibility()
        // Proactively trigger the system prompts (also registers the app in the
        // TCC lists) rather than making the user toggle manually.
        if needScreen { PermissionService.requestScreenRecording() }
        if needAX { PermissionService.requestAccessibility(prompt: true) }
        if needScreen || needAX { windows.showPermissions() }
    }
}
