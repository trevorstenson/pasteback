import AppKit

/// Local, capped, captures-only history. Records ONLY our captures — never the
/// general pasteboard (per project2.md §4 this must not become a clipboard
/// manager). Layout on disk:
///
///   <base>/<uuid>/meta.json     — CaptureRecord
///   <base>/<uuid>/capture.png   — full-resolution pixels
///   <base>/<uuid>/thumb.png     — ~320px list thumbnail
///
/// Writes run on a private utility queue so the capture path never blocks on
/// disk I/O. Oldest records are evicted past the count/size caps. The directory
/// is excluded from backups; a settings toggle turns the store into a no-op.
final class CaptureHistoryStore {

    var maxRecords = 20
    var maxBytes = 100 * 1024 * 1024
    /// History opt-out: when false, `append` is a no-op (existing records are
    /// kept until the user clears them).
    var isEnabled: () -> Bool

    let baseURL: URL

    private let queue = DispatchQueue(label: "com.pasteback.history", qos: .utility)
    private let fileManager = FileManager.default

    init(baseURL: URL? = nil,
         isEnabled: @escaping () -> Bool = { SettingsStore.shared.keepHistory }) {
        self.baseURL = baseURL ?? Self.defaultBaseURL()
        self.isEnabled = isEnabled
    }

    static func defaultBaseURL() -> URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("PasteBack/History", isDirectory: true)
    }

    // MARK: - Writing

    func append(_ capture: CapturedScreenshot) {
        guard isEnabled() else { return }
        queue.async { [self] in
            do {
                try writeRecord(for: capture)
                evict()
            } catch {
                Log.write("history append failed: \(error)")
            }
        }
    }

    /// Drains the write queue (used by --selftest for determinism).
    func waitForPendingWrites() {
        queue.sync {}
    }

    func delete(id: UUID) {
        queue.sync { try? fileManager.removeItem(at: directoryURL(for: id)) }
    }

    func clear() {
        queue.sync { try? fileManager.removeItem(at: baseURL) }
        Log.write("history cleared")
    }

    // MARK: - Reading

    /// All records, newest first.
    func records() -> [CaptureRecord] {
        queue.sync { loadRecords().sorted { $0.timestamp > $1.timestamp } }
    }

    func thumbnailURL(for id: UUID) -> URL {
        directoryURL(for: id).appendingPathComponent("thumb.png")
    }

    func imageURL(for id: UUID) -> URL {
        directoryURL(for: id).appendingPathComponent("capture.png")
    }

    /// Record → live capture. Re-hydrated captures flow through the existing
    /// ActionResolver / PasteboardWriter unchanged (`captureRect`/`axElements`
    /// are live-only and stay empty).
    func rehydrate(_ record: CaptureRecord) -> CapturedScreenshot? {
        guard let image = Self.loadPNG(at: imageURL(for: record.id)) else { return nil }
        return CapturedScreenshot(
            id: record.id,
            timestamp: record.timestamp,
            image: image,
            captureRect: nil,
            source: CaptureSource(appName: record.source.appName,
                                  bundleIdentifier: record.source.bundleIdentifier,
                                  pid: nil,
                                  url: record.source.url.flatMap(URL.init(string:))),
            ocrText: record.ocrText,
            ocrLines: [],
            axText: record.axText,
            axElements: [],
            entities: record.detectedEntities(),
            tables: record.detectedTables())
    }

    /// Representation availability for a record without decoding its full PNG
    /// (the list UI builds "Re-copy as…" menus from this).
    func availableRepresentations(for record: CaptureRecord) -> [Representation] {
        let lightweight = CapturedScreenshot(
            id: record.id,
            timestamp: record.timestamp,
            image: Self.placeholderImage,
            source: CaptureSource(appName: record.source.appName,
                                  bundleIdentifier: record.source.bundleIdentifier,
                                  pid: nil,
                                  url: record.source.url.flatMap(URL.init(string:))),
            ocrText: record.ocrText,
            axText: record.axText,
            entities: record.detectedEntities(),
            tables: record.detectedTables())
        return RepresentationBuilder().availableRepresentations(for: lightweight)
    }

    // MARK: - Internals (on queue)

    private func writeRecord(for capture: CapturedScreenshot) throws {
        let dir = directoryURL(for: capture.id)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        excludeFromBackup()

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let meta = try encoder.encode(CaptureRecord(capture: capture))
        try meta.write(to: dir.appendingPathComponent("meta.json"), options: .atomic)

        if let png = Self.pngData(from: capture.image) {
            try png.write(to: dir.appendingPathComponent("capture.png"), options: .atomic)
        }
        if let thumb = Self.thumbnail(of: capture.image),
           let thumbPNG = Self.pngData(from: thumb) {
            try thumbPNG.write(to: dir.appendingPathComponent("thumb.png"), options: .atomic)
        }
        Log.write("history appended: id=\(capture.id) app=\(capture.source.appName ?? "?")")
    }

    private func evict() {
        var entries = loadRecords()
            .sorted { $0.timestamp > $1.timestamp }   // newest first
            .map { (record: $0, dir: directoryURL(for: $0.id)) }

        while entries.count > maxRecords, let oldest = entries.popLast() {
            try? fileManager.removeItem(at: oldest.dir)
            Log.write("history evicted (count cap): id=\(oldest.record.id)")
        }

        var totalBytes = entries.reduce(0) { $0 + directorySize(at: $1.dir) }
        while totalBytes > maxBytes, entries.count > 1, let oldest = entries.popLast() {
            totalBytes -= directorySize(at: oldest.dir)
            try? fileManager.removeItem(at: oldest.dir)
            Log.write("history evicted (size cap): id=\(oldest.record.id)")
        }
    }

    private func loadRecords() -> [CaptureRecord] {
        guard let subdirs = try? fileManager.contentsOfDirectory(
            at: baseURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
        else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return subdirs.compactMap { dir in
            guard let data = try? Data(contentsOf: dir.appendingPathComponent("meta.json"))
            else { return nil }
            return try? decoder.decode(CaptureRecord.self, from: data)
        }
    }

    private func directoryURL(for id: UUID) -> URL {
        baseURL.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    private func directorySize(at url: URL) -> Int {
        guard let files = try? fileManager.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.fileSizeKey])
        else { return 0 }
        return files.reduce(0) {
            $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    private func excludeFromBackup() {
        var url = baseURL
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    // MARK: - Image helpers

    private static func pngData(from image: CGImage) -> Data? {
        NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    private static func loadPNG(at url: URL) -> CGImage? {
        guard let provider = CGDataProvider(url: url as CFURL) else { return nil }
        return CGImage(pngDataProviderSource: provider, decode: nil,
                       shouldInterpolate: true, intent: .defaultIntent)
    }

    private static func thumbnail(of image: CGImage, maxDimension: CGFloat = 320) -> CGImage? {
        let width = CGFloat(image.width), height = CGFloat(image.height)
        let scale = min(1, maxDimension / max(width, height, 1))
        guard scale < 1 else { return image }
        let thumbWidth = max(1, Int(width * scale))
        let thumbHeight = max(1, Int(height * scale))
        guard let context = CGContext(
            data: nil, width: thumbWidth, height: thumbHeight,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: thumbWidth, height: thumbHeight))
        return context.makeImage()
    }

    /// 1×1 stand-in so representation availability can be computed from a
    /// record without decoding its real PNG.
    private static let placeholderImage: CGImage = {
        let context = CGContext(
            data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return context.makeImage()!
    }()
}
