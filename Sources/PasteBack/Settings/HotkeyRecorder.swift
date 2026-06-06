import AppKit
import SwiftUI
import Carbon.HIToolbox

/// Maps a Carbon hotkey to a display string like "⌃⌥⌘7".
enum HotkeyFormatter {
    static func string(for hotkey: HotkeyManager.Hotkey) -> String {
        var s = ""
        let m = Int(hotkey.modifiers)
        if m & controlKey != 0 { s += "⌃" }
        if m & optionKey != 0 { s += "⌥" }
        if m & shiftKey != 0 { s += "⇧" }
        if m & cmdKey != 0 { s += "⌘" }
        return s + keyName(Int(hotkey.keyCode))
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var m = 0
        if flags.contains(.command) { m |= cmdKey }
        if flags.contains(.shift) { m |= shiftKey }
        if flags.contains(.option) { m |= optionKey }
        if flags.contains(.control) { m |= controlKey }
        return UInt32(m)
    }

    private static func keyName(_ code: Int) -> String {
        let map: [Int: String] = [
            kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3", kVK_ANSI_4: "4",
            kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9",
            kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D", kVK_ANSI_E: "E",
            kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H", kVK_ANSI_I: "I", kVK_ANSI_J: "J",
            kVK_ANSI_K: "K", kVK_ANSI_L: "L", kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O",
            kVK_ANSI_P: "P", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
            kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X", kVK_ANSI_Y: "Y",
            kVK_ANSI_Z: "Z", kVK_Space: "Space", kVK_Return: "↩"
        ]
        return map[code] ?? "Key\(code)"
    }
}

/// SwiftUI wrapper around an NSButton that records the next key combo pressed.
struct HotkeyRecorder: NSViewRepresentable {
    @Binding var hotkey: HotkeyManager.Hotkey

    func makeNSView(context: Context) -> RecorderButton {
        let view = RecorderButton()
        view.onRecord = { hotkey = $0 }
        return view
    }
    func updateNSView(_ nsView: RecorderButton, context: Context) {
        nsView.hotkey = hotkey
        nsView.refreshTitle()
    }

    final class RecorderButton: NSButton {
        var hotkey = HotkeyManager.Hotkey.defaultCapture
        var onRecord: ((HotkeyManager.Hotkey) -> Void)?
        private var recording = false

        override init(frame f: NSRect) {
            super.init(frame: f)
            bezelStyle = .rounded; setButtonType(.momentaryPushIn)
            target = self; action = #selector(startRecording)
            refreshTitle()
        }
        required init?(coder: NSCoder) { fatalError() }

        @objc private func startRecording() {
            recording = true; title = "Type shortcut…"
            window?.makeFirstResponder(self)
        }
        func refreshTitle() { if !recording { title = HotkeyFormatter.string(for: hotkey) } }
        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            guard recording else { super.keyDown(with: event); return }
            let mods = HotkeyFormatter.carbonModifiers(from: event.modifierFlags)
            guard mods != 0 else { return }   // require a modifier
            recording = false
            let hk = HotkeyManager.Hotkey(keyCode: UInt32(event.keyCode), modifiers: mods)
            hotkey = hk; onRecord?(hk); refreshTitle()
        }
    }
}
