import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings = SettingsStore.shared
    private let defaultChoices: [Representation] = [.image, .plainText, .markdown]

    var body: some View {
        Form {
            Section("Capture") {
                // Pick a shortcut from a menu — no need to physically press the
                // chord (helpful for one-handed use).
                Picker("Shortcut", selection: $settings.hotkey) {
                    ForEach(HotkeyManager.Hotkey.presets, id: \.hotkey) { preset in
                        Text(preset.name).tag(preset.hotkey)
                    }
                    if !HotkeyManager.Hotkey.presets.contains(where: { $0.hotkey == settings.hotkey }) {
                        Text("Custom (\(HotkeyFormatter.string(for: settings.hotkey)))")
                            .tag(settings.hotkey)
                    }
                }
                LabeledContent("Or record a custom shortcut") {
                    HotkeyRecorder(hotkey: $settings.hotkey).frame(width: 140, height: 24)
                }
                Picker("Capture mode", selection: $settings.captureMode) {
                    Text("In-app overlay (enables link/text recovery)").tag(SettingsStore.CaptureMode.native)
                    Text("System screenshot tool (OCR only)").tag(SettingsStore.CaptureMode.shellOut)
                }
                Picker("Region selection", selection: $settings.regionSelectionStyle) {
                    Text("Drag rectangle").tag(SettingsStore.RegionSelectionStyle.drag)
                    Text("Two-click rectangle").tag(SettingsStore.RegionSelectionStyle.twoClick)
                }
            }
            Section("Paste") {
                Picker("Default representation", selection: $settings.defaultRepresentation) {
                    ForEach(defaultChoices) { Text($0.title).tag($0) }
                }
            }
            Section("HUD") {
                VStack(alignment: .leading) {
                    Text("Auto-dismiss after \(Int(settings.autoDismissSeconds))s")
                    Slider(value: $settings.autoDismissSeconds, in: 3...30, step: 1)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 380)
    }
}
