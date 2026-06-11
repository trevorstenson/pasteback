import AppKit
import SwiftUI

/// The expanded HUD state: everything a capture got, on demand. Read-and-act
/// only (copy buttons, Open buttons) — the panel is non-activating, so buttons
/// work without key status while text selection would not.
struct InspectorView: View {
    static let minWidth: CGFloat = 480

    let capture: CapturedScreenshot
    let summary: CaptureSummary
    let actions: [CaptureAction]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if !capture.canonicalText.isEmpty { textSection }
                    if !links.isEmpty { linksSection }
                    if !entityGroups.isEmpty { entitiesSection }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
                .padding(.bottom, 8)
                .padding(.horizontal, 2)
            }
            Divider()
            provenanceFooter
        }
        // Pinned ideal width: the chip row below decides the panel's width and
        // the inspector stretches to match (never narrower than minWidth).
        .frame(minWidth: Self.minWidth, idealWidth: Self.minWidth, maxWidth: .infinity,
               minHeight: 360, idealHeight: 360, maxHeight: 360)
    }

    // MARK: - Derived content

    /// All link entities, AX-seeded (ground truth) first.
    private var links: [DetectedEntity] {
        let all = capture.entities.filter { $0.type == .url }
        return all.filter { $0.source == .ax } + all.filter { $0.source != .ax }
    }

    private var nonLinkEntities: [DetectedEntity] {
        capture.entities.filter { $0.type != .url }
    }

    /// Non-link entities grouped by kind, in first-appearance order.
    private var entityGroups: [(label: String, items: [DetectedEntity])] {
        var order: [String] = []
        var groups: [String: [DetectedEntity]] = [:]
        for entity in nonLinkEntities {
            let label = Self.kindLabel(for: entity.type)
            if groups[label] == nil { order.append(label) }
            groups[label, default: []].append(entity)
        }
        return order.map { ($0, groups[$0]!) }
    }

    private var isCodeLike: Bool {
        capture.entities.contains {
            if case .codeBlock = $0.type { return true }
            if case .stackTrace = $0.type { return true }
            return false
        }
    }

    // MARK: - Sections

    private var textSection: some View {
        SectionCard(title: "Text", count: summary.lineCount,
                    copyValue: capture.canonicalText) {
            Text(verbatim: capture.canonicalText)
                .font(isCodeLike ? .system(size: 11, design: .monospaced) : .system(size: 11.5))
                .foregroundStyle(.primary)
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var linksSection: some View {
        SectionCard(title: "Links", count: links.count,
                    copyValue: links.map(\.value).joined(separator: "\n")) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(links.enumerated()), id: \.offset) { index, link in
                    LinkRow(link: link)
                    if index < links.count - 1 {
                        Divider().opacity(0.4)
                    }
                }
            }
        }
    }

    private var entitiesSection: some View {
        SectionCard(title: "Entities", count: nonLinkEntities.count, copyValue: nil) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(entityGroups, id: \.label) { group in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            Text(group.label)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                            if let action = groupAction(for: group.items[0].type) {
                                ActionPill(action: action)
                            }
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), alignment: .leading)],
                                  alignment: .leading, spacing: 5) {
                            ForEach(Array(group.items.enumerated()), id: \.offset) { _, entity in
                                EntityChip(displayText: Self.displayValue(for: entity),
                                           copyValue: entity.value)
                            }
                        }
                    }
                }
            }
        }
    }

    private var provenanceFooter: some View {
        HStack(spacing: 9) {
            if let icon = appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 24, height: 24)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(summary.appName ?? "Unknown app")
                    .font(.system(size: 11.5, weight: .semibold))
                if let url = capture.source.url {
                    Text(verbatim: url.absoluteString)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 12)
            HStack(spacing: 8) {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(capture.timestamp, style: .time)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("\(capture.image.width) × \(capture.image.height)")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                }
                SourceBadgeView(badge: summary.sourceBadge, helpText: summary.sourceReason)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 9)
        .padding(.bottom, 2)
    }

    // MARK: - Helpers

    /// The intent action already resolved for this capture, when the group's
    /// entity kind has one (date → Add to Calendar, address → Open in Maps, …).
    private func groupAction(for type: EntityType) -> CaptureAction? {
        let id: String?
        switch type {
        case .date:     id = "add-calendar"
        case .address:  id = "open-maps"
        case .filePath: id = "reveal"
        case .barcode:  id = actions.contains { $0.id == "qr-open" } ? "qr-open" : "qr-copy"
        default:        id = nil
        }
        guard let id else { return nil }
        return actions.first { $0.id == id }
    }

    private var appIcon: NSImage? {
        if let pid = capture.source.pid,
           let app = NSRunningApplication(processIdentifier: pid),
           let icon = app.icon {
            return icon
        }
        if let bundleID = capture.source.bundleIdentifier,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return nil
    }

    private static let isoParser = ISO8601DateFormatter()

    /// Human-facing form of an entity (dates render localized); copying still
    /// uses the canonical value.
    static func displayValue(for entity: DetectedEntity) -> String {
        if case .date = entity.type, let date = isoParser.date(from: entity.value) {
            return date.formatted(date: .abbreviated, time: .shortened)
        }
        return entity.value
    }

    static func kindLabel(for type: EntityType) -> String {
        switch type {
        case .url:                    return "Links"
        case .email:                  return "Emails"
        case .phone:                  return "Phone numbers"
        case .address:                return "Addresses"
        case .date:                   return "Dates"
        case .ticketID(let system):   return "\(system.capitalized) tickets"
        case .commitHash:             return "Commits"
        case .filePath:               return "File paths"
        case .hexColor:               return "Colors"
        case .codeBlock:              return "Code"
        case .stackTrace:             return "Stack traces"
        case .barcode:                return "QR / Barcodes"
        }
    }
}

