import AppKit
import CoreImage

/// Headless verification of OCR → entity detection → representation → pasteboard,
/// runnable without interactive capture: `PasteBack --selftest`.
enum SelfTest {

    static func run() -> Never {
        var failures: [String] = []
        func check(_ cond: Bool, _ label: String) {
            print(cond ? "✓ \(label)" : "✗ \(label)")
            if !cond { failures.append(label) }
        }

        let sample = "Visit https://example.com or email team@example.com"
        guard let image = renderText(sample) else {
            print("✗ render failed\nSELFTEST FAIL"); exit(1)
        }

        guard let result = try? OCRService().recognize(in: image) else {
            print("✗ OCR threw\nSELFTEST FAIL"); exit(1)
        }
        print("OCR text: \(result.text)")
        check(result.text.lowercased().contains("example.com"), "OCR recognized URL token")

        let entities = EntityDetector().detect(in: result.text)
        let hasURL = entities.contains { $0.type == .url }
        let hasEmail = entities.contains { $0.type == .email }
        check(hasURL, "detected a URL entity")
        check(hasEmail, "detected an email entity")
        let relativePathEntities = EntityDetector().detect(in: "./Sources/PasteBack/AppDelegate.swift")
        check(!relativePathEntities.contains { $0.type == .filePath },
              "relative paths do not trigger Reveal in Finder")
        let existingPathEntities = EntityDetector().detect(in: FileManager.default.currentDirectoryPath)
        check(existingPathEntities.contains { $0.type == .filePath },
              "existing absolute paths trigger Reveal in Finder")

        let capture = CapturedScreenshot(
            image: image, ocrText: result.text, ocrLines: result.lines, entities: entities)

        let reps = RepresentationBuilder().availableRepresentations(for: capture)
        print("Chips: \(reps.map(\.title))")
        check(reps.contains(.image) && reps.contains(.plainText), "image + text chips offered")
        if hasURL { check(reps.contains(.firstURL), "First URL chip when URL present") }

        let writer = PasteboardWriter()
        let pb = NSPasteboard.general

        if hasURL {
            _ = writer.write(capture, primary: .firstURL)
            let pasted = pb.string(forType: .string) ?? ""
            let urlValue = entities.first { $0.type == .url }?.value ?? "—"
            check(pasted == urlValue, "First URL pastes exactly the URL")
            check(pb.data(forType: .png) == nil, "First URL carries no image")
            check(pb.data(forType: .URL) != nil, "First URL sets public.url")
        }

        _ = writer.write(capture, primary: .plainText)
        check(pb.types?.first == .string, "Text mode primary is plain text")
        check(pb.data(forType: .rtf) != nil, "Text mode carries RTF")
        check(pb.data(forType: .html) != nil, "Text mode carries HTML")
        check(pb.data(forType: .png) != nil, "Text mode carries the image")

        _ = writer.write(capture, primary: .image)
        check(pb.types?.first == .png, "Image mode primary is PNG")
        check(pb.string(forType: .string) == nil, "Image mode is image-only")

        // AX-preference: canonicalText prefers AX text when present.
        let axCap = CapturedScreenshot(
            image: image, ocrText: "ocr fallback", axText: "ax ground truth")
        check(axCap.canonicalText == "ax ground truth", "canonicalText prefers AX over OCR")
        let hugeAXCap = CapturedScreenshot(
            image: image,
            ocrText: "selected text from pixels",
            axText: String(repeating: "terminal scrollback ", count: 30_000))
        check(hugeAXCap.canonicalText == "selected text from pixels",
              "canonicalText rejects oversized AX scrollback")

        // --- Stage 1: CaptureSummary (HUD preview row) ---
        let summaryCapture = CapturedScreenshot(
            image: image,
            source: CaptureSource(appName: "Arc", bundleIdentifier: "company.thebrowser.Browser",
                                  pid: nil, url: nil),
            ocrText: "ocr guess",
            axText: "Sign in to your account\nor create a new one",
            entities: [
                DetectedEntity(type: .url, value: "https://a.example.com", sourceText: "a", source: .ax),
                DetectedEntity(type: .url, value: "https://b.example.com", sourceText: "b", source: .ax),
                DetectedEntity(type: .email, value: "x@example.com", sourceText: "x@example.com"),
            ])
        let axSummary = CaptureSummary(capture: summaryCapture)
        check(axSummary.sourceBadge == .ax, "summary badge is AX when AX text wins")
        check(axSummary.lineCount == 2 && axSummary.linkCount == 2 && axSummary.entityCount == 1,
              "summary counts lines/links/entities")
        check(axSummary.previewText.hasPrefix("Sign in to your account"),
              "summary preview comes from canonical text")
        check(axSummary.appName == "Arc", "summary carries the source app name")
        check(axSummary.metadataText == "2 lines · 2 links · 1 entity",
              "summary metadata line is assembled correctly")

        check(CaptureSummary(capture: hugeAXCap).sourceBadge == .ocr,
              "summary badge falls back to OCR on oversized-AX rejection")

        let mixedCap = CapturedScreenshot(
            image: image, ocrText: "ocr only text",
            entities: [DetectedEntity(type: .url, value: "https://x.example.com",
                                      sourceText: "x", source: .ax)])
        check(CaptureSummary(capture: mixedCap).sourceBadge == .mixed,
              "summary badge is AX+OCR when AX entities seed OCR text")

        let imageOnlyCap = CapturedScreenshot(image: image, ocrText: "")
        let imageOnlySummary = CaptureSummary(capture: imageOnlyCap)
        check(imageOnlySummary.previewText == "Image only" && imageOnlySummary.isImageOnly,
              "summary reads 'Image only' for textless captures")
        check(imageOnlySummary.sourceBadge == .ocr && imageOnlySummary.metadataText.isEmpty,
              "image-only summary has no counts")

        let longCap = CapturedScreenshot(
            image: image, ocrText: String(repeating: "word ", count: 40))
        let longSummary = CaptureSummary(capture: longCap)
        check(longSummary.previewText.count <= CaptureSummary.previewLimit + 1
              && longSummary.previewText.hasSuffix("…"),
              "summary preview truncates to ~60 chars with ellipsis")

        let settings = SettingsStore.shared
        settings.autoDismissSeconds = 7
        check(UserDefaults.standard.double(forKey: "autoDismissSeconds") == 7,
              "settings persist to UserDefaults")

        let recognizer = TechnicalContentRecognizer()
        let swiftSample = """
        12 | import Foundation
        13 | struct User {
        14 |     let id: UUID
        15 |     func displayName() -> String {
        16 |         return "User \\(id.uuidString)"
        17 |     }
        18 | }
        """
        let swiftRecognition = recognizer.recognize(in: swiftSample, source: CaptureSource(
            appName: "Xcode", bundleIdentifier: "com.apple.dt.Xcode", pid: nil, url: nil))
        check(swiftRecognition?.language == "swift", "technical recognizer identifies Swift")
        check(swiftRecognition?.normalizedText.contains("12 |") == false,
              "technical recognizer strips line gutters")
        let codeEntities = recognizer.entities(in: swiftSample, source: CaptureSource(
            appName: "Xcode", bundleIdentifier: "com.apple.dt.Xcode", pid: nil, url: nil), axElements: [])
        let codeCapture = CapturedScreenshot(image: image, ocrText: swiftSample, entities: codeEntities)
        let codePayload = RepresentationBuilder().payload(for: .codeBlock, from: codeCapture)
        let codePaste = codePayload.flatMap { String(data: $0.data, encoding: .utf8) } ?? ""
        check(RepresentationBuilder().availableRepresentations(for: codeCapture).contains(.codeBlock),
              "Code chip offered for recognized code")
        check(codePaste.hasPrefix("```swift\n") && !codePaste.contains("12 |"),
              "Code chip uses language and normalized text")

        let rustWithChrome = """
        PasteBack Code Detection Fixture
        New Tab Rust
        pub fn normalize(input: &str) -> String {
            input
                .lines()
                .map(str::trim_end)
                .filter(|line| !line.is_empty())
                .collect::<Vec<_>>()
                .join("\\n")
        }
        """
        let rustRecognition = recognizer.recognize(in: rustWithChrome, source: CaptureSource(
            appName: "Safari", bundleIdentifier: "com.apple.Safari", pid: nil, url: nil))
        check(rustRecognition?.language == "rust", "technical recognizer identifies Rust with page chrome")
        check(rustRecognition?.normalizedText.hasPrefix("pub fn normalize") == true &&
              !rustRecognition!.normalizedText.contains("PasteBack Code Detection Fixture"),
              "technical recognizer drops surrounding page chrome")

        let typescriptWithHeader = """
        PasteBack Code Detection Fixture
        New Tab TypeScript / React
        type CaptureAction = {
          id: string;
          title: string;
          perform: () => Promise<void>;
        };

        export function Chip({ action }: { action: CaptureAction }) {
          return <button onClick={() => action.perform()}>
            {action.title}
          </button>;
        }
        """
        let tsRecognition = recognizer.recognize(in: typescriptWithHeader, source: CaptureSource(
            appName: "Safari", bundleIdentifier: "com.apple.Safari", pid: nil, url: nil))
        check(tsRecognition?.language == "typescript", "technical recognizer identifies TypeScript with page chrome")
        check(tsRecognition?.normalizedText.hasPrefix("type CaptureAction") == true &&
              tsRecognition!.normalizedText.contains("export function Chip"),
              "technical recognizer keeps full TypeScript snippet")

        let jsonRecognition = recognizer.recognize(
            in: #"{"name":"PasteBack","enabled":true,"count":3}"#,
            source: CaptureSource(appName: nil, bundleIdentifier: nil, pid: nil, url: nil))
        check(jsonRecognition?.language == "json", "technical recognizer identifies JSON")

        let commandRecognition = recognizer.recognize(
            in: "$ git checkout -b feature/code-recognizer",
            source: CaptureSource(appName: "Terminal", bundleIdentifier: "com.apple.Terminal", pid: nil, url: nil))
        check(commandRecognition?.language == "bash", "technical recognizer identifies shell commands")
        check(commandRecognition?.normalizedText.hasPrefix("git checkout") == true,
              "technical recognizer strips shell prompts")

        let stackRecognition = recognizer.recognize(
            in: "Traceback (most recent call last):\n  File \"app.py\", line 10, in <module>\nValueError: bad",
            source: CaptureSource(appName: nil, bundleIdentifier: nil, pid: nil, url: nil))
        check(stackRecognition?.kind == .stackTrace, "technical recognizer identifies stack traces")

        let proseRecognition = recognizer.recognize(
            in: "This is a regular paragraph about a project plan. It has several sentences but no code.",
            source: CaptureSource(appName: nil, bundleIdentifier: nil, pid: nil, url: nil))
        check(proseRecognition == nil, "technical recognizer rejects ordinary prose")

        // --- Four entity→action primitives ---
        let isoDate = ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: 1_700_000_000))
        let dateCapture = CapturedScreenshot(
            image: image, ocrText: "Team sync\nThursday 3pm",
            entities: [DetectedEntity(type: .date, value: isoDate, sourceText: "Thursday 3pm")])
        let ics = CalendarEventBuilder().icsFileURL(for: dateCapture)
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        check(ics.contains("BEGIN:VCALENDAR") && ics.contains("DTSTART") && ics.contains("SUMMARY"),
              "CalendarEventBuilder emits a valid VEVENT")

        let mapsURL = MapsLinkBuilder().url(for: "1 Infinite Loop, Cupertino CA")?.absoluteString ?? ""
        check(mapsURL.contains("maps.apple.com") && mapsURL.contains("Infinite%20Loop"),
              "MapsLinkBuilder builds an encoded Apple Maps URL")

        let sigCapture = CapturedScreenshot(
            image: image,
            ocrText: "Jane Doe\nSenior Engineer, Acme Corp\njane@acme.com\n+1 415 555 1234",
            entities: [
                DetectedEntity(type: .email, value: "jane@acme.com", sourceText: "jane@acme.com"),
                DetectedEntity(type: .phone, value: "+14155551234", sourceText: "+1 415 555 1234"),
            ])
        let contact = ContactExtractor().extract(from: sigCapture)
        check(contact?.name == "Jane Doe", "ContactExtractor finds the name")
        check(contact?.emails.first == "jane@acme.com" && contact?.phones.isEmpty == false,
              "ContactExtractor collects email + phone")
        let vcf = contact.flatMap { ContactExtractor().vCardFileURL(for: $0) }
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        check(vcf.contains("FN:Jane Doe") && vcf.contains("EMAIL") && vcf.contains("TEL:"),
              "ContactExtractor emits a vCard")

        if let qr = makeQR("https://pasteback.app/hi") {
            check(BarcodeService().decode(in: qr).contains { $0.value.contains("pasteback.app") },
                  "BarcodeService decodes a QR code")
        } else {
            check(false, "QR fixture render failed")
        }

        let resolver = ActionResolver()
        func actionIDs(_ c: CapturedScreenshot) -> [String] { resolver.resolve(c) { _ in }.map(\.id) }
        let addrCapture = CapturedScreenshot(
            image: image, ocrText: "1 Infinite Loop, Cupertino CA",
            entities: [DetectedEntity(type: .address, value: "1 Infinite Loop, Cupertino CA",
                                      sourceText: "1 Infinite Loop, Cupertino CA")])
        check(actionIDs(addrCapture).contains("open-maps"), "ActionResolver offers Open in Maps")
        check(actionIDs(dateCapture).contains("add-calendar"), "ActionResolver offers Add to Calendar")
        check(actionIDs(sigCapture).contains("save-contact"), "ActionResolver offers Save Contact")
        let qrCapture = CapturedScreenshot(
            image: image, ocrText: "",
            entities: [DetectedEntity(type: .barcode(symbology: "QR"),
                                      value: "https://pasteback.app", sourceText: "https://pasteback.app")])
        check(actionIDs(qrCapture).contains("qr-open"), "ActionResolver offers Open QR Link")

        // --- Column-aware AX text assembly (no side-by-side row interleaving) ---
        func axEl(_ x: CGFloat, _ y: CGFloat, _ t: String) -> AXElement {
            AXElement(role: "AXStaticText", text: t, url: nil,
                      frame: CGRect(x: x, y: y, width: 180, height: 16), sourcePID: 0)
        }
        let harvester = AXHarvester()
        let twoColumns = [
            axEl(0, 0, "Alpha one"),   axEl(400, 0, "Beta one"),
            axEl(0, 30, "Alpha two"),  axEl(400, 30, "Beta two"),
        ]
        let assembled = harvester.assembleText(from: twoColumns)
        check(assembled.contains("Alpha one\nAlpha two") && assembled.contains("Beta one\nBeta two"),
              "assembleText keeps each column intact")
        check(!assembled.contains("Alpha one Beta one"),
              "assembleText does not zipper side-by-side columns row by row")
        let oneColumn = [axEl(0, 0, "Line A"), axEl(0, 30, "Line B")]
        check(harvester.assembleText(from: oneColumn) == "Line A\nLine B",
              "assembleText leaves a single column unchanged")

        print(failures.isEmpty ? "\nSELFTEST PASS" : "\nSELFTEST FAIL (\(failures.count))")
        exit(failures.isEmpty ? 0 : 1)
    }

    private static func renderText(_ text: String) -> CGImage? {
        let size = NSSize(width: 1100, height: 110)
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.white.setFill(); NSRect(origin: .zero, size: size).fill()
        (text as NSString).draw(at: NSPoint(x: 20, y: 35),
            withAttributes: [.font: NSFont.systemFont(ofSize: 34), .foregroundColor: NSColor.black])
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.cgImage
    }

    /// Renders a QR code for the given string (test fixture for BarcodeService).
    private static func makeQR(_ string: String) -> CGImage? {
        guard let data = string.data(using: .utf8),
              let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        return CIContext().createCGImage(scaled, from: scaled.extent)
    }
}
