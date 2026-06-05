import Foundation

/// Minimal append-to-file logger for debugging (NSLog from an ad-hoc/dev GUI app
/// is hard to surface). Writes to /tmp/pasteback.log.
enum Log {
    private static let url = URL(fileURLWithPath: "/tmp/pasteback.log")

    static func write(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile(); handle.write(data); try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }
}
