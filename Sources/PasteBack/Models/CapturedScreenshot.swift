import Foundation
import CoreGraphics

/// A line of text recognized by Vision, with its normalized bounding box.
struct OCRLine {
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
}

/// Where an entity's value came from — AX is ground truth and wins over OCR.
enum EntitySource {
    case ax
    case ocr
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

    let entities: [DetectedEntity]

    /// The canonical text for representations: AX text when present, else OCR.
    var canonicalText: String { axText.isEmpty ? ocrText : axText }

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
        entities: [DetectedEntity] = []
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
        self.entities = entities
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
}
