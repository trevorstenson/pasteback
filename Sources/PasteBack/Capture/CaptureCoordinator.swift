import AppKit

/// Orchestrates the capture pipeline: region capture → OCR (+ AX harvest in M1)
/// → entity detection → pasteboard write. Holds the most recent capture so the
/// HUD and the menu-bar "Re-copy last capture as…" action can re-target the clipboard.
final class CaptureCoordinator {

    private let capture = CaptureService()
    private let ocr = OCRService()
    private let axHarvester = AXHarvester()
    private let entityDetector = EntityDetector()
    private let writer = PasteboardWriter()
    private let settings = SettingsStore.shared

    private(set) var lastCapture: CapturedScreenshot?

    /// Fired on the main thread after a successful capture, for the HUD.
    var onCaptured: ((CapturedScreenshot) -> Void)?

    func runCapture(primary: Representation = .image) {
        capture.captureRegion(mode: settings.captureMode) { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(CaptureService.CaptureError.cancelled):
                NSLog("Paste-Back: capture cancelled")
            case .failure(let error):
                NSLog("Paste-Back: capture failed: %@", String(describing: error))
            case .success(let captureResult):
                self.process(captureResult, primary: primary)
            }
        }
    }

    private func process(_ result: CaptureResult, primary: Representation) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            // Floor: OCR always runs.
            let ocrResult = (try? self.ocr.recognize(in: result.image))
                ?? OCRService.OCRResult(text: "", lines: [])

            // Enrichment: AX harvest (M1 fills this in; empty for now).
            let ax = self.harvestAX(result)

            let canonicalText = ax.text.isEmpty ? ocrResult.text : ax.text
            let entities = self.entityDetector.detect(in: canonicalText, seed: ax.entities)

            // Provenance: prefer the app actually under the selected pixels
            // (discovered by AX hit-test), not the frontmost app. Enrich with the
            // page URL recovered from AX.
            var source = result.source
            if let owner = ax.ownerPID, let app = NSRunningApplication(processIdentifier: owner) {
                source = CaptureSource(appName: app.localizedName,
                                       bundleIdentifier: app.bundleIdentifier,
                                       pid: owner, url: ax.pageURL ?? source.url)
            } else if let pageURL = ax.pageURL {
                source = CaptureSource(appName: source.appName, bundleIdentifier: source.bundleIdentifier,
                                       pid: source.pid, url: pageURL)
            }

            let screenshot = CapturedScreenshot(
                image: result.image,
                captureRect: result.rect,
                source: source,
                ocrText: ocrResult.text,
                ocrLines: ocrResult.lines,
                axText: ax.text,
                axElements: ax.elements,
                entities: entities
            )
            Log.write("""
            capture: ownerApp=\(source.appName ?? "?") frontApp=\(result.source.appName ?? "?") \
            pid=\(source.pid.map(String.init) ?? "?") \
            rect=\(result.rect.map { "\(Int($0.width))x\(Int($0.height))" } ?? "nil") \
            image=\(result.image.width)x\(result.image.height) \
            axTrusted=\(PermissionService.hasAccessibility()) \
            ocrLines=\(ocrResult.lines.count) axElems=\(ax.elements.count) \
            axText=\(ax.text.count)chars ocrText=\(ocrResult.text.count)chars entities=\(entities.count) \
            axLinks=\(ax.entities.count) ownerApps=\(ax.ownerPIDs.count) \
            pageURL=\(ax.pageURL?.absoluteString ?? "nil") \
            firstURL=\(entities.first { $0.type == .url }?.value ?? "nil")
            """)

            DispatchQueue.main.async {
                self.lastCapture = screenshot
                self.writer.write(screenshot, primary: primary)
                self.onCaptured?(screenshot)
            }
        }
    }

    /// AX harvest: ground-truth enrichment when we own the rect, know the app,
    /// and have Accessibility permission. Empty otherwise → OCR floor stands.
    private struct AXResult {
        let text: String; let elements: [AXElement]
        let entities: [DetectedEntity]; let pageURL: URL?
        let ownerPID: pid_t?; let ownerPIDs: [pid_t]
    }
    private func harvestAX(_ result: CaptureResult) -> AXResult {
        guard let rect = result.rect, PermissionService.hasAccessibility() else {
            return AXResult(text: "", elements: [], entities: [], pageURL: nil, ownerPID: nil, ownerPIDs: [])
        }
        // The harvester discovers the app(s) under the selected pixels itself,
        // weighted by coverage; the frontmost app is only a fallback.
        let h = axHarvester.harvest(rect: rect, fallbackPID: result.source.pid)
        return AXResult(text: h.text, elements: h.elements, entities: h.entities,
                        pageURL: h.pageURL, ownerPID: h.ownerPID, ownerPIDs: h.ownerPIDs)
    }

    func recopy(as representation: Representation) {
        guard let lastCapture else { return }
        writer.write(lastCapture, primary: representation)
    }
}
