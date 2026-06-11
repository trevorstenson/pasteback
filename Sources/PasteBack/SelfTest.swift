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
        check(CaptureSummary(capture: hugeAXCap).sourceReason.contains("too broad"),
              "summary explains oversized AX fallback")

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

        // --- Stage 5: AX reliability + honest degradation ---
        let quirks = AppQuirks.current
        check(quirks.shouldSkipAX(appName: "Warp", bundleIdentifier: "dev.warp.Warp-Stable"),
              "AppQuirks skips Warp AX")
        check(quirks.needsNudge(appName: "Google Chrome", bundleIdentifier: "com.google.Chrome"),
              "AppQuirks marks Chromium apps as nudge candidates")

        let noPermissionSummary = CaptureSummary(capture: CapturedScreenshot(
            image: image,
            source: CaptureSource(appName: "Arc", bundleIdentifier: "company.thebrowser.Browser",
                                  pid: nil, url: nil),
            ocrText: "https://example.com",
            axOutcome: .noPermission))
        check(noPermissionSummary.sourceReason.contains("not granted"),
              "summary explains OCR fallback when AX permission is missing")

        let skippedSummary = CaptureSummary(capture: CapturedScreenshot(
            image: image, source: CaptureSource(appName: "Warp", bundleIdentifier: "dev.warp.Warp-Stable",
                                                pid: nil, url: nil),
            ocrText: "terminal output",
            axOutcome: .skipped(reason: "Warp exposes unscoped Accessibility text")))
        check(skippedSummary.sourceReason.contains("Warp exposes"),
              "summary explains app-specific AX skip")

        let emptyRetrySummary = CaptureSummary(capture: CapturedScreenshot(
            image: image, ocrText: "pixel text", axOutcome: .emptyTree(retried: true)))
        check(emptyRetrySummary.sourceReason.contains("after retry"),
              "summary explains empty AX tree after retry")

        let harvestedRetrySummary = CaptureSummary(capture: CapturedScreenshot(
            image: image, ocrText: "ocr", axText: "ax",
            axOutcome: .harvested(elementCount: 47, retried: true)))
        check(harvestedRetrySummary.sourceBadge == .ax
              && harvestedRetrySummary.sourceReason.contains("after retry"),
              "summary reports successful AX retry")

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

        // --- Stage 2: Image chip is the universal revert (always present, always last) ---
        func copyChipIDs(_ c: CapturedScreenshot) -> [String] {
            resolver.resolve(c) { _ in }.filter(\.isStateful).map(\.id)
        }
        check(copyChipIDs(capture).last == "rep-image",
              "Image chip is last in the copy group (URL capture)")
        let pinnedCodeIDs = copyChipIDs(codeCapture)
        check(pinnedCodeIDs.first == "rep-codeBlock" && pinnedCodeIDs.last == "rep-image",
              "Image chip stays last even when code leads the copies")
        check(copyChipIDs(CapturedScreenshot(image: image, ocrText: "")) == ["rep-image"],
              "Image chip is offered even for textless captures")

        // --- Stage 3: capture history round-trip + eviction ---
        let historyDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pasteback-selftest-\(UUID().uuidString)", isDirectory: true)
        let history = CaptureHistoryStore(baseURL: historyDir, isEnabled: { true })
        let histCapture = CapturedScreenshot(
            timestamp: Date(timeIntervalSinceNow: -100),
            image: image,
            source: CaptureSource(appName: "Arc", bundleIdentifier: "company.thebrowser.Browser",
                                  pid: 42, url: URL(string: "https://github.com/x/y/pull/1")),
            ocrText: "ocr text",
            axText: "ax ground truth",
            entities: [
                DetectedEntity(type: .url, value: "https://example.com", sourceText: "example",
                               source: .ax),
                DetectedEntity(type: .ticketID(system: "JIRA"), value: "ABC-123", sourceText: "ABC-123"),
                DetectedEntity(type: .codeBlock(language: "swift"), value: "let x = 1",
                               sourceText: "let x = 1"),
                DetectedEntity(type: .barcode(symbology: "QR"), value: "hello", sourceText: "hello"),
            ])
        history.append(histCapture)
        history.waitForPendingWrites()
        let storedRecords = history.records()
        check(storedRecords.count == 1, "history persists a capture record")
        if let record = storedRecords.first {
            check(FileManager.default.fileExists(atPath: history.imageURL(for: record.id).path)
                  && FileManager.default.fileExists(atPath: history.thumbnailURL(for: record.id).path),
                  "history writes capture.png + thumb.png")
            let rehydrated = history.rehydrate(record)
            check(rehydrated?.canonicalText == "ax ground truth",
                  "rehydrated capture keeps AX text")
            check(rehydrated?.entities.count == 4
                  && rehydrated?.entities.first?.source == .ax,
                  "entities survive the round-trip with their source")
            check(rehydrated?.entities.contains { $0.type == .ticketID(system: "JIRA") } == true
                  && rehydrated?.entities.contains { $0.type == .codeBlock(language: "swift") } == true
                  && rehydrated?.entities.contains { $0.type == .barcode(symbology: "QR") } == true,
                  "associated-value entity kinds round-trip")
            check(rehydrated?.source.url?.absoluteString == "https://github.com/x/y/pull/1"
                  && rehydrated?.source.appName == "Arc",
                  "provenance survives the round-trip")
            let recordReps = history.availableRepresentations(for: record)
            check(recordReps.contains(.image) && recordReps.contains(.plainText)
                  && recordReps.contains(.firstURL),
                  "representations are computable from a record")
            check(record.searchableText.localizedCaseInsensitiveContains("ABC-123"),
                  "history search text covers entity values")
        }
        history.maxRecords = 3
        for i in 0..<3 {
            history.append(CapturedScreenshot(
                timestamp: Date(timeIntervalSinceNow: Double(i)),
                image: image, ocrText: "filler \(i)"))
        }
        history.waitForPendingWrites()
        let afterEvict = history.records()
        check(afterEvict.count == 3, "history enforces the record cap")
        check(!afterEvict.contains { $0.id == histCapture.id },
              "history evicts the oldest capture first")
        let disabledHistory = CaptureHistoryStore(baseURL: historyDir, isEnabled: { false })
        disabledHistory.append(histCapture)
        disabledHistory.waitForPendingWrites()
        check(disabledHistory.records().count == 3, "history opt-out makes append a no-op")
        history.clear()
        check(history.records().isEmpty, "Clear History empties the store")
        try? FileManager.default.removeItem(at: historyDir)
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

        // --- Stage 6: Table → CSV ---
        let tableRecognizer = TableRecognizer()
        func gridEl(_ x: CGFloat, _ y: CGFloat, _ t: String) -> AXElement {
            AXElement(role: "AXStaticText", text: t, url: nil,
                      frame: CGRect(x: x, y: y, width: 160, height: 16), sourcePID: 0)
        }
        // Rung 2: AX geometry — 3×2 grid.
        let axGridElements = [
            gridEl(0, 0, "Name"),  gridEl(200, 0, "Qty"),
            gridEl(0, 30, "Apple"), gridEl(200, 30, "3"),
            gridEl(0, 60, "Pear"),  gridEl(200, 60, "12"),
        ]
        let axTable = tableRecognizer.inferFromAX(elements: axGridElements)
        check(axTable?.rowCount == 3 && axTable?.columnCount == 2 && axTable?.source == .ax,
              "TableRecognizer infers a 3×2 table from AX geometry")
        check(axTable?.isStructural == false,
              "AX leaf-geometry tables are not marked structural")
        check(axTable?.rows == [["Name", "Qty"], ["Apple", "3"], ["Pear", "12"]],
              "AX-geometry table cells land in the right rows/columns")

        // Rung 3: OCR geometry — Vision-normalized boxes (origin bottom-left).
        func ocrCell(_ x: CGFloat, _ minY: CGFloat, _ t: String) -> OCRLine {
            OCRLine(text: t, boundingBox: CGRect(x: x, y: minY, width: 0.2, height: 0.05))
        }
        let ocrGrid = [
            ocrCell(0.1, 0.85, "A"), ocrCell(0.6, 0.85, "B"),
            ocrCell(0.1, 0.65, "C"), ocrCell(0.6, 0.65, "D"),
            ocrCell(0.1, 0.45, "E"), ocrCell(0.6, 0.45, "F"),
        ]
        let ocrTable = tableRecognizer.inferFromOCR(lines: ocrGrid)
        check(ocrTable?.rowCount == 3 && ocrTable?.columnCount == 2 && ocrTable?.source == .ocr,
              "TableRecognizer infers a 3×2 table from OCR geometry")
        check(ocrTable?.isStructural == false,
              "OCR-geometry tables are not marked structural")
        check(ocrTable?.rows.first == ["A", "B"] && ocrTable?.rows.last == ["E", "F"],
              "OCR-geometry rows are ordered top→bottom after Y flip")

        // Vision often returns one observation per visual row; word boxes are
        // what make screenshot-of-table OCR useful.
        func token(_ x: CGFloat, _ minY: CGFloat, _ w: CGFloat, _ t: String) -> OCRToken {
            OCRToken(text: t, boundingBox: CGRect(x: x, y: minY, width: w, height: 0.05))
        }
        func mergedOCRRow(_ minY: CGFloat, _ words: [(CGFloat, CGFloat, String)]) -> OCRLine {
            let text = words.map(\.2).joined(separator: " ")
            return OCRLine(
                text: text,
                boundingBox: CGRect(x: 0.08, y: minY, width: 0.84, height: 0.05),
                tokens: words.map { token($0.0, minY, $0.1, $0.2) })
        }
        let mergedOCRRows = [
            mergedOCRRow(0.85, [(0.10, 0.10, "Plan"), (0.42, 0.06, "Seats"), (0.62, 0.08, "Price")]),
            mergedOCRRow(0.65, [(0.10, 0.12, "Starter"), (0.42, 0.03, "3"), (0.62, 0.05, "$0")]),
            mergedOCRRow(0.45, [(0.10, 0.10, "Team"), (0.42, 0.04, "12"), (0.62, 0.07, "$20")]),
        ]
        let mergedOCRTable = tableRecognizer.inferFromOCR(lines: mergedOCRRows)
        check(mergedOCRTable?.rows == [["Plan", "Seats", "Price"], ["Starter", "3", "$0"], ["Team", "12", "$20"]],
              "TableRecognizer recovers a table from Vision merged-row OCR using word boxes")

        // A single spanning/caption cell should not collapse every column.
        let spanningGrid = [
            AXElement(role: "AXStaticText", text: "Quarterly plan summary across all columns",
                      url: nil, frame: CGRect(x: 0, y: -30, width: 360, height: 16), sourcePID: 0),
            gridEl(0, 0, "Plan"),  gridEl(200, 0, "Qty"),
            gridEl(0, 30, "Apple"), gridEl(200, 30, "3"),
            gridEl(0, 60, "Pear"),  gridEl(200, 60, "12"),
        ]
        let spanningTable = tableRecognizer.inferFromAX(elements: spanningGrid)
        check(spanningTable?.columnCount == 2,
              "TableRecognizer keeps columns when one row spans the gutter")

        // Multi-column prose must NOT be read as a table (median cell > ~40 chars).
        let proseGrid = [
            gridEl(0, 0, "The quick brown fox jumps over the lazy dog every morning"),
            gridEl(200, 0, "While the second column carries an equally long sentence here"),
            gridEl(0, 30, "Another paragraph of prose that wraps across the column width"),
            gridEl(200, 30, "And its neighbor likewise runs well beyond forty characters wide"),
            gridEl(0, 60, "A third left line continuing the flowing multi-column body text"),
            gridEl(200, 60, "Matched on the right by yet another long-form prose continuation"),
        ]
        check(tableRecognizer.inferFromAX(elements: proseGrid) == nil,
              "TableRecognizer rejects multi-column prose as a table")

        // CSV quoting matrix (RFC-4180) + CRLF row endings.
        let quotingTable = TableData(
            headers: ["a", "b,c"],
            rows: [["x\"y", "line1\nline2"], ["p", "q"]],
            source: .ocr)
        let csv = TableFormatter.csv(quotingTable)
        check(csv.contains("\"b,c\""), "CSV quotes fields containing commas")
        check(csv.contains("\"x\"\"y\""), "CSV doubles embedded quotes")
        check(csv.contains("\"line1\nline2\""), "CSV quotes fields containing newlines")
        check(csv.contains("\r\n"), "CSV uses CRLF row endings")

        // Markdown pipe table.
        let md = TableFormatter.markdown(TableData(headers: ["H1", "H2"], rows: [["a", "b"]], source: .ax))
        check(md == "| H1 | H2 |\n| --- | --- |\n| a | b |", "TableFormatter emits a Markdown pipe table")
        let markdownCapture = CapturedScreenshot(
            image: image,
            ocrText: "Intro paragraph",
            tables: [TableData(headers: ["H"], rows: [["a"]], source: .ocr)])
        let markdownPayload = RepresentationBuilder().payload(for: .markdown, from: markdownCapture)
        let markdownText = markdownPayload.flatMap { String(data: $0.data, encoding: .utf8) } ?? ""
        check(markdownText.contains("Intro paragraph") && markdownText.contains("| H |"),
              "Markdown table payload preserves surrounding text")

        // TSV rides the plain-text flavor when a table is the primary (cells, not
        // one column) and an explicit CSV type rides alongside.
        let tableCapture = CapturedScreenshot(
            image: image, ocrText: "",
            tables: [TableData(headers: nil, rows: [["A", "B"], ["C", "D"]], source: .ocr)])
        check(RepresentationBuilder().availableRepresentations(for: tableCapture).contains(.csv),
              "Table (CSV) chip offered when a table is present")
        _ = writer.write(tableCapture, primary: .csv)
        check(pb.string(forType: .string) == "A\tB\nC\tD",
              "Table-primary writes TSV to the plain-text flavor")
        check(pb.data(forType: RepresentationBuilder.csvType) != nil,
              "Table-primary also carries an explicit CSV flavor")
        check(pb.data(forType: .png) == nil,
              "Table-primary carries no image (so spreadsheets paste cells, not a picture)")
        let tableChipIDs = copyChipIDs(tableCapture)
        check(tableChipIDs.first == "rep-csv" && tableChipIDs.last == "rep-image",
              "Copy as Table leads the copy group; Image stays last")
        check(actionIDs(tableCapture).contains("save-csv"),
              "ActionResolver offers Save CSV for a table capture")
        check(actionIDs(tableCapture).first != "save-csv",
              "Geometry-inferred tables do not promote Save CSV ahead of copy actions")
        let structuralTableCapture = CapturedScreenshot(
            image: image,
            ocrText: "",
            tables: [TableData(headers: nil, rows: [["A", "B"], ["C", "D"]],
                               source: .ax, isStructural: true)])
        check(actionIDs(structuralTableCapture).first == "save-csv",
              "AX-structural tables can lead with Save CSV")
        let axGeometryTableCapture = CapturedScreenshot(
            image: image,
            ocrText: "",
            tables: [TableData(headers: nil, rows: [["A", "B"], ["C", "D"]],
                               source: .ax, isStructural: false)])
        check(actionIDs(axGeometryTableCapture).first != "save-csv",
              "AX-geometry tables do not promote Save CSV ahead of copy actions")
        let tableSummary = CaptureSummary(capture: tableCapture)
        check(tableSummary.tableShape == "2×2" && tableSummary.metadataText.contains("2×2 table"),
              "summary reports the table shape")

        // Tables survive the history persistence round-trip.
        let tableRecord = CaptureRecord(capture: CapturedScreenshot(
            image: image, ocrText: "",
            tables: [TableData(headers: ["H"], rows: [["a"], ["b"]],
                               source: .ax, isStructural: true)]))
        let encodedRecord = try? JSONEncoder().encode(tableRecord)
        let decodedRecord = encodedRecord.flatMap { try? JSONDecoder().decode(CaptureRecord.self, from: $0) }
        let roundTrippedTables = decodedRecord?.detectedTables()
        check(roundTrippedTables?.first?.headers == ["H"]
              && roundTrippedTables?.first?.rows == [["a"], ["b"]]
              && roundTrippedTables?.first?.source == .ax,
              "tables round-trip through CaptureRecord")
        check(roundTrippedTables?.first?.isStructural == true,
              "table structural confidence round-trips through CaptureRecord")

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
