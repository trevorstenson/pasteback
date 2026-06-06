import AppKit
import Carbon.HIToolbox

/// Registers a single global hotkey via Carbon's RegisterEventHotKey.
/// No Accessibility permission required (unlike NSEvent global monitors).
final class HotkeyManager {
    struct Hotkey: Equatable, Hashable {
        let keyCode: UInt32
        /// Carbon modifier masks (cmdKey, shiftKey, optionKey, controlKey).
        let modifiers: UInt32

        /// All three modifiers are on the left of the keyboard; pairing them with
        /// a left-hand key keeps the whole chord one-hand (left) reachable. Three
        /// modifiers also avoid the common ⌘⇧-number shortcuts other apps claim
        /// (RegisterEventHotKey reports success even on conflict, so be safe).
        static let leftHandModifiers = UInt32(controlKey | optionKey | cmdKey)

        /// Default: ⌃⌥⌘C ("C" for Capture — left-hand, one-hand friendly).
        static let `default` = Hotkey(
            keyCode: UInt32(kVK_ANSI_C),
            modifiers: leftHandModifiers
        )

        /// Left-hand-friendly presets, selectable in Settings without having to
        /// physically press the chord (handy for one-handed use).
        static let presets: [(name: String, hotkey: Hotkey)] = [
            ("⌃⌥⌘C  (Capture)", Hotkey(keyCode: UInt32(kVK_ANSI_C), modifiers: leftHandModifiers)),
            ("⌃⌥⌘S  (Snip)",    Hotkey(keyCode: UInt32(kVK_ANSI_S), modifiers: leftHandModifiers)),
            ("⌃⌥⌘D",            Hotkey(keyCode: UInt32(kVK_ANSI_D), modifiers: leftHandModifiers)),
            ("⌃⌥⌘Z",            Hotkey(keyCode: UInt32(kVK_ANSI_Z), modifiers: leftHandModifiers)),
            ("⌃⌥⌘1",            Hotkey(keyCode: UInt32(kVK_ANSI_1), modifiers: leftHandModifiers)),
        ]
    }

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var onPressed: (() -> Void)?

    private let signature: OSType = {
        let chars: [UInt8] = Array("PBhk".utf8)
        return chars.reduce(OSType(0)) { ($0 << 8) + OSType($1) }
    }()

    func register(_ hotkey: Hotkey = .default, onPressed: @escaping () -> Void) {
        unregister()
        self.onPressed = onPressed

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData -> OSStatus in
                guard let userData else { return noErr }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { manager.onPressed?() }
                return noErr
            },
            1, &eventType, selfPtr, &eventHandler
        )

        let hotKeyID = EventHotKeyID(signature: signature, id: 1)
        RegisterEventHotKey(
            hotkey.keyCode, hotkey.modifiers, hotKeyID,
            GetApplicationEventTarget(), 0, &hotKeyRef
        )
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef); self.hotKeyRef = nil }
        if let eventHandler { RemoveEventHandler(eventHandler); self.eventHandler = nil }
    }

    deinit { unregister() }
}
