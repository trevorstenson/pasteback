import AppKit
import ImageIO

/// Output of a capture: pixels plus the context needed to de-flatten — the
/// selected rect (CG top-left coords) and the app that owned the region.
struct CaptureResult {
    let image: CGImage
    /// nil in shell-out mode (we don't own the selection rect there → OCR-only).
    let rect: CGRect?
    let source: CaptureSource
}

/// Captures a user-selected screen region.
/// - `.native`: in-app overlay + `CGWindowListCreateImage`; gives us the rect +
///   the owning app, which AX harvest (M1) needs. Requires Screen Recording.
/// - `.shellOut`: system `screencapture -i`; no rect, OCR-only fallback.
///
/// `captureRegion` invokes `completion` on the main thread.
final class CaptureService {

    enum CaptureError: Error { case cancelled, decodeFailed, captureFailed }

    private let overlay = RegionOverlayController()

    func captureRegion(
        mode: SettingsStore.CaptureMode,
        selectionStyle: SettingsStore.RegionSelectionStyle,
        completion: @escaping (Result<CaptureResult, Error>) -> Void
    ) {
        switch mode {
        case .native:   captureViaOverlay(selectionStyle: selectionStyle, completion: completion)
        case .shellOut: captureViaShellOut(completion: completion)
        }
    }

    // MARK: - Native overlay

    private func captureViaOverlay(
        selectionStyle: SettingsStore.RegionSelectionStyle,
        completion: @escaping (Result<CaptureResult, Error>) -> Void
    ) {
        // Record the app behind the overlay BEFORE we steal focus.
        let source = Self.frontmostSource()

        overlay.begin(selectionStyle: selectionStyle) { cocoaRect in
            guard let cocoaRect else {
                completion(.failure(CaptureError.cancelled)); return
            }
            let cgRect = ScreenGeometry.cocoaToCG(cocoaRect)
            // Capture after a tick so the dismissed overlay isn't composited in.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                guard let image = CGWindowListCreateImage(
                    cgRect, .optionOnScreenOnly, kCGNullWindowID, .bestResolution
                ) else {
                    completion(.failure(CaptureError.captureFailed)); return
                }
                completion(.success(CaptureResult(image: image, rect: cgRect, source: source)))
            }
        }
    }

    // MARK: - Shell-out

    private func captureViaShellOut(completion: @escaping (Result<CaptureResult, Error>) -> Void) {
        let source = Self.frontmostSource()
        DispatchQueue.global(qos: .userInitiated).async {
            let tmpURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("pasteback-\(UUID().uuidString).png")
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = ["-i", "-x", tmpURL.path]

            let result: Result<CaptureResult, Error>
            do {
                try process.run(); process.waitUntilExit()
                defer { try? FileManager.default.removeItem(at: tmpURL) }
                if !FileManager.default.fileExists(atPath: tmpURL.path) {
                    result = .failure(CaptureError.cancelled)
                } else if let src = CGImageSourceCreateWithURL(tmpURL as CFURL, nil),
                          let image = CGImageSourceCreateImageAtIndex(src, 0, nil) {
                    result = .success(CaptureResult(image: image, rect: nil, source: source))
                } else {
                    result = .failure(CaptureError.decodeFailed)
                }
            } catch {
                result = .failure(error)
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    // MARK: - Source app

    static func frontmostSource() -> CaptureSource {
        // Target the app behind us, never Paste-Back itself.
        let app = FrontmostAppTracker.shared.targetApp()
        return CaptureSource(
            appName: app?.localizedName,
            bundleIdentifier: app?.bundleIdentifier,
            pid: app?.processIdentifier,
            url: nil   // browser/tab URL is an M1+ enhancer
        )
    }
}
