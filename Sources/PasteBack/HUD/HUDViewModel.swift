import SwiftUI

/// Drives the chip strip: the ranked actions and which stateful (copy) action is
/// currently reflected on the clipboard.
final class HUDViewModel: ObservableObject {
    @Published var actions: [CaptureAction] = []
    @Published var selectedID: String?
    @Published var focusedIndex: Int = 0

    /// Fired after any chip tap (used to reset the auto-dismiss timer).
    var onTap: (() -> Void)?
    /// Fired when the user explicitly closes the HUD.
    var onDismiss: (() -> Void)?

    func update(actions: [CaptureAction], selectedID: String?) {
        self.actions = actions
        self.selectedID = selectedID
        if let selectedID, let idx = actions.firstIndex(where: { $0.id == selectedID }) {
            focusedIndex = idx
        } else {
            focusedIndex = 0
        }
    }

    func tap(_ action: CaptureAction) {
        if action.isStateful { selectedID = action.id }
        action.perform()
        onTap?()
    }

    func triggerFocused() {
        guard actions.indices.contains(focusedIndex) else { return }
        tap(actions[focusedIndex])
    }

    func trigger(index: Int) {
        guard actions.indices.contains(index) else { return }
        focusedIndex = index
        tap(actions[index])
    }

    func moveFocus(by delta: Int) {
        guard !actions.isEmpty else { return }
        focusedIndex = (focusedIndex + delta + actions.count) % actions.count
        let action = actions[focusedIndex]
        if action.isStateful {
            selectedID = action.id
            action.perform()
        }
        onTap?()
    }

    func dismiss() {
        onDismiss?()
    }
}
