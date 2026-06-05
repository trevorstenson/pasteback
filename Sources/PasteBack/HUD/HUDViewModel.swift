import SwiftUI

/// Drives the chip strip: the ranked actions and which stateful (copy) action is
/// currently reflected on the clipboard.
final class HUDViewModel: ObservableObject {
    @Published var actions: [CaptureAction] = []
    @Published var selectedID: String?

    /// Fired after any chip tap (used to reset the auto-dismiss timer).
    var onTap: (() -> Void)?

    func update(actions: [CaptureAction], selectedID: String?) {
        self.actions = actions
        self.selectedID = selectedID
    }

    func tap(_ action: CaptureAction) {
        if action.isStateful { selectedID = action.id }
        action.perform()
        onTap?()
    }
}
