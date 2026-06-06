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
        /// PID of the app that dominates the selection (provenance + intent).
        let ownerPID: pid_t?
        /// All apps that survived sliver-dropping (for diagnostics), dominant-first.
        let ownerPIDs: [pid_t]
    }

    private let maxDepth = 80
    private let maxElements = 6000
    private let messagingTimeout: Float = 0.2   // seconds per AX call

    /// `rect` is in CoreGraphics top-left screen coordinates (same space AX uses).
    ///
    /// We do NOT assume the active app owns the pixels. Instead we hit-test a grid
    /// of points across the rect against the system-wide AX element to discover the
    /// app(s) actually under the selection — so capturing a non-focused window, or
    /// a region spanning two apps side by side, harvests the right tree(s).
    /// `fallbackPID` is used only if hit-testing finds nothing (e.g. an app that
    /// doesn't respond to position queries).
    func harvest(rect: CGRect, fallbackPID: pid_t?) -> Result {
        guard AXIsProcessTrusted() else {
            return Result(text: "", elements: [], entities: [], pageURL: nil,
                          ownerPID: nil, ownerPIDs: [])
        }

        let owners = owningPIDs(in: rect, fallback: fallbackPID)
        var collected: [AXElement] = []
        for pid in owners.ordered {
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, messagingTimeout)
            nudgeWebAccessibility(app)
            var visited = 0
            walk(app, sourcePID: pid, rect: rect, depth: 0, visited: &visited, into: &collected)
        }
        let dominant = owners.dominant

        let text = assembleText(from: collected)

        // The page container (AXWebArea) exposes the *page* URL with a frame
        // spanning everything — provenance, not a selected link. Prefer the
        // dominant app's page.
        let pageURL = (collected.first { $0.role == "AXWebArea" && $0.sourcePID == dominant }
                       ?? collected.first { $0.role == "AXWebArea" })?.url

        // Ground-truth links: only real hyperlink elements (role AXLink). Drop
        // icon-sized links (e.g. HN's ▲ upvote arrow). Rank the dominant app's
        // links ahead of secondary apps' links, then reading order within each —
        // so "First URL" comes from the window that owns most of the selection.
        let allLinks = collected.filter { $0.role == "AXLink" && $0.url != nil }
        let substantial = allLinks.filter { $0.frame.width >= 24 && $0.frame.height >= 10 }
        let links = (substantial.isEmpty ? allLinks : substantial).sorted { a, b in
            let aDom = a.sourcePID == dominant, bDom = b.sourcePID == dominant
            if aDom != bDom { return aDom }
            return abs(a.frame.minY - b.frame.minY) > 6
                ? a.frame.minY < b.frame.minY
                : a.frame.minX < b.frame.minX
        }
        let entities = links.map { element in
            DetectedEntity(
                type: .url, value: element.url!.absoluteString,
                sourceText: element.text ?? element.url!.absoluteString,
                boundingBox: element.frame, source: .ax)
        }
        return Result(text: text, elements: collected, entities: entities,
                      pageURL: pageURL, ownerPID: dominant, ownerPIDs: owners.ordered)
    }

    // MARK: - Pixel-ownership discovery (coverage-weighted)

    private struct Owners { let ordered: [pid_t]; let dominant: pid_t? }

    /// Apps under the selection, weighted by how much of it they cover. Apps that
    /// own less than `sliverThreshold` of the resolved sample points are dropped
    /// as accidental edge clips. Survivors are ordered by coverage (dominant
    /// first), with the center sample breaking ties.
    private func owningPIDs(in rect: CGRect, fallback: pid_t?) -> Owners {
        let system = AXUIElementCreateSystemWide()
        let selfPID = ProcessInfo.processInfo.processIdentifier
        let sliverThreshold = 0.15

        var counts: [pid_t: Int] = [:]
        var centerPID: pid_t?
        var resolved = 0

        for (index, point) in samplePoints(in: rect).enumerated() {
            var element: AXUIElement?
            guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &element) == .success,
                  let element else { continue }
            var pid: pid_t = 0
            guard AXUIElementGetPid(element, &pid) == .success, pid != 0, pid != selfPID else { continue }
            counts[pid, default: 0] += 1
            resolved += 1
            if index == 0 { centerPID = pid }   // samplePoints[0] is the center
        }

        guard resolved > 0 else {
            if let fallback, fallback != selfPID { return Owners(ordered: [fallback], dominant: fallback) }
            return Owners(ordered: [], dominant: nil)
        }

        // Drop slivers (accidental edge clips); keep at least the top owner.
        var survivors = counts.filter { Double($0.value) / Double(resolved) >= sliverThreshold }.map(\.key)
        if survivors.isEmpty, let top = counts.max(by: { $0.value < $1.value })?.key { survivors = [top] }

        let ordered = survivors.sorted { a, b in
            if counts[a]! != counts[b]! { return counts[a]! > counts[b]! }
            if a == centerPID { return true }
            if b == centerPID { return false }
            return a < b
        }
        return Owners(ordered: ordered, dominant: ordered.first)
    }

    /// Center first, then a 3×3 grid inset into the rect.
    private func samplePoints(in rect: CGRect) -> [CGPoint] {
        guard rect.width.isFinite, rect.height.isFinite else { return [] }
        var points = [CGPoint(x: rect.midX, y: rect.midY)]
        for fx in [0.2, 0.5, 0.8] {
            for fy in [0.2, 0.5, 0.8] {
                points.append(CGPoint(x: rect.minX + rect.width * fx,
                                      y: rect.minY + rect.height * fy))
            }
        }
        return points
    }

    // MARK: - Tree walk

    private func walk(_ element: AXUIElement, sourcePID: pid_t, rect: CGRect, depth: Int,
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
                collected.append(AXElement(role: role, text: text, url: link,
                                           frame: frame, sourcePID: sourcePID))
            }
        }

        for child in kids {
            walk(child, sourcePID: sourcePID, rect: rect, depth: depth + 1,
                 visited: &visited, into: &collected)
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
