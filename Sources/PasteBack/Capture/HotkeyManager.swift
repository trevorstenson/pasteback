import AppKit
import Carbon.HIToolbox

/// Registers a single global hotkey via Carbon's RegisterEventHotKey.
/// No Accessibility permission required (unlike NSEvent global monitors).
final class HotkeyManager {
    struct Hotkey {
        let keyCode: UInt32
        /// Carbon modifier masks (cmdKey, shiftKey, optionKey, controlKey).
        let modifiers: UInt32

        /// Default: ⌃⌥⌘7. A 3-modifier default avoids the common ⌘⇧-number
        /// shortcuts other apps tend to claim — and RegisterEventHotKey reports
        /// success even when the combo is already owned, so conflicts are silent.
        static let `default` = Hotkey(
            keyCode: UInt32(kVK_ANSI_7),
            modifiers: UInt32(controlKey | optionKey | cmdKey)
        )
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