/// Pill showing where a capture's content came from (the moat made visible).
struct SourceBadgeView: View {
    let badge: CaptureSummary.SourceBadge
    var helpText: String? = nil

    var body: some View {
        Text(badge.rawValue)
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(badge == .ocr ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.white))
            .background(
                Capsule().fill(badge == .ocr
                    ? AnyShapeStyle(.quaternary)
                    : AnyShapeStyle(Color.accentColor.opacity(0.85)))
            )
            .help(helpText ?? (badge == .ax ? "Ground truth from the Accessibility tree"
                  : badge == .mixed ? "OCR text enriched with Accessibility entities"
                  : "Recognized from pixels"))
    }
}

/// Rounded container giving each inspector section a card-like grouping with a
/// consistent header row (title · count · copy-all).
private struct SectionCard<Content: View>: View {
    let title: String
    let count: Int?
    let copyValue: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Text(title.uppercased())
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(.secondary)
                    .kerning(0.8)
                if let count {
                    Text("\(count)")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
                if let copyValue, !copyValue.isEmpty {
                    CopyButton(value: copyValue)
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

/// `visible text → URL` with Open + Copy buttons; the row highlights on hover.
private struct LinkRow: View {
    let link: DetectedEntity
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "link")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.tertiary)
                .frame(width: 12)
            VStack(alignment: .leading, spacing: 1) {
                if !link.sourceText.isEmpty && link.sourceText != link.value {
                    Text(verbatim: link.sourceText)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Text(verbatim: link.value)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            if let url = URL(string: link.value) {
                IconButton(symbol: "arrow.up.forward.app", help: "Open") {
                    NSWorkspace.shared.open(url)
                }
            }
            CopyButton(value: link.value)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(hovering ? AnyShapeStyle(Color.primary.opacity(0.07)) : AnyShapeStyle(Color.clear))
        )
        .onHover { hovering = $0 }
    }
}

/// Tinted capsule for an intent action inside an entity group
/// (Add to Calendar, Open in Maps, …).
private struct ActionPill: View {
    let action: CaptureAction
    @State private var hovering = false

    var body: some View {
        Button {
            action.perform()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: action.symbol)
                    .font(.system(size: 9, weight: .medium))
                Text(action.title)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(Capsule().fill(Color.accentColor.opacity(hovering ? 0.25 : 0.14)))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Tap-to-copy chip for one detected entity.
private struct EntityChip: View {
    let displayText: String
    let copyValue: String
    @State private var copied = false
    @State private var hovering = false

    var body: some View {
        Button {
            copyToPasteboard(copyValue)
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
        } label: {
            HStack(spacing: 5) {
                Text(verbatim: displayText)
                    .font(.system(size: 10.5))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 8))
                    .foregroundStyle(copied ? AnyShapeStyle(Color.green) : AnyShapeStyle(.tertiary))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(hovering ? 0.12 : 0.07))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Copy \(copyValue)")
    }
}

/// Small circular icon button with a hover highlight.
private struct IconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(hovering ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .frame(width: 21, height: 21)
                .background(
                    Circle().fill(hovering ? AnyShapeStyle(Color.primary.opacity(0.1))
                                           : AnyShapeStyle(Color.clear))
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// Small copy button with a transient checkmark confirmation.
private struct CopyButton: View {
    let value: String
    @State private var copied = false
    @State private var hovering = false

    var body: some View {
        Button {
            copyToPasteboard(value)
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(copied ? AnyShapeStyle(Color.green)
                                 : hovering ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .frame(width: 21, height: 21)
                .background(
                    Circle().fill(hovering ? AnyShapeStyle(Color.primary.opacity(0.1))
                                           : AnyShapeStyle(Color.clear))
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Copy")
    }
}

private func copyToPasteboard(_ string: String) {
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setString(string, forType: .string)
}
