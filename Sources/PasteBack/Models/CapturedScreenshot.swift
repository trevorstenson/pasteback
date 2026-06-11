import Foundation
import CoreGraphics

/// A line of text recognized by Vision, with its normalized bounding box.
struct OCRLine {
    let text: String
    /// Vision-normalized coordinates (0–1), origin bottom-left.
    let boundingBox: CGRect
    /// Per-token geometry from the same Vision observation. Empty for older
    /// fixtures / OCR providers that only expose line boxes.
    let tokens: [OCRToken]

    init(text: String, boundingBox: CGRect, tokens: [OCRToken] = []) {
        self.text = text
        self.boundingBox = boundingBox
        self.tokens = tokens
    }
}

/// A word/token recognized by Vision, with its normalized bounding box.
struct OCRToken: Equatable {
    let text: String
    /// Vision-normalized coordinates (0–1), origin bottom-left.
    let boundingBox: CGRect
}

/// An element harvested from the Accessibility tree under the capture region.
/// Populated in Milestone 1; empty until then.
struct AXElement {
    let role: String
    let text: String?
    let url: URL?
    /// Screen frame in CoreGraphics top-left coordinates.
    let frame: CGRect
    /// PID of the app this element came from — lets us attribute/rank by app
    /// when a selection spans more than one window.
    let sourcePID: pid_t
}

enum EntityType: Equatable {
    case url
    case email
    case phone
    case address
    case date
    case ticketID(system: String)   // "JIRA", "LINEAR", "GITHUB"
    case commitHash
    case filePath
    case hexColor
    case codeBlock(language: String?)
    case stackTrace
    case barcode(symbology: String?)   // QR / barcode payload decoded via Vision
}

/// Where an entity's value came from — AX is ground truth and wins over OCR.
enum EntitySource {
    case ax
    case ocr
}

/// A tabular region recovered from a capture: rectangular rows, an optional
/// header, and the source rung (AX ground truth vs OCR geometry). Produced by
/// `TableRecognizer` (geometry rungs) or `AXHarvester` (structural rung).
struct TableData: Equatable {
    /// Column headers, or `nil` when no header row is distinguishable.
    let headers: [String]?
    /// Rectangular rows; short rows are padded with `""` so every row has the
    /// same column count.
    let rows: [[String]]
    let source: EntitySource

    var columnCount: Int {
        max(headers?.count ?? 0, rows.map(\.count).max() ?? 0)
    }
    var rowCount: Int { rows.count }
}

/// What happened when PasteBack tried to enrich a capture via Accessibility.
/// This is deliberately small and user-facing: OCR fallback should explain why.
enum AXOutcome: Equatable {
    case notAttempted
    case harvested(elementCount: Int, retried: Bool)
    case noPermission
    case skipped(reason: String)
    case emptyTree(retried: Bool)

    var logValue: String {
        switch self {
        case .notAttempted:
            return "notAttempted"
        case .harvested(let elementCount, let retried):
            return "harvested(\(elementCount),retry=\(retried ? 1 : 0))"
        case .noPermission:
            return "noPermission"
        case .skipped(let reason):
            return "skipped(\(reason))"
        case .emptyTree(let retried):
            return "emptyTree(retry=\(retried ? 1 : 0))"
        }
    }
}

struct DetectedEntity {
    let type: EntityType
    /// Canonicalized form (e.g. URL with scheme).
    let value: String
    /// Exactly what the source saw.
    let sourceText: String
    let boundingBox: CGRect?
    let source: EntitySource

    init(
        type: EntityType,
        value: String,
        sourceText: String,
        boundingBox: CGRect? = nil,
        source: EntitySource = .ocr
    ) {
        self.type = type
        self.value = value
        self.sourceText = sourceText
        self.boundingBox = boundingBox
        self.source = source
    }
}

/// Lightweight provenance about where a capture came from (seeds M4 sharing).
struct CaptureSource {
    let appName: String?
    let bundleIdentifier: String?
    let pid: pid_t?
    /// Frontmost document/tab URL when known (browsers, etc.).
    let url: URL?
}

/// The result of one capture: pixels + OCR (floor) + AX (enrichment) + entities.
struct CapturedScreenshot {
    let id: UUID
    let timestamp: Date
    let image: CGImage
    /// Captured region in CoreGraphics top-left screen coordinates (nil in
    /// shell-out mode, where we don't own the selection rect).
    let captureRect: CGRect?
    let source: CaptureSource

    // OCR floor.
    let ocrText: String
    let ocrLines: [OCRLine]

    // AX enrichment (empty until M1).
    let axText: String
    let axElements: [AXElement]
    let axOutcome: AXOutcome

    let entities: [DetectedEntity]

    /// Tables recovered from the selection (highest-fidelity rung that produced
    /// a confident result). Default empty — additive, nothing else depends on it.
    let tables: [TableData]

    /// The canonical text for representations: AX text when it plausibly matches
    /// the selected region, else OCR. Some apps expose one giant AX leaf for an
    /// entire scrollback/document even when the user selected a tiny rect; using
    /// that would make the capture feel unrelated to the lasso.
    var canonicalText: String {
        Self.canonicalText(ocrText: ocrText, axText: axText)
    }

    static func canonicalText(ocrText: String, axText: String) -> String {
        guard !axText.isEmpty else { return ocrText }
        guard !ocrText.isEmpty else { return axText }
        if axText.count > 10_000 && axText.count > ocrText.count * 20 {
            return ocrText
        }
        return axText
    }

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        image: CGImage,
        captureRect: CGRect? = nil,
        source: CaptureSource = CaptureSource(appName: nil, bundleIdentifier: nil, pid: nil, url: nil),
        ocrText: String,
        ocrLines: [OCRLine] = [],
        axText: String = "",
        axElements: [AXElement] = [],
        axOutcome: AXOutcome = .notAttempted,
        entities: [DetectedEntity] = [],
        tables: [TableData] = []
    ) {
        self.id = id
        self.timestamp = timestamp
        self.image = image
        self.captureRect = captureRect
        self.source = source
        self.ocrText = ocrText
        self.ocrLines = ocrLines
        self.axText = axText
        self.axElements = axElements
        self.axOutcome = axOutcome
        self.entities = entities
        self.tables = tables
    }
}

/// The clipboard representations the user can choose between.
enum Representation: Hashable, Identifiable {
    var id: Self { self }
    case image
    case plainText
    case markdown
    case rtf
    case html
    case firstURL
    case firstEmail
    case firstPhone
    case codeBlock
    case csv
}
