// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PasteBack",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        // No third-party deps. The global hotkey is registered directly via
        // Carbon (RegisterEventHotKey) — KeyboardShortcuts' #Preview macro needs
        // full Xcode, unavailable under Command Line Tools.
    ],
    targets: [
        .executableTarget(
            name: "PasteBack",
            path: "Sources/PasteBack"
        )
    ]
)
