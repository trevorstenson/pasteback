import AppKit

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
        check(pb.string(forType: .string) != nil, "Image mode carries text")

        // AX-preference: canonicalText prefers AX text when present.
        let axCap = CapturedScreenshot(
            image: image, ocrText: "ocr fallback", axText: "ax ground truth")
        check(axCap.canonicalText == "ax ground truth", "canonicalText prefers AX over OCR")

        let settings = SettingsStore.shared
        settings.autoDismissSeconds = 7
        check(UserDefaults.standard.double(forKey: "autoDismissSeconds") == 7,
              "settings persist to UserDefaults")

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
}
