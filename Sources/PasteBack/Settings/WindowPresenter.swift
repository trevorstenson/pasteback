import AppKit
import SwiftUI

/// Hosts the Settings and Permissions windows. An accessory app must momentarily
/// activate itself so these windows can take focus.
final class WindowPresenter {
    private var settingsWindow: NSWindow?
    private var permissionsWindow: NSWindow?

    func showSettings() {
        if settingsWindow == nil {
            settingsWindow = makeWindow(title: "Paste-Back Settings", content: SettingsView())
            settingsWindow?.isReleasedWhenClosed = false
        }
        present(settingsWindow)
    }

    func showPermissions() {
        if permissionsWindow == nil {
            let window = makeWindow(title: "Paste-Back Permissions",
                                    content: PermissionsView(onDone: { [weak self] in
                                        self?.permissionsWindow?.close()
                                    }))
            window.isReleasedWhenClosed = false
            permissionsWindow = window
        }
        present(permissionsWindow)
    }

    private func makeWindow<Content: View>(title: String, content: Content) -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: content))
        window.title = title
        window.styleMask = [.titled, .closable]
        window.center()
        return window
    }

    private func present(_ window: NSWindow?) {
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
