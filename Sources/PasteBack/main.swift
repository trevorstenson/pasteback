import AppKit

// Headless verification paths.
if CommandLine.arguments.contains("--selftest") {
    SelfTest.run()
}
if CommandLine.arguments.contains("--axprobe") {
    AXProbe.run()
}

// SPM executables use a top-level entry point (no @main). Bootstrap NSApplication
// as an accessory (menu-bar agent): no Dock icon.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
