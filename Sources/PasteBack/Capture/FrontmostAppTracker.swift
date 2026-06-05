import AppKit

/// Tracks the most recently active app that ISN'T Paste-Back, so a capture
/// harvests the app behind our overlay/windows — not our own (empty) UI. Fixes
/// the case where a capture fired while the Settings/Permissions window was focused.
final class FrontmostAppTracker {
    static let shared = FrontmostAppTracker()

    private let selfBundleID = Bundle.main.bundleIdentifier ?? "com.pasteback.app"
    private var lastNonSelf: NSRunningApplication?

    func start() {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                       object: nil, queue: .main) { [weak self] note in
            guard let self,
                  let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            else { return }
            if app.bundleIdentifier != self.selfBundleID { self.lastNonSelf = app }
        }
        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier != selfBundleID {
            lastNonSelf = front
        }
    }

    /// The app to harvest: the current frontmost if it isn't us, else the last
    /// non-self app we saw activate.
    func targetApp() -> NSRunningApplication? {
        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier != selfBundleID {
            return front
        }
        return lastNonSelf
    }
}
