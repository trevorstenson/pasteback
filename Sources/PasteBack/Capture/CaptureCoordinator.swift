import AppKit

/// Orchestrates the capture pipeline: region capture → OCR (+ AX harvest in M1)
/// → entity detection → pasteboard write. Holds the most recent capture so the
/// HUD and the menu-bar "Re-copy last capture as…" action can re-target the clipboard.
final class CaptureCoordinator {

    private let capture = CaptureService()
    private let ocr = OCRService()
    private let axHarvester = AXHarvester()
    private let entityDetector = EntityDetector()
    private let technicalRecognizer = TechnicalContentRecognizer()
    private let barcodeService = BarcodeService()
    private let writer = PasteboardWriter()
    private let settings = SettingsStore.shared
    private let appQuirks = AppQuirks.current
    let historyStore = CaptureHistoryStore()

    private(set) var lastCapture: CapturedScreenshot?
    /// The representation we last wrote to the clipboard (capture or re-copy);
    /// lets a recalled HUD highlight the chip that matches the clipboard.
    private(set) var lastWrittenRepresentation: Representation?

    /// Fired on the main thread after a successful capture, for the HUD.
    var onCaptured: ((CapturedScreenshot) -> Void)?

    func runCapture(primary: Representation = .image) {
        Log.write("capture requested: mode=\(settings.captureMode.rawValue) selectionStyle=\(settings.regionSelectionStyle.rawValue)")
        capture.captureRegion(
            mode: settings.captureMode,
            selectionStyle: settings.regionSelectionStyle
        ) { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(CaptureService.CaptureError.cancelled):
                Log.write("capture cancelled")
                NSLog("Paste-Back: capture cancelled")
            case .failure(let error):
                Log.write("capture failed: \(String(describing: error))")
                NSLog("Paste-Back: capture failed: %@", String(describing: error))
            case .success(let captureResult):
                Log.write("""
                capture selected: rect=\(captureResult.rect.map { "\(Int($0.width))x\(Int($0.height))" } ?? "nil") \
                image=\(captureResult.image.width)x\(captureResult.image.height) \
                frontApp=\(captureResult.source.appName ?? "?")
                """)
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

            let canonicalText = CapturedScreenshot.canonicalText(ocrText: ocrResult.text, axText: ax.text)
            let technicalEntities = self.technicalRecognizer.entities(
                in: canonicalText,
                source: source,
                axElements: ax.elements
            )
            // Image-based: decode any QR/barcodes in the captured pixels.
            let barcodeEntities = self.barcodeService.entities(in: result.image)
            let entities = self.entityDetector.detect(
                in: canonicalText, seed: ax.entities + technicalEntities + barcodeEntities)

            let screenshot = CapturedScreenshot(
                image: result.image,
                captureRect: result.rect,
                source: source,
                ocrText: ocrResult.text,
                ocrLines: ocrResult.lines,
                axText: ax.text,
                axElements: ax.elements,
                axOutcome: ax.outcome,
                entities: entities
            )
            Log.write("""
            capture: ownerApp=\(source.appName ?? "?") frontApp=\(result.source.appName ?? "?") \
            pid=\(source.pid.map(String.init) ?? "?") \
            rect=\(result.rect.map { "\(Int($0.width))x\(Int($0.height))" } ?? "nil") \
            image=\(result.image.width)x\(result.image.height) \
            axTrusted=\(PermissionService.hasAccessibility()) \
            ocrLines=\(ocrResult.lines.count) axElems=\(ax.elements.count) axOutcome=\(ax.outcome.logValue) \
            axText=\(ax.text.count)chars ocrText=\(ocrResult.text.count)chars \
            canonicalText=\(canonicalText.count)chars entities=\(entities.count) \
            axLinks=\(ax.entities.count) ownerApps=\(ax.ownerPIDs.count) barcodes=\(barcodeEntities.count) \
            technical=\(technicalEntities.first.map { "\($0.type)" } ?? "nil") \
            pageURL=\(ax.pageURL?.absoluteString ?? "nil") \
            firstURL=\(entities.first { $0.type == .url }?.value ?? "nil")
            """)

            DispatchQueue.main.async {
                self.lastCapture = screenshot
                self.lastWrittenRepresentation = primary
                self.writer.write(screenshot, primary: primary)
                self.onCaptured?(screenshot)
                // History append runs on the store's own utility queue — the
                // capture path never blocks on disk I/O.
                self.historyStore.append(screenshot)
            }
        }
    }

    /// AX harvest: ground-truth enrichment when we own the rect, know the app,
    /// and have Accessibility permission. Empty otherwise → OCR floor stands.
    private struct AXResult {
        let text: String; let elements: [AXElement]
        let entities: [DetectedEntity]; let pageURL: URL?
        let ownerPID: pid_t?; let ownerPIDs: [pid_t]
        let outcome: AXOutcome
    }
    private func harvestAX(_ result: CaptureResult) -> AXResult {
        guard let rect = result.rect else {
            return AXResult(text: "", elements: [], entities: [], pageURL: nil,
                            ownerPID: nil, ownerPIDs: [], outcome: .notAttempted)
        }
        guard PermissionService.hasAccessibility() else {
            return AXResult(text: "", elements: [], entities: [], pageURL: nil,
                            ownerPID: nil, ownerPIDs: [], outcome: .noPermission)
        }
        if appQuirks.shouldSkipAX(appName: result.source.appName,
                                  bundleIdentifier: result.source.bundleIdentifier) {
            Log.write("ax skipped: app=\(result.source.appName ?? "?") bundle=\(result.source.bundleIdentifier ?? "?")")
            let app = result.source.appName ?? "This app"
            return AXResult(text: "", elements: [], entities: [], pageURL: nil,
                            ownerPID: nil, ownerPIDs: [],
                            outcome: .skipped(reason: "\(app) exposes unscoped Accessibility text"))
        }
        // The harvester discovers the app(s) under the selected pixels itself,
        // weighted by coverage; the frontmost app is only a fallback.
        let h = axHarvester.harvest(rect: rect, fallbackPID: result.source.pid)
        let outcome: AXOutcome = h.elements.isEmpty
            ? .emptyTree(retried: h.retryCount > 0)
            : .harvested(elementCount: h.elements.count, retried: h.retryCount > 0)
        return AXResult(text: h.text, elements: h.elements, entities: h.entities,
                        pageURL: h.pageURL, ownerPID: h.ownerPID, ownerPIDs: h.ownerPIDs,
                        outcome: outcome)
    }

    func recopy(as representation: Representation) {
        guard let lastCapture else { return }
        lastWrittenRepresentation = representation
        writer.write(lastCapture, primary: representation)
    }

    /// Makes a re-hydrated history capture the current "last capture" (so the
    /// HUD, re-copy menu, and recall all operate on it) without touching the
    /// clipboard.
    func adopt(_ capture: CapturedScreenshot) {
        lastCapture = capture
        lastWrittenRepresentation = nil
    }
}
