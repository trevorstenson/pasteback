import AppKit

/// Coordinate conversion between Cocoa global space (origin bottom-left of the
/// primary display) and CoreGraphics / Accessibility space (origin top-left).
/// One helper, reused by capture and by the AX harvester (M1).
enum ScreenGeometry {

    /// Height of the primary display, which defines both global origins.
    static var primaryHeight: CGFloat {
        NSScreen.screens.first?.frame.height ?? 0
    }

    /// Cocoa global rect (bottom-left origin) → CG/AX rect (top-left origin).
    static func cocoaToCG(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.origin.x,
               y: primaryHeight - rect.origin.y - rect.height,
               width: rect.width, height: rect.height)
    }
}
