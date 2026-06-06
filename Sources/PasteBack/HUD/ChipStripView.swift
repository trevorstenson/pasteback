import SwiftUI

/// Horizontal strip of action chips shown in the floating HUD. Stateful (copy)
/// chips highlight when they're the current clipboard format; one-shot chips
/// (Open Link, Reveal) just perform on tap.
struct ChipStripView: View {
    @ObservedObject var viewModel: HUDViewModel
    @State private var isHovering = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
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
            .padding(8)

            if isHovering {
                Button {
                    viewModel.dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 18, height: 18)
                        .foregroundStyle(.secondary)
                        .background(.regularMaterial, in: Circle())
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("Close")
                .offset(x: 7, y: -7)
            }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .onHover { isHovering = $0 }
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
                    .font(.system(size: 12, weight: .medium))
                Text(action.title)
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(foreground)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(background)
            )
        }
        .buttonStyle(.plain)
    }

    private var foreground: Color {
        if isSelected { return .white }
        return action.isStateful ? .primary : .white
    }

    private var background: Color {
        if isSelected { return .accentColor }
        // One-shot intent actions get a subtle accent tint to read as "do this".
        return action.isStateful ? Color.secondary.opacity(0.15) : Color.accentColor.opacity(0.55)
    }
}
