import Foundation

/// Central place for app-specific AX behavior. Keep entries narrow and based on
/// observed behavior, so quirks stay explainable instead of becoming folklore.
struct AppQuirks {
    let skipAX: [String]
    let needsNudge: [String]
    let oversizedLeafProne: [String]

    static let current = AppQuirks(
        skipAX: [
            "warp"
        ],
        needsNudge: [
            "chrome", "chromium", "brave", "edge", "arc", "thebrowser",
            "electron", "slack", "discord", "notion", "figma"
        ],
        oversizedLeafProne: [
            "warp", "terminal", "iterm"
        ]
    )

    func shouldSkipAX(appName: String?, bundleIdentifier: String?) -> Bool {
        matches(skipAX, appName: appName, bundleIdentifier: bundleIdentifier)
    }

    func needsNudge(appName: String?, bundleIdentifier: String?) -> Bool {
        matches(needsNudge, appName: appName, bundleIdentifier: bundleIdentifier)
    }

    func isOversizedLeafProne(appName: String?, bundleIdentifier: String?) -> Bool {
        matches(oversizedLeafProne, appName: appName, bundleIdentifier: bundleIdentifier)
    }

    private func matches(_ needles: [String], appName: String?, bundleIdentifier: String?) -> Bool {
        let haystacks = [appName, bundleIdentifier]
            .compactMap { $0?.lowercased() }
        return needles.contains { needle in
            let n = needle.lowercased()
            return haystacks.contains { $0.contains(n) }
        }
    }
}
