import Foundation
import Carbon.HIToolbox

/// User-configurable settings, persisted in UserDefaults.
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    enum CaptureMode: String {
        case native     // in-app overlay (rect-aware, enables AX; needs Screen Recording)
        case shellOut   // /usr/sbin/screencapture (no app permission, OCR-only)
    }

    private let defaults = UserDefaults.standard
    private enum Key {
        static let defaultRep = "defaultRepresentation"
        static let autoDismiss = "autoDismissSeconds"
        static let captureMode = "captureMode"
        static let hotkeyKeyCode = "hotkeyKeyCode"
        static let hotkeyModifiers = "hotkeyModifiers"
    }

    static let didChange = Notification.Name("SettingsStore.didChange")

    @Published var defaultRepresentation: Representation {
        didSet { defaults.set(defaultRepresentation.storageKey, forKey: Key.defaultRep); notify() }
    }
    @Published var autoDismissSeconds: Double {
        didSet { defaults.set(autoDismissSeconds, forKey: Key.autoDismiss); notify() }
    }
    @Published var captureMode: CaptureMode {
        didSet { defaults.set(captureMode.rawValue, forKey: Key.captureMode); notify() }
    }
    @Published var hotkey: HotkeyManager.Hotkey {
        didSet {
            defaults.set(Int(hotkey.keyCode), forKey: Key.hotkeyKeyCode)
            defaults.set(Int(hotkey.modifiers), forKey: Key.hotkeyModifiers)
            notify()
        }
    }

    private init() {
        defaults.register(defaults: [
            Key.autoDismiss: 10.0,
            Key.captureMode: CaptureMode.native.rawValue,   // native is default (enables AX)
            Key.defaultRep: Representation.image.storageKey,
            Key.hotkeyKeyCode: Int(kVK_ANSI_7),
            Key.hotkeyModifiers: Int(controlKey | optionKey | cmdKey)
        ])
        defaultRepresentation = Representation(storageKey: defaults.string(forKey: Key.defaultRep) ?? "") ?? .image
        autoDismissSeconds = defaults.double(forKey: Key.autoDismiss)
        captureMode = CaptureMode(rawValue: defaults.string(forKey: Key.captureMode) ?? "") ?? .native
        hotkey = HotkeyManager.Hotkey(
            keyCode: UInt32(defaults.integer(forKey: Key.hotkeyKeyCode)),
            modifiers: UInt32(defaults.integer(forKey: Key.hotkeyModifiers)))
    }

    private func notify() { NotificationCenter.default.post(name: Self.didChange, object: self) }
}
