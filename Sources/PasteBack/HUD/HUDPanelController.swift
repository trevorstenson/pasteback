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
        viewModel.onDismiss = { [weak self] in self?.dismiss() }
    }

    func show(actions: [CaptureAction], selectedID: String?) {
        viewModel.update(actions: actions, selectedID: selectedID)
        let panel = panel ?? makePanel()
        self.panel = panel

        // Attach a FRESH hosting view each time so its intrinsic size reflects the
        // current chip set synchronously — reusing one lags a frame and clips the
        // right edge when a capture is wider than the previous one.
        let hosting = NSHostingView(rootView: ChipStripView(viewModel: viewModel))
        hosting.sizingOptions = [.intrinsicContentSize]
        panel.contentView = hosting

        positionPanel(panel)
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
        // Drag the strip's background (anywhere but a chip) to reposition it.
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        // contentView is attached per-show() with a fresh hosting view.

        // Keep the HUD alive while the user is dragging/positioning it (each new
        // capture still re-anchors near the cursor).
        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main
        ) { [weak self] _ in self?.restartDismissTimer() }
        return panel
    }

    private func positionPanel(_ panel: NSPanel) {
        if let hosting = panel.contentView {
            hosting.layoutSubtreeIfNeeded()
            panel.setContentSize(hosting.fittingSize)
        }
        // Bottom-center of the screen under the cursor (the user can drag it).
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = panel.frame.size
        var origin = NSPoint(x: visible.midX - size.width / 2,
                             y: visible.minY + 96)
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        panel.setFrameOrigin(origin)
    }

    private func restartDismissTimer() {
        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: autoDismissInterval, repeats: false) {
            [weak self] _ in self?.dismiss()
        }
    }
}
