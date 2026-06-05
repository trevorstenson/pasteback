import AppKit

/// Owns the status-bar item and its menu. The "Re-copy last capture as…" submenu
/// is rebuilt each time the menu opens — also the mitigation for clipboard
/// managers that re-snapshot and drop representations.
final class MenuBarController: NSObject, NSMenuDelegate {

    var onCapture: (() -> Void)?
    var onRecopy: ((Representation) -> Void)?
    var onOpenSettings: (() -> Void)?
    var onOpenPermissions: (() -> Void)?
    var availableRepresentations: (() -> [Representation])?

    private var statusItem: NSStatusItem!

    func install() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "text.viewfinder",
                                   accessibilityDescription: "Paste-Back")
            button.image?.isTemplate = true
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        add(menu, "Capture Region", #selector(capture))

        let reps = availableRepresentations?() ?? []
        let recopy = NSMenuItem(title: "Re-copy Last Capture As…", action: nil, keyEquivalent: "")
        if reps.isEmpty {
            recopy.isEnabled = false
        } else {
            let submenu = NSMenu()
            for rep in reps {
                let item = NSMenuItem(title: rep.title, action: #selector(recopyItem(_:)), keyEquivalent: "")
                item.target = self; item.representedObject = rep
                submenu.addItem(item)
            }
            recopy.submenu = submenu
        }
        menu.addItem(recopy)

        menu.addItem(.separator())
        add(menu, "Settings…", #selector(openSettings), ",")
        add(menu, "Permissions…", #selector(openPermissions))
        menu.addItem(.separator())
        add(menu, "Quit Paste-Back", #selector(quit), "q")
    }

    @discardableResult
    private func add(_ menu: NSMenu, _ title: String, _ action: Selector, _ key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self; menu.addItem(item); return item
    }

    @objc private func capture() { onCapture?() }
    @objc private func recopyItem(_ sender: NSMenuItem) {
        if let rep = sender.representedObject as? Representation { onRecopy?(rep) }
    }
    @objc private func openSettings() { onOpenSettings?() }
    @objc private func openPermissions() { onOpenPermissions?() }
    @objc private func quit() { NSApplication.shared.terminate(nil) }
}
