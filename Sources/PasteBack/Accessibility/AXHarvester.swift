import AppKit
import ApplicationServices

/// Harvests the Accessibility subtree under a captured region to recover
/// ground-truth structure the pixels threw away: real link URLs, exact text,
/// element roles. This is the moat — strictly better than OCR when available,
/// and silently empty when the app exposes no AX tree (→ caller falls back to OCR).
///
/// All AX calls are synchronous IPC to the target app, so the walk is bounded by
/// depth/element caps, a per-message timeout, and frame-intersection pruning
/// (children are contained within their parent's frame, so a non-intersecting
/// subtree can be skipped wholesale).
final class AXHarvester {

    struct Result {
        let text: String
        let elements: [AXElement]
        let entities: [DetectedEntity]
        /// The page/document URL (browser tab) — provenance, not a selected link.
        let pageURL: URL?
    }

    private let maxDepth = 80
    private let maxElements = 6000
    private let messagingTimeout: Float = 0.2   // seconds per AX call

    /// `rect` is in CoreGraphics top-left screen coordinates (same space AX uses).
    func harvest(rect: CGRect, pid: pid_t) -> Result {
        guard AXIsProcessTrusted() else {
            return Result(text: "", elements: [], entities: [], pageURL: nil)
        }

        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, messagingTimeout)
        nudgeWebAccessibility(app)

        var collected: [AXElement] = []
        var visited = 0
        walk(app, rect: rect, depth: 0, visited: &visited, into: &collected)

        let text = assembleText(from: collected)

        // The page container (AXWebArea/AXScrollArea) exposes the *page* URL with
        // a frame spanning everything — that's provenance, not a selected link.
        let pageURL = collected.first { $0.role == "AXWebArea" }?.url

        // Ground-truth links: only real hyperlink elements (role AXLink). Drop
        // icon-sized links (e.g. HN's ▲ upvote arrow) so "First URL" surfaces a
        // real anchor, not a tiny control. Then order in reading order.
        let allLinks = collected.filter { $0.role == "AXLink" && $0.url != nil }
        let substantial = allLinks.filter { $0.frame.width >= 24 && $0.frame.height >= 10 }
        let links = (substantial.isEmpty ? allLinks : substantial).sorted {
            abs($0.frame.minY - $1.frame.minY) > 6
                ? $0.frame.minY < $1.frame.minY
                : $0.frame.minX < $1.frame.minX
        }
        let entities = links.map { element in
            DetectedEntity(
                type: .url, value: element.url!.absoluteString,
                sourceText: element.text ?? element.url!.absoluteString,
                boundingBox: element.frame, source: .ax)
        }
        return Result(text: text, elements: collected, entities: entities, pageURL: pageURL)
    }

    // MARK: - Tree walk

    private func walk(_ element: AXUIElement, rect: CGRect, depth: Int,
                      visited: inout Int, into collected: inout [AXElement]) {
        if depth > maxDepth || visited > maxElements { return }
        visited += 1

        let frame = frame(of: element)
        // Prune: an element with a real frame that doesn't intersect → skip subtree.
        if let frame, !frame.intersects(rect) { return }

        let kids = children(of: element)
        let link = url(of: element)
        let role = string(element, kAXRoleAttribute) ?? ""

        // Collect text from leaves and links (avoids container text duplicating children).
        if let frame, frame.intersects(rect), link != nil || kids.isEmpty {
            let text = bestText(of: element)
            if text != nil || link != nil {
                collected.append(AXElement(role: role, text: text, url: link, frame: frame))
            }
        }

        for child in kids {
            walk(child, rect: rect, depth: depth + 1, visited: &visited, into: &collected)
        }
    }

    // MARK: - Text assembly (reading order: top→bottom, left→right)

    private func assembleText(from elements: [AXElement]) -> String {
        let withText = elements.compactMap { e -> (CGRect, String)? in
            guard let t = e.text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty
            else { return nil }
            return (e.frame, t)
        }
        guard !withText.isEmpty else { return "" }

        let sorted = withText.sorted {
            abs($0.0.minY - $1.0.minY) > 6 ? $0.0.minY < $1.0.minY : $0.0.minX < $1.0.minX
        }
        var out = ""
        var prevY = sorted.first!.0.minY
        for (frame, text) in sorted {
            if out.isEmpty { out = text }
            else if abs(frame.minY - prevY) > 6 { out += "\n" + text }
            else { out += " " + text }
            prevY = frame.minY
        }
        return out
    }

    // MARK: - Chrome/Electron nudge

    /// Chromium gates full web a11y until an assistive tech is detected. Setting
    /// these attributes nudges the renderer to build the tree. Errors are ignored.
    private func nudgeWebAccessibility(_ app: AXUIElement) {
        for attr in ["AXManualAccessibility", "AXEnhancedUserInterface"] {
            AXUIElementSetAttributeValue(app, attr as CFString, kCFBooleanTrue)
        }
    }

    // MARK: - Attribute accessors

    private func frame(of element: AXUIElement) -> CGRect? {
        var posRef: AnyObject?
        var sizeRef: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success
        else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard let posRef, let sizeRef,
              AXValueGetValue(posRef as! AXValue, .cgPoint, &point),
              AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        else { return nil }
        return CGRect(origin: point, size: size)
    }

    private func children(of element: AXUIElement) -> [AXUIElement] {
        var ref: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &ref) == .success
        else { return [] }
        return (ref as? [AXUIElement]) ?? []
    }

    private func url(of element: AXUIElement) -> URL? {
        var ref: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXURLAttribute as CFString, &ref) == .success
        else { return nil }
        if let u = ref as? URL { return u }
        if let s = ref as? String { return URL(string: s) }
        return nil
    }

    private func bestText(of element: AXUIElement) -> String? {
        for attr in [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute] {
            if let s = string(element, attr), !s.isEmpty { return s }
        }
        return nil
    }

    private func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var ref: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success
        else { return nil }
        return ref as? String
    }
}
