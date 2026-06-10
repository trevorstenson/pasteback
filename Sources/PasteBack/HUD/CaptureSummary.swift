import Foundation

/// At-a-glance description of a capture for the HUD preview row: what text we
/// got, how much, where it came from. Pure value computed from a
/// `CapturedScreenshot` — covered by `--selftest`.
struct CaptureSummary {

    /// Where the capture's content came from. AX is ground truth; OCR is the
    /// pixel floor; mixed means OCR text seeded with AX entities (real hrefs).
    enum SourceBadge: String, Equatable {
        case ax = "AX"
        case ocr = "OCR"
        case mixed = "AX+OCR"
    }

    static let previewLimit = 60

    let previewText: String
    let isImageOnly: Bool
    let lineCount: Int
    let linkCount: Int
    /// Non-link entities (emails, phones, dates, paths, ticket IDs, …).
    let entityCount: Int
    let sourceBadge: SourceBadge
    let appName: String?

    init(capture: CapturedScreenshot) {
        let canonical = capture.canonicalText

        let collapsed = canonical
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if collapsed.isEmpty {
            previewText = "Image only"
            isImageOnly = true
        } else if collapsed.count > Self.previewLimit {
            let head = String(collapsed.prefix(Self.previewLimit))
                .trimmingCharacters(in: .whitespaces)
            previewText = head + "…"
            isImageOnly = false
        } else {
            previewText = collapsed
            isImageOnly = false
        }

        lineCount = canonical
            .split(whereSeparator: \.isNewline)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .count
        let links = capture.entities.filter { $0.type == .url }
        linkCount = links.count
        entityCount = capture.entities.count - links.count

        // Badge: AX when the canonical text is the AX harvest; mixed when the
        // text fell back to OCR but AX still contributed ground-truth entities
        // (or an oversized AX leaf was rejected); pure OCR otherwise.
        let usedAXText = !capture.axText.isEmpty && canonical == capture.axText
        let hasAXContribution = capture.entities.contains { $0.source == .ax }
        if usedAXText {
            sourceBadge = .ax
        } else if hasAXContribution {
            sourceBadge = .mixed
        } else {
            sourceBadge = .ocr
        }

        appName = capture.source.appName
    }

    /// "14 lines · 3 links · 2 entities" — empty when there is nothing to count.
    var metadataText: String {
        var parts: [String] = []
        if lineCount > 0 { parts.append("\(lineCount) \(lineCount == 1 ? "line" : "lines")") }
        if linkCount > 0 { parts.append("\(linkCount) \(linkCount == 1 ? "link" : "links")") }
        if entityCount > 0 { parts.append("\(entityCount) \(entityCount == 1 ? "entity" : "entities")") }
        return parts.joined(separator: " · ")
    }
}
