import AppKit

/// Native region selector: covers every screen with a dimmed overlay, lets the
/// user drag a rectangle, and reports the selection in Cocoa global coordinates
/// (bottom-left origin), or nil if cancelled. Required for AX harvest, which
/// needs the selected rect.
final class RegionOverlayController {

    private var windows: [OverlayWindow] = []
    private var completion: ((CGRect?) -> Void)?

    func begin(completion: @escaping (CGRect?) -> Void) {
        self.completion = completion
        for screen in NSScreen.screens {
            let window = OverlayWindow(screen: screen)
            window.onSelect = { [weak self] rect in self?.finish(rect) }
            window.onCancel = { [weak self] in self?.finish(nil) }
            windows.append(window)
            window.orderFrontRegardless()
        }
        NSApp.activate(ignoringOtherApps: true)
        windows.first?.makeKey()
    }

    private func finish(_ rect: CGRect?) {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        let completion = self.completion
        self.completion = nil
        completion?(rect)
    }
}

private final class OverlayWindow: NSWindow {
    var onSelect: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: [.borderless],
                   backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)
        level = .screenSaver
        backgroundColor = NSColor.black.withAlphaComponent(0.18)
        isOpaque = false
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let view = SelectionView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.screenOrigin = screen.frame.origin
        view.onSelect = { [weak self] rect in self?.onSelect?(rect) }
        view.onCancel = { [weak self] in self?.onCancel?() }
        contentView = view
    }

    override var canBecomeKey: Bool { true }
}

private final class SelectionView: NSView {
    var onSelect: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?
    var screenOrigin: NSPoint = .zero

    private var startPoint: NSPoint?
    private var currentRect: NSRect = .zero

    override var acceptsFirstResponder: Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentRect = .zero
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = startPoint else { return }
        let p = convert(event.locationInWindow, from: nil)
        currentRect = NSRect(x: min(start.x, p.x), y: min(start.y, p.y),
                             width: abs(p.x - start.x), height: abs(p.y - start.y))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { startPoint = nil }
        guard currentRect.width > 3, currentRect.height > 3 else { onCancel?(); return }
        let global = NSRect(x: currentRect.origin.x + screenOrigin.x,
                            y: currentRect.origin.y + screenOrigin.y,
                            width: currentRect.width, height: currentRect.height)
        onSelect?(global)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?() }   // Esc
    }

    override func draw(_ dirtyRect: NSRect) {
        guard currentRect != .zero else { return }
        NSColor.white.withAlphaComponent(0.08).setFill()
        currentRect.fill()
        NSColor.controlAccentColor.setStroke()
        let path = NSBezierPath(rect: currentRect)
        path.lineWidth = 1.5
        path.stroke()
    }
}
