import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let hotkeyManager = HotkeyManager()
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
            guard let self else { return }
            let actions = self.resolver.resolve(capture) { rep in
                self.coordinator.recopy(as: rep)
            }
            // Initial highlight = the default representation that was auto-copied.
            let defaultID = "rep-\(self.defaultRepresentation.storageKey)"
            let selected = actions.contains { $0.id == defaultID } ? defaultID
                : actions.first { $0.isStateful }?.id
            self.hud.show(actions: actions, selectedID: selected)
        }
        registerHotkey()
        NotificationCenter.default.addObserver(
            self, selector: #selector(settingsChanged), name: SettingsStore.didChange, object: nil)
        maybeShowOnboarding()
    }

    private func setupMenuBar() {
        menuBar.onCapture = { [weak self] in self?.triggerCapture() }
        menuBar.onRecopy = { [weak self] rep in self?.coordinator.recopy(as: rep) }
        menuBar.onOpenSettings = { [weak self] in self?.windows.showSettings() }
        menuBar.onOpenPermissions = { [weak self] in self?.windows.showPermissions() }
        menuBar.availableRepresentations = { [weak self] in
            guard let capture = self?.coordinator.lastCapture else { return [] }
            return self?.builder.availableRepresentations(for: capture) ?? []
        }
        menuBar.install()
    }

    private func registerHotkey() {
        hotkeyManager.register(settings.hotkey) { [weak self] in self?.triggerCapture() }
    }

    private func triggerCapture() {
        hud.dismiss()
        coordinator.runCapture(primary: defaultRepresentation)
    }

    @objc private func settingsChanged() { registerHotkey() }

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
