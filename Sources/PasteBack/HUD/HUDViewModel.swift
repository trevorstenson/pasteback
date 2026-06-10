import SwiftUI

/// Drives the chip strip: the ranked actions and which stateful (copy) action is
/// currently reflected on the clipboard.
final class HUDViewModel: ObservableObject {
    @Published var actions: [CaptureAction] = []
    @Published var selectedID: String?
    @Published var focusedIndex: Int = 0
    @Published var capture: CapturedScreenshot?
    @Published var summary: CaptureSummary?
    @Published var isExpanded = false

    /// Fired after any chip tap (used to reset the auto-dismiss timer).
    var onTap: (() -> Void)?
    /// Fired when the user explicitly closes the HUD.
    var onDismiss: (() -> Void)?
    /// Fired after the inspector expands/collapses, so the panel controller can
    /// re-attach a fresh hosting view, resize, and pause/resume the timer.
    var onExpandedChange: ((Bool) -> Void)?

    func update(capture: CapturedScreenshot?, actions: [CaptureAction], selectedID: String?) {
        self.capture = capture
        self.summary = capture.map(CaptureSummary.init)
        self.isExpanded = false
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

    func toggleExpanded() {
        guard capture != nil else { return }
        isExpanded.toggle()
        onExpandedChange?(isExpanded)
    }

    /// Collapses the inspector if open. Returns true when it did collapse.
    func collapseIfExpanded() -> Bool {
        guard isExpanded else { return false }
        isExpanded = false
        onExpandedChange?(false)
        return true
    }

    func dismiss() {
        onDismiss?()
    }
}
