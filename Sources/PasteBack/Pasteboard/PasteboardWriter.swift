import AppKit

/// Writes a capture to `NSPasteboard.general` as a single multi-type item, with
/// the chosen primary representation declared FIRST (many apps pick the first
/// compatible type, not the "best" one). Chip selection recomposes with a new primary.
final class PasteboardWriter {

    private let builder = RepresentationBuilder()

    @discardableResult
    func write(_ capture: CapturedScreenshot, primary: Representation) -> Bool {
        let payloads = builder.payloads(for: primary, from: capture)
        guard !payloads.isEmpty else { return false }
        let item = NSPasteboardItem()
        for payload in payloads { item.setData(payload.data, forType: payload.type) }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.writeObjects([item])
    }
}
