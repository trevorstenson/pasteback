import AppKit

/// Builds clipboard payloads for each `Representation` from a capture, and
/// decides which types ride together on the pasteboard for a given primary.
/// Uses `capture.canonicalText` (AX text when present, else OCR) and ground-truth
/// entity URLs so links are exact once AX harvest is in (M1).
struct RepresentationBuilder {

    struct Payload {
        let type: NSPasteboard.PasteboardType
        let data: Data
    }

    // MARK: - Pasteboard composition

    func payloads(for primary: Representation, from capture: CapturedScreenshot) -> [Payload] {
        switch primary {
        case .firstURL, .firstEmail, .firstPhone, .codeBlock:
            var result: [Payload] = []
            if let p = payload(for: primary, from: capture) { result.append(p) }
            if primary == .firstURL, let url = firstValue(.url, capture) {
                result.append(Payload(type: .URL, data: Data(url.utf8)))
            }
            return result

        case .image:
            return payload(for: .image, from: capture).map { [$0] } ?? []

        case .plainText, .markdown, .rtf, .html:
            var ordered: [Payload] = []
            var seen = Set<NSPasteboard.PasteboardType>()
            func add(_ p: Payload?) {
                guard let p, !seen.contains(p.type) else { return }
                seen.insert(p.type); ordered.append(p)
            }
            add(payload(for: primary, from: capture))
            add(payload(for: .plainText, from: capture))
            add(payload(for: .rtf, from: capture))
            add(payload(for: .html, from: capture))
            add(payload(for: .image, from: capture))
            if urls(capture).count == 1, let only = urls(capture).first {
                add(Payload(type: .URL, data: Data(only.utf8)))
            }
            return ordered
        }
    }

    func availableRepresentations(for capture: CapturedScreenshot) -> [Representation] {
        var reps: [Representation] = [.image]
        if !capture.canonicalText.isEmpty {
            reps.append(.plainText)
            reps.append(.markdown)
        }
        if !urls(capture).isEmpty { reps.append(.firstURL) }
        if firstValue(.email, capture) != nil { reps.append(.firstEmail) }
        if hasCode(capture) { reps.append(.codeBlock) }
        return reps
    }

    // MARK: - Per-representation payloads

    func payload(for representation: Representation, from capture: CapturedScreenshot) -> Payload? {
        let text = capture.canonicalText
        switch representation {
        case .image:
            return pngData(from: capture.image).map { Payload(type: .png, data: $0) }
        case .plainText, .markdown:
            guard !text.isEmpty else { return nil }
            return Payload(type: .string, data: Data(text.utf8))
        case .rtf:
            return richTextData(for: capture).map { Payload(type: .rtf, data: $0) }
        case .html:
            return htmlString(for: capture).map { Payload(type: .html, data: Data($0.utf8)) }
        case .firstURL:
            return firstValue(.url, capture).map { Payload(type: .string, data: Data($0.utf8)) }
        case .firstEmail:
            return firstValue(.email, capture).map { Payload(type: .string, data: Data($0.utf8)) }
        case .firstPhone:
            return firstValue(.phone, capture).map { Payload(type: .string, data: Data($0.utf8)) }
        case .codeBlock:
            guard let code = codeEntity(capture) else { return nil }
            let language = codeLanguage(code) ?? ""
            return Payload(type: .string, data: Data("```\(language)\n\(code.value)\n```".utf8))
        }
    }

    // MARK: - Entity helpers

    private func urls(_ capture: CapturedScreenshot) -> [String] {
        capture.entities.filter { $0.type == .url }.map(\.value)
    }
    private func firstValue(_ type: EntityType, _ capture: CapturedScreenshot) -> String? {
        capture.entities.first { $0.type == type }?.value
    }
    private func hasCode(_ capture: CapturedScreenshot) -> Bool {
        codeEntity(capture) != nil
    }
    private func codeEntity(_ capture: CapturedScreenshot) -> DetectedEntity? {
        capture.entities.first {
            if case .codeBlock = $0.type { return true }
            return false
        } ?? capture.entities.first {
            if case .stackTrace = $0.type { return true }
            return false
        }
    }
    private func codeLanguage(_ entity: DetectedEntity) -> String? {
        if case .codeBlock(let language) = entity.type {
            return language
        }
        return nil
    }

    // MARK: - Rich text

    private func attributedText(for capture: CapturedScreenshot) -> NSAttributedString? {
        let text = capture.canonicalText
        guard !text.isEmpty else { return nil }
        let attributed = NSMutableAttributedString(
            string: text, attributes: [.font: NSFont.systemFont(ofSize: NSFont.systemFontSize)])
        let ns = text as NSString
        for entity in capture.entities where entity.type == .url {
            let range = ns.range(of: entity.sourceText)
            if range.location != NSNotFound, let url = URL(string: entity.value) {
                attributed.addAttribute(.link, value: url, range: range)
            }
        }
        return attributed
    }

    private func richTextData(for capture: CapturedScreenshot) -> Data? {
        guard let a = attributedText(for: capture) else { return nil }
        return try? a.data(from: NSRange(location: 0, length: a.length),
                           documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
    }

    private func htmlString(for capture: CapturedScreenshot) -> String? {
        let text = capture.canonicalText
        guard !text.isEmpty else { return nil }
        var html = escapeHTML(text)
        for entity in capture.entities where entity.type == .url {
            let escSource = escapeHTML(entity.sourceText)
            html = html.replacingOccurrences(
                of: escSource, with: "<a href=\"\(escapeHTML(entity.value))\">\(escSource)</a>")
        }
        return "<html><body>\(html.replacingOccurrences(of: "\n", with: "<br>\n"))</body></html>"
    }

    private func escapeHTML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private func pngData(from image: CGImage) -> Data? {
        NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }
}
