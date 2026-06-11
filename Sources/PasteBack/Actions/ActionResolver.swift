import AppKit

/// Turns a capture into ranked HUD actions. Intent is inferred from the dominant
/// entity + selection size: a small selection "about" one link/path promotes the
/// side-effecting action (Open Link / Reveal) to the front; a block of content
/// keeps copy representations first. Copy actions delegate to `copy`.
struct ActionResolver {

    private let builder = RepresentationBuilder()
    private let calendarBuilder = CalendarEventBuilder()
    private let mapsBuilder = MapsLinkBuilder()
    private let contactExtractor = ContactExtractor()

    func resolve(_ capture: CapturedScreenshot, copy: @escaping (Representation) -> Void) -> [CaptureAction] {
        let intent = intentActions(for: capture)
        let copies = copyActions(for: capture, copy: copy)

        // Lead with intent when the selection is "about" one entity (short) OR a
        // strong composite (QR / contact) is present — those are clearly the goal
        // even in a longer selection.
        let isFocused = capture.canonicalText.count <= 80
        let leadsWithStrong = intent.contains {
            $0.id == "qr-open" || $0.id == "qr-copy" || $0.id == "save-contact"
        }
        return ((isFocused || leadsWithStrong) && !intent.isEmpty) ? intent + copies : copies + intent
    }

    // MARK: - Side-effecting (intent) actions  (priority order)

    private func intentActions(for capture: CapturedScreenshot) -> [CaptureAction] {
        var actions: [CaptureAction] = []

        // QR / barcode: open if it's a link, else copy the decoded payload.
        if let payload = barcodeValue(capture) {
            if let url = httpURL(payload) {
                actions.append(CaptureAction(
                    id: "qr-open", title: "Open QR Link", symbol: "qrcode",
                    isStateful: false) { NSWorkspace.shared.open(url) })
            } else {
                actions.append(CaptureAction(
                    id: "qr-copy", title: "Copy QR", symbol: "qrcode",
                    isStateful: false) {
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.setString(payload, forType: .string)
                    })
            }
        }

        // Contact (signature / business card) → vCard.
        if let contact = contactExtractor.extract(from: capture) {
            actions.append(CaptureAction(
                id: "save-contact", title: "Save Contact", symbol: "person.crop.circle.badge.plus",
                isStateful: false) {
                    if let url = contactExtractor.vCardFileURL(for: contact) {
                        NSWorkspace.shared.open(url)
                    }
                })
        }

        // Date → calendar event.
        if firstEntity(.date, capture) != nil {
            actions.append(CaptureAction(
                id: "add-calendar", title: "Add to Calendar", symbol: "calendar.badge.plus",
                isStateful: false) {
                    if let url = calendarBuilder.icsFileURL(for: capture) {
                        NSWorkspace.shared.open(url)
                    }
                })
        }

        // Address → Maps.
        if let address = firstEntity(.address, capture), let url = mapsBuilder.url(for: address) {
            actions.append(CaptureAction(
                id: "open-maps", title: "Open in Maps", symbol: "map",
                isStateful: false) { NSWorkspace.shared.open(url) })
        }

        // URL → open.
        if let value = firstEntity(.url, capture), let url = URL(string: value) {
            actions.append(CaptureAction(
                id: "open-url", title: "Open Link", symbol: "arrow.up.forward.app",
                isStateful: false) { NSWorkspace.shared.open(url) })
        }
        // File path → reveal.
        if let path = firstEntity(.filePath, capture) {
            let fileURL = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            actions.append(CaptureAction(
                id: "reveal", title: "Reveal in Finder", symbol: "folder",
                isStateful: false) {
                    NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                })
        }
        return actions
    }

    private func barcodeValue(_ capture: CapturedScreenshot) -> String? {
        capture.entities.first { if case .barcode = $0.type { return true }; return false }?.value
    }

    private func httpURL(_ string: String) -> URL? {
        guard let url = URL(string: string),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https"
        else { return nil }
        return url
    }

    // MARK: - Copy / representation actions

    private func copyActions(for capture: CapturedScreenshot, copy: @escaping (Representation) -> Void) -> [CaptureAction] {
        var reps = builder.availableRepresentations(for: capture)
        // If code was detected, lead the copy actions with the code block.
        if let idx = reps.firstIndex(of: .codeBlock) {
            reps.remove(at: idx); reps.insert(.codeBlock, at: 0)
        }
        // The universal revert: Image is always offered and always LAST in the
        // copy group, regardless of ranking — a predictable position builds
        // muscle memory ("the last chip is always the safe one").
        if let idx = reps.firstIndex(of: .image) {
            reps.remove(at: idx); reps.append(.image)
        }
        return reps.map { rep in
            CaptureAction(id: "rep-\(rep.storageKey)", title: rep.title,
                          symbol: rep.symbolName, isStateful: true) { copy(rep) }
        }
    }

    private func firstEntity(_ type: EntityType, _ capture: CapturedScreenshot) -> String? {
        capture.entities.first { $0.type == type }?.value
    }
}
