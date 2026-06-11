import AppKit
import ApplicationServices

/// `PasteBack --axprobe` — empirically measures AX coverage. Waits a few seconds
/// so you can focus the app to inspect, then harvests that app's whole tree and
/// prints the roles / URLs / text it recovered. Use it to see how good coverage
/// is on the apps you actually use (Safari, Chrome, Terminal, Slack, Figma…).
enum AXProbe {
    static func run(arguments: [String] = CommandLine.arguments) -> Never {
        print("AX trusted: \(AXIsProcessTrusted())")
        if !AXIsProcessTrusted() {
            print("→ Not trusted. Grant this binary Accessibility in System Settings, or run the signed .app.")
        }

        let targets = bundleTargets(from: arguments)
        if !targets.isEmpty {
            runCoverageTable(targets: targets)
        }

        let delay = 4
        print("Focus the app to probe — harvesting in \(delay)s…")
        Thread.sleep(forTimeInterval: TimeInterval(delay))

        guard let app = NSWorkspace.shared.frontmostApplication else {
            print("No frontmost app."); exit(1)
        }
        print("Frontmost: \(app.localizedName ?? "?") [\(app.bundleIdentifier ?? "?")] pid=\(app.processIdentifier)")

        // Infinite rect → no frame pruning; harvest the whole (bounded) tree.
        let result = AXHarvester().harvest(rect: .infinite, fallbackPID: app.processIdentifier)

        print("\nElements with content: \(result.elements.count)")
        print("Ground-truth URLs: \(result.entities.count)")
        print("Retry needed: \(result.retryCount > 0 ? "yes" : "no")")
        let roles = Dictionary(grouping: result.elements, by: { $0.role }).mapValues(\.count)
        print("Roles: \(roles.sorted { $0.value > $1.value }.prefix(12).map { "\($0.key)=\($0.value)" }.joined(separator: ", "))")

        print("\nSample URLs:")
        for e in result.elements.compactMap(\.url).prefix(8) { print("  • \(e.absoluteString)") }
        print("\nText preview:")
        print(result.text.prefix(600))
        exit(0)
    }

    private static func runCoverageTable(targets: [String]) -> Never {
        let running = NSWorkspace.shared.runningApplications
        print("Target\tApp\tBundle\tElems\tLinks\tRetry")
        for target in targets {
            let matches = running.filter { app in
                let bundle = app.bundleIdentifier?.lowercased() ?? ""
                let name = app.localizedName?.lowercased() ?? ""
                let needle = target.lowercased()
                return bundle.contains(needle) || name.contains(needle)
            }
            if matches.isEmpty {
                print("\(target)\t-\t-\t0\t0\tno-running-app")
                continue
            }
            for app in matches {
                let result = AXHarvester().harvest(rect: .infinite, fallbackPID: app.processIdentifier)
                print([
                    target,
                    app.localizedName ?? "?",
                    app.bundleIdentifier ?? "?",
                    "\(result.elements.count)",
                    "\(result.entities.count)",
                    result.retryCount > 0 ? "yes" : "no"
                ].joined(separator: "\t"))
            }
        }
        exit(0)
    }

    private static func bundleTargets(from arguments: [String]) -> [String] {
        guard let index = arguments.firstIndex(of: "--axprobe") else { return [] }
        return arguments.dropFirst(index + 1).filter { !$0.hasPrefix("--") }
    }
}
