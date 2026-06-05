import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings = SettingsStore.shared
    private let defaultChoices: [Representation] = [.image, .plainText, .markdown]

    var body: some View {
        Form {
            Section("Capture") {
                LabeledContent("Shortcut") {
                    HotkeyRecorder(hotkey: $settings.hotkey).frame(width: 140, height: 24)
                }
                Picker("Capture mode", selection: $settings.captureMode) {
                    Text("In-app overlay (enables link/text recovery)").tag(SettingsStore.CaptureMode.native)
                    Text("System screenshot tool (OCR only)").tag(SettingsStore.CaptureMode.shellOut)
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
        .frame(width: 440, height: 340)
    }
}
