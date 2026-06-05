import AppKit
import SwiftUI

/// Owns the floating, non-activating HUD panel that appears near the cursor after
/// a capture. Clicking a chip re-targets the clipboard without stealing focus.
/// All methods are called on the main thread.
final class HUDPanelController {

    private let viewModel = HUDViewModel()
    private var panel: NSPanel?
    private var dismissTimer: Timer?

    private var autoDismissInterval: TimeInterval { SettingsStore.shared.autoDismissSeconds }

    init() {
        viewModel.onTap = { [weak self] in self?.restartDismissTimer() }
    }

    func show(actions: [CaptureAction], selectedID: String?) {
        viewModel.update(actions: actions, selectedID: selectedID)
        let panel = panel ?? makePanel()
        self.panel = panel
        sizeAndPositionNearCursor(panel)
        panel.orderFrontRegardless()
        restartDismissTimer()
    }

    func dismiss() {
        dismissTimer?.invalidate(); dismissTimer = nil
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 48),
                            styleMask: [.nonactivatingPanel, .borderless],
                            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NSHostingView(rootView: ChipStripView(viewModel: viewModel))
        return panel
    }

    private func sizeAndPositionNearCursor(_ panel: NSPanel) {
        if let hosting = panel.contentView { panel.setContentSize(hosting.fittingSize) }
        let mouse = NSEvent.mouseLocation
        let size = panel.frame.size
        var origin = NSPoint(x: mouse.x + 12, y: mouse.y - size.height - 12)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main {
            let v = screen.visibleFrame
            origin.x = min(max(origin.x, v.minX), v.maxX - size.width)
            origin.y = min(max(origin.y, v.minY), v.maxY - size.height)
        }
        panel.setFrameOrigin(origin)
    }

    private func restartDismissTimer() {
        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: autoDismissInterval, repeats: false) {
            [weak self] _ in self?.dismiss()
        }
    }
}
