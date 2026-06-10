import SwiftUI

/// The floating HUD content: a one-line payload preview (what did the capture
/// get, from where) above the horizontal strip of action chips — and, when
/// expanded, the full inspector above both.
/// - One-shot actions (Open Link, Save Contact, …) and the currently-active copy
///   format are shown filled (accent).
/// - Other copy formats are shown in a subtle neutral fill.
/// Chips size to their full label (no clipping); the panel sizes to the strip.
struct ChipStripView: View {
    @ObservedObject var viewModel: HUDViewModel
    @State private var isHovering = false

    var body: some View {
        content
            .overlay(alignment: .topTrailing) {
                if isHovering { closeButton.offset(x: 5, y: -5) }
            }
            .padding(6)                 // room for the close button + drop shadow
            .onHover { isHovering = $0 }
    }

    /// Layout contract: the BOTTOM row (chips + provenance) is the panel's
    /// single source of width — every other row reports a zero/fixed ideal and
    /// stretches to match at render time. One pass, no measurement, no ragged
    /// right edge in either state.
    private var content: some View {
        VStack(alignment: .leading, spacing: 7) {
            if viewModel.isExpanded, let capture = viewModel.capture,
               let summary = viewModel.summary {
                InspectorView(capture: capture, summary: summary, actions: viewModel.actions)
                Divider()
            }
            if let summary = viewModel.summary {
                PreviewRow(summary: summary, isExpanded: viewModel.isExpanded) {
                    viewModel.toggleExpanded()
                }
                .frame(minWidth: 0, idealWidth: 0, maxWidth: .infinity, alignment: .leading)
            }
            bottomRow
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    /// Chips on the left, source badge + app name right-aligned on the same
    /// line. A minimum width keeps the preview line legible above few chips.
    private var bottomRow: some View {
        HStack(spacing: 6) {
            chipRow
            Spacer(minLength: 12)
            if let summary = viewModel.summary {
                Button {
                    viewModel.toggleExpanded()
                } label: {
                    HStack(spacing: 6) {
                        SourceBadgeView(badge: summary.sourceBadge)
                        if let app = summary.appName {
                            Text("from \(app)")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .fixedSize()
                .help(viewModel.isExpanded ? "Collapse details (Space)" : "Show details (Space)")
            }
        }
        .frame(minWidth: 380, alignment: .leading)
    }

    private var chipRow: some View {
        HStack(spacing: 6) {
            ForEach(Array(viewModel.actions.enumerated()), id: \.element.id) { index, action in
                ChipButton(
                    shortcut: index < 9 ? "\(index + 1)" : nil,
                    action: action,
                    isSelected: action.isStateful && action.id == viewModel.selectedID,
                    isFocused: index == viewModel.focusedIndex
                ) {
                    viewModel.focusedIndex = index
                    viewModel.tap(action)
                }
            }
        }
        .fixedSize()                    // never compress/clip the chips
    }

    private var closeButton: some View {
        Button { viewModel.dismiss() } label: {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .frame(width: 18, height: 18)
                .foregroundStyle(.secondary)
                .background(.regularMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help("Close")
    }
}

/// One-line summary above the chips: preview text on the left, counts and a
/// chevron on the right. Clicking it (or Space) toggles the inspector. The row
/// reports a zero ideal width and fills whatever width the chip row sets.
private struct PreviewRow: View {
    let summary: CaptureSummary
    let isExpanded: Bool
    let onToggle: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 8) {
                Text(verbatim: summary.isImageOnly ? summary.previewText : "“\(summary.previewText)”")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                if !summary.metadataText.isEmpty {
                    Text(summary.metadataText)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .fixedSize()
                }
                Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(hovering ? .primary : .secondary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(hovering ? AnyShapeStyle(Color.primary.opacity(0.07)) : AnyShapeStyle(Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(isExpanded ? "Collapse details (Space)" : "Show details (Space)")
    }
}

private struct ChipButton: View {
    let shortcut: String?
    let action: CaptureAction
    let isSelected: Bool
    let isFocused: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 5) {
                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 10, weight: .bold))
                        .frame(minWidth: 14, minHeight: 14)
                        .foregroundStyle(isFilled ? Color.white.opacity(0.9) : Color.secondary)
                        .background(
                            Circle().fill(isFilled ? Color.white.opacity(0.22) : Color.primary.opacity(0.08))
                        )
                }
                Image(systemName: action.symbol)
                    .font(.system(size: 12, weight: .semibold))
                Text(action.title)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)
            }
            .fixedSize(horizontal: true, vertical: false)   // full label, no clipping
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .foregroundStyle(isFilled ? Color.white : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isFilled ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(isFocused ? Color.accentColor.opacity(0.9) : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    /// Accent-filled when it's an action to perform, or the active copy format.
    private var isFilled: Bool { !action.isStateful || isSelected }
}
