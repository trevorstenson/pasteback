import AppKit
import CoreGraphics
import ApplicationServices

/// Permission helpers. Screen Recording is needed for native capture;
/// Accessibility is needed for AX ground-truth harvest (M1). Both degrade
/// gracefully: no Screen Recording → use shell-out; no Accessibility → OCR-only.
enum PermissionService {

    // MARK: Screen Recording

    static func hasScreenRecording() -> Bool { CGPreflightScreenCaptureAccess() }

    @discardableResult
    static func requestScreenRecording() -> Bool { CGRequestScreenCaptureAccess() }

    static func openScreenRecordingSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    }

    // MARK: Accessibility

    static func hasAccessibility() -> Bool { AXIsProcessTrusted() }

    /// Checks trust and, if `prompt`, shows the system Accessibility prompt.
    @discardableResult
    static func requestAccessibility(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    private static func open(_ urlString: String) {
        if let url = URL(string: urlString) { NSWorkspace.shared.open(url) }
    }
}
