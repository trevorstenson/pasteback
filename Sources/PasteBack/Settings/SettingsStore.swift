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
        static let recallHotkeyEnabled = "recallHotkeyEnabled"
        static let recallHotkeyKeyCode = "recallHotkeyKeyCode"
        static let recallHotkeyModifiers = "recallHotkeyModifiers"
        static let historyHotkeyEnabled = "historyHotkeyEnabled"
        static let historyHotkeyKeyCode = "historyHotkeyKeyCode"
        static let historyHotkeyModifiers = "historyHotkeyModifiers"
        static let keepHistory = "keepHistory"
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
    @Published var recallHotkeyEnabled: Bool {
        didSet { defaults.set(recallHotkeyEnabled, forKey: Key.recallHotkeyEnabled); notify() }
    }
    @Published var recallHotkey: HotkeyManager.Hotkey {
        didSet {
            defaults.set(Int(recallHotkey.keyCode), forKey: Key.recallHotkeyKeyCode)
            defaults.set(Int(recallHotkey.modifiers), forKey: Key.recallHotkeyModifiers)
            notify()
        }
    }
    @Published var historyHotkeyEnabled: Bool {
        didSet { defaults.set(historyHotkeyEnabled, forKey: Key.historyHotkeyEnabled); notify() }
    }
    @Published var historyHotkey: HotkeyManager.Hotkey {
        didSet {
            defaults.set(Int(historyHotkey.keyCode), forKey: Key.historyHotkeyKeyCode)
            defaults.set(Int(historyHotkey.modifiers), forKey: Key.historyHotkeyModifiers)
            notify()
        }
    }
    @Published var keepHistory: Bool {
        didSet { defaults.set(keepHistory, forKey: Key.keepHistory); notify() }
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
            Key.settingsHotkeyModifiers: Int(controlKey | optionKey | cmdKey),
            // Recall: ⌃⌥⌘V — left-hand reachable, mnemonic "view".
            Key.recallHotkeyEnabled: true,
            Key.recallHotkeyKeyCode: Int(kVK_ANSI_V),
            Key.recallHotkeyModifiers: Int(controlKey | optionKey | cmdKey),
            // History window: ⌃⌥⌘Y (the conventional "history" key).
            Key.historyHotkeyEnabled: true,
            Key.historyHotkeyKeyCode: Int(kVK_ANSI_Y),
            Key.historyHotkeyModifiers: Int(controlKey | optionKey | cmdKey),
            Key.keepHistory: true
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
        recallHotkeyEnabled = defaults.bool(forKey: Key.recallHotkeyEnabled)
        recallHotkey = HotkeyManager.Hotkey(
            keyCode: UInt32(defaults.integer(forKey: Key.recallHotkeyKeyCode)),
            modifiers: UInt32(defaults.integer(forKey: Key.recallHotkeyModifiers)))
        historyHotkeyEnabled = defaults.bool(forKey: Key.historyHotkeyEnabled)
        historyHotkey = HotkeyManager.Hotkey(
            keyCode: UInt32(defaults.integer(forKey: Key.historyHotkeyKeyCode)),
            modifiers: UInt32(defaults.integer(forKey: Key.historyHotkeyModifiers)))
        keepHistory = defaults.bool(forKey: Key.keepHistory)
    }

    private func notify() { NotificationCenter.default.post(name: Self.didChange, object: self) }
}
