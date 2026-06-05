import SwiftUI

/// Onboarding for the two permissions, with live status that updates as the user
/// grants them in System Settings. Both degrade gracefully if declined.
struct PermissionsView: View {
    @State private var screenRecording = PermissionService.hasScreenRecording()
    @State private var accessibility = PermissionService.hasAccessibility()
    let onDone: () -> Void

    private let poll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Paste-Back permissions").font(.title2.bold())

            row(title: "Screen Recording",
                granted: screenRecording,
                why: "Capture the region you select with the in-app overlay.",
                open: PermissionService.openScreenRecordingSettings)

            row(title: "Accessibility",
                granted: accessibility,
                why: "Recover real links, exact text, and structure from what you "
                   + "select — instead of guessing from pixels. Without it, Paste-Back "
                   + "still works using on-device OCR.",
                open: PermissionService.openAccessibilitySettings)

            HStack {
                Spacer()
                Button("Done") { onDone() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
        .onReceive(poll) { _ in
            screenRecording = PermissionService.hasScreenRecording()
            accessibility = PermissionService.hasAccessibility()
        }
    }

    @ViewBuilder
    private func row(title: String, granted: Bool, why: String, open: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: granted ? "checkmark.seal.fill" : "lock.shield")
                .font(.headline)
                .foregroundStyle(granted ? .green : .primary)
            Text(why).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !granted {
                Button("Open System Settings…", action: open)
            }
        }
    }
}
