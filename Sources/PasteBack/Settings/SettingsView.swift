import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings = SettingsStore.shared
    private let defaultChoices: [Representation] = [.image, .plainText, .markdown]

    var body: some View {
        Form {
            Section("Capture") {
                // Pick a shortcut from a menu — no need to physically press the
                // chord (helpful for one-handed use).
                Picker("Capture shortcut", selection: $settings.hotkey) {
                    ForEach(HotkeyManager.Hotkey.capturePresets, id: \.hotkey) { preset in
                        Text(preset.name).tag(preset.hotkey)
                    }
                    if !HotkeyManager.Hotkey.capturePresets.contains(where: { $0.hotkey == settings.hotkey }) {
                        Text("Custom (\(HotkeyFormatter.string(for: settings.hotkey)))")
                            .tag(settings.hotkey)
                    }
                }
                LabeledContent("Record capture shortcut") {
                    HotkeyRecorder(hotkey: $settings.hotkey).frame(width: 140, height: 24)
                }
                Picker("Settings shortcut", selection: $settings.settingsHotkey) {
                    ForEach(HotkeyManager.Hotkey.settingsPresets, id: \.hotkey) { preset in
                        Text(preset.name).tag(preset.hotkey)
                    }
                    if !HotkeyManager.Hotkey.settingsPresets.contains(where: { $0.hotkey == settings.settingsHotkey }) {
                        Text("Custom (\(HotkeyFormatter.string(for: settings.settingsHotkey)))")
                            .tag(settings.settingsHotkey)
                    }
                }
                LabeledContent("Record settings shortcut") {
                    HotkeyRecorder(hotkey: $settings.settingsHotkey).frame(width: 140, height: 24)
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
        .frame(width: 500, height: 460)
    }
}
