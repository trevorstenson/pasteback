import SwiftUI

/// Horizontal strip of action chips shown in the floating HUD.
/// - One-shot actions (Open Link, Save Contact, …) and the currently-active copy
///   format are shown filled (accent).
/// - Other copy formats are shown in a subtle neutral fill.
/// Chips size to their full label (no clipping); the panel sizes to the strip.
struct ChipStripView: View {
    @ObservedObject var viewModel: HUDViewModel
    @State private var isHovering = false

    var body: some View {
        chipBar
            .overlay(alignment: .topTrailing) {
                if isHovering { closeButton.offset(x: 5, y: -5) }
            }
            .padding(6)                 // room for the close button + drop shadow
            .onHover { isHovering = $0 }
    }

    private var chipBar: some View {
        HStack(spacing: 6) {
            ForEach(viewModel.actions) { action in
                ChipButton(
                    action: action,
                    isSelected: action.isStateful && action.id == viewModel.selectedID
                ) {
                    viewModel.tap(action)
                }
            }
        }
        .fixedSize()                    // never compress/clip the chips
        .padding(7)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
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

private struct ChipButton: View {
    let action: CaptureAction
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 5) {
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
        }
        .buttonStyle(.plain)
    }

    /// Accent-filled when it's an action to perform, or the active copy format.
    private var isFilled: Bool { !action.isStateful || isSelected }
}
