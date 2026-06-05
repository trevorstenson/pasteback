import AppKit

/// Turns a capture into ranked HUD actions. Intent is inferred from the dominant
/// entity + selection size: a small selection "about" one link/path promotes the
/// side-effecting action (Open Link / Reveal) to the front; a block of content
/// keeps copy representations first. Copy actions delegate to `copy`.
struct ActionResolver {

    private let builder = RepresentationBuilder()

    func resolve(_ capture: CapturedScreenshot, copy: @escaping (Representation) -> Void) -> [CaptureAction] {
        let intent = intentActions(for: capture)
        let copies = copyActions(for: capture, copy: copy)

        // A short selection is "about" a single entity → lead with the intent action.
        let isFocused = capture.canonicalText.count <= 80
        return (isFocused && !intent.isEmpty) ? intent + copies : copies + intent
    }

    // MARK: - Side-effecting (intent) actions

    private func intentActions(for capture: CapturedScreenshot) -> [CaptureAction] {
        var actions: [CaptureAction] = []

        if let value = firstEntity(.url, capture), let url = URL(string: value) {
            actions.append(CaptureAction(
                id: "open-url", title: "Open Link", symbol: "arrow.up.forward.app",
                isStateful: false) { NSWorkspace.shared.open(url) })
        }
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

    // MARK: - Copy / representation actions

    private func copyActions(for capture: CapturedScreenshot, copy: @escaping (Representation) -> Void) -> [CaptureAction] {
        var reps = builder.availableRepresentations(for: capture)
        // If code was detected, lead the copy actions with the code block.
        if let idx = reps.firstIndex(of: .codeBlock) {
            reps.remove(at: idx); reps.insert(.codeBlock, at: 0)
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
