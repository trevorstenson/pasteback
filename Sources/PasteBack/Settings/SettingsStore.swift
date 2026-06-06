import Foundation
import Carbon.HIToolbox

/// User-configurable settings, persisted in UserDefaults.
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    enum CaptureMode: String {
        case native     // in-app overlay (rect-aware, enables AX; needs Screen Recording)
        case shellOut   // /usr/sbin/screencapture (no app permission, OCR-only)
    }

    enum RegionSelectionStyle: String {
        case drag
        case twoClick
    }

    private let defaults = UserDefaults.standard
    private enum Key {
        static let defaultRep = "defaultRepresentation"
        static let autoDismiss = "autoDismissSeconds"
        static let captureMode = "captureMode"
        static let regionSelectionStyle = "regionSelectionStyle"
        static let hotkeyKeyCode = "hotkeyKeyCode"
        static let hotkeyModifiers = "hotkeyModifiers"
        static let settingsHotkeyKeyCode = "settingsHotkeyKeyCode"
        static let settingsHotkeyModifiers = "settingsHotkeyModifiers"
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
    @Published var regionSelectionStyle: RegionSelectionStyle {
        didSet { defaults.set(regionSelectionStyle.rawValue, forKey: Key.regionSelectionStyle); notify() }
    }
    @Published var hotkey: HotkeyManager.Hotkey {
        didSet {
            defaults.set(Int(hotkey.keyCode), forKey: Key.hotkeyKeyCode)
            defaults.set(Int(hotkey.modifiers), forKey: Key.hotkeyModifiers)
            notify()
        }
    }
    @Published var settingsHotkey: HotkeyManager.Hotkey {
        didSet {
            defaults.set(Int(settingsHotkey.keyCode), forKey: Key.settingsHotkeyKeyCode)
            defaults.set(Int(settingsHotkey.modifiers), forKey: Key.settingsHotkeyModifiers)
            notify()
        }
    }

    private init() {
        defaults.register(defaults: [
            Key.autoDismiss: 10.0,
            Key.captureMode: CaptureMode.native.rawValue,   // native is default (enables AX)
            Key.regionSelectionStyle: RegionSelectionStyle.drag.rawValue,
            Key.defaultRep: Representation.image.storageKey,
            Key.hotkeyKeyCode: Int(kVK_ANSI_C),
            Key.hotkeyModifiers: Int(controlKey | optionKey | cmdKey),
            Key.settingsHotkeyKeyCode: Int(kVK_ANSI_A),
            Key.settingsHotkeyModifiers: Int(controlKey | optionKey | cmdKey)
        ])
        defaultRepresentation = Representation(storageKey: defaults.string(forKey: Key.defaultRep) ?? "") ?? .image
        autoDismissSeconds = defaults.double(forKey: Key.autoDismiss)
        captureMode = CaptureMode(rawValue: defaults.string(forKey: Key.captureMode) ?? "") ?? .native
        regionSelectionStyle = RegionSelectionStyle(
            rawValue: defaults.string(forKey: Key.regionSelectionStyle) ?? "") ?? .drag
        hotkey = HotkeyManager.Hotkey(
            keyCode: UInt32(defaults.integer(forKey: Key.hotkeyKeyCode)),
            modifiers: UInt32(defaults.integer(forKey: Key.hotkeyModifiers)))
        settingsHotkey = HotkeyManager.Hotkey(
            keyCode: UInt32(defaults.integer(forKey: Key.settingsHotkeyKeyCode)),
            modifiers: UInt32(defaults.integer(forKey: Key.settingsHotkeyModifiers)))
    }

    private func notify() { NotificationCenter.default.post(name: Self.didChange, object: self) }
}
