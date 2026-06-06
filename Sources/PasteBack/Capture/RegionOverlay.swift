import AppKit

/// Native region selector: covers every screen with a dimmed overlay, lets the
/// user drag a rectangle, and reports the selection in Cocoa global coordinates
/// (bottom-left origin), or nil if cancelled. Required for AX harvest, which
/// needs the selected rect.
final class RegionOverlayController {

    private var windows: [OverlayWindow] = []
    private var completion: ((CGRect?) -> Void)?

    func begin(
        selectionStyle: SettingsStore.RegionSelectionStyle,
        completion: @escaping (CGRect?) -> Void
    ) {
        self.completion = completion
        for screen in NSScreen.screens {
            let window = OverlayWindow(screen: screen, selectionStyle: selectionStyle)
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

    init(screen: NSScreen, selectionStyle: SettingsStore.RegionSelectionStyle) {
        super.init(contentRect: screen.frame, styleMask: [.borderless],
                   backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)
        level = .screenSaver
        backgroundColor = NSColor.black.withAlphaComponent(0.18)
        isOpaque = false
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        acceptsMouseMovedEvents = true

        let view = SelectionView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.selectionStyle = selectionStyle
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
    var selectionStyle: SettingsStore.RegionSelectionStyle = .drag

    private var startPoint: NSPoint?
    private var anchorPoint: NSPoint?
    private var currentRect: NSRect = .zero

    override var acceptsFirstResponder: Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    override func mouseDown(with event: NSEvent) {
        guard selectionStyle == .drag else {
            handleTwoClick(at: convert(event.locationInWindow, from: nil))
            return
        }
        startPoint = convert(event.locationInWindow, from: nil)
        currentRect = .zero
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard selectionStyle == .drag else { return }
        guard let start = startPoint else { return }
        let p = convert(event.locationInWindow, from: nil)
        currentRect = rect(from: start, to: p)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard selectionStyle == .drag else { return }
        defer { startPoint = nil }
        finishSelection()
    }

    override func mouseMoved(with event: NSEvent) {
        guard selectionStyle == .twoClick, let anchorPoint else { return }
        let p = convert(event.locationInWindow, from: nil)
        currentRect = rect(from: anchorPoint, to: p)
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: onCancel?()             // Esc
        case 51: resetTwoClickAnchor()   // Delete / Backspace
        default: break
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        if let anchorPoint {
            NSColor.controlAccentColor.setFill()
            NSBezierPath(ovalIn: NSRect(x: anchorPoint.x - 3, y: anchorPoint.y - 3,
                                        width: 6, height: 6)).fill()
        }
        if currentRect != .zero {
            NSColor.white.withAlphaComponent(0.08).setFill()
            currentRect.fill()
            NSColor.controlAccentColor.setStroke()
            let path = NSBezierPath(rect: currentRect)
            path.lineWidth = 1.5
            path.stroke()
        }
    }

    private func handleTwoClick(at point: NSPoint) {
        guard let anchorPoint else {
            self.anchorPoint = point
            currentRect = .zero
            needsDisplay = true
            return
        }
        currentRect = rect(from: anchorPoint, to: point)
        finishSelection()
    }

    private func resetTwoClickAnchor() {
        guard selectionStyle == .twoClick else { return }
        anchorPoint = nil
        currentRect = .zero
        needsDisplay = true
    }

    private func finishSelection() {
        guard currentRect.width > 3, currentRect.height > 3 else {
            if selectionStyle == .twoClick { resetTwoClickAnchor() } else { onCancel?() }
            return
        }
        let global = NSRect(x: currentRect.origin.x + screenOrigin.x,
                            y: currentRect.origin.y + screenOrigin.y,
                            width: currentRect.width, height: currentRect.height)
        onSelect?(global)
    }

    private func rect(from start: NSPoint, to end: NSPoint) -> NSRect {
        NSRect(x: min(start.x, end.x), y: min(start.y, end.y),
               width: abs(end.x - start.x), height: abs(end.y - start.y))
    }
}
