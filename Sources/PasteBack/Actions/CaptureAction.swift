import Foundation

/// A chip in the HUD. Either a *stateful* copy action (sets the clipboard's
/// primary representation, stays "selected") or a one-shot side-effecting action
/// (open a link, reveal a file) that performs and doesn't hold selection.
struct CaptureAction: Identifiable {
    let id: String
    let title: String
    let symbol: String
    /// Copy/representation actions are stateful (highlight = current clipboard).
    let isStateful: Bool
    let perform: () -> Void
}
