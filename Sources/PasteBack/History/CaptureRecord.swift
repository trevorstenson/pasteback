import Foundation

/// Codable sidecar of a capture for on-disk history. The live model types stay
/// non-Codable on purpose (`CGImage` isn't Codable; `EntityType` has associated
/// values) — this DTO is the persistence boundary. `axElements` are not
/// persisted (heavy, only needed live); `ocrLines`/`captureRect` likewise.
struct CaptureRecord: Codable, Identifiable {

    struct Source: Codable {
        let appName: String?
        let bundleIdentifier: String?
        let url: String?
    }

    struct Entity: Codable {
        /// Stringified `EntityType`, e.g. `"url"`, `"ticketID:JIRA"`,
        /// `"codeBlock:swift"`, `"barcode:QR"`.
        let kind: String
        let value: String
        let sourceText: String
        /// `"ax"` or `"ocr"`.
        let source: String
    }

    struct Table: Codable {
        let headers: [String]?
        let rows: [[String]]
        /// `"ax"` or `"ocr"`.
        let source: String
    }

    let id: UUID
    let timestamp: Date
    let source: Source
    let ocrText: String
    let axText: String
    let entities: [Entity]
    /// Optional for backward compatibility with records written before Stage 6.
    let tables: [Table]?

    init(capture: CapturedScreenshot) {
        id = capture.id
        timestamp = capture.timestamp
        source = Source(appName: capture.source.appName,
                        bundleIdentifier: capture.source.bundleIdentifier,
                        url: capture.source.url?.absoluteString)
        ocrText = capture.ocrText
        axText = capture.axText
        entities = capture.entities.map {
            Entity(kind: Self.kindString(for: $0.type),
                   value: $0.value,
                   sourceText: $0.sourceText,
                   source: $0.source == .ax ? "ax" : "ocr")
        }
        tables = capture.tables.map {
            Table(headers: $0.headers, rows: $0.rows, source: $0.source == .ax ? "ax" : "ocr")
        }
    }

    /// Typed tables for re-hydration.
    func detectedTables() -> [TableData] {
        (tables ?? []).map {
            TableData(headers: $0.headers, rows: $0.rows, source: $0.source == "ax" ? .ax : .ocr)
        }
    }

    /// Typed entities for re-hydration (unknown kinds from future versions are
    /// dropped rather than failing the whole record).
    func detectedEntities() -> [DetectedEntity] {
        entities.compactMap { entity in
            guard let type = Self.entityType(fromKind: entity.kind) else { return nil }
            return DetectedEntity(type: type,
                                  value: entity.value,
                                  sourceText: entity.sourceText,
                                  boundingBox: nil,
                                  source: entity.source == "ax" ? .ax : .ocr)
        }
    }

    /// Everything the history search box matches against (seed of the
    /// "find that error I shot last week" corpus).
    var searchableText: String {
        let canonical = axText.isEmpty ? ocrText : axText
        return ([canonical] + entities.map(\.value)).joined(separator: "\n")
    }

    // MARK: - EntityType <-> String

    static func kindString(for type: EntityType) -> String {
        switch type {
        case .url:                      return "url"
        case .email:                    return "email"
        case .phone:                    return "phone"
        case .address:                  return "address"
        case .date:                     return "date"
        case .ticketID(let system):     return "ticketID:\(system)"
        case .commitHash:               return "commitHash"
        case .filePath:                 return "filePath"
        case .hexColor:                 return "hexColor"
        case .codeBlock(let language):  return language.map { "codeBlock:\($0)" } ?? "codeBlock"
        case .stackTrace:               return "stackTrace"
        case .barcode(let symbology):   return symbology.map { "barcode:\($0)" } ?? "barcode"
        }
    }

    static func entityType(fromKind kind: String) -> EntityType? {
        let parts = kind.split(separator: ":", maxSplits: 1).map(String.init)
        let base = parts.first ?? kind
        let argument = parts.count > 1 ? parts[1] : nil
        switch base {
        case "url":         return .url
        case "email":       return .email
        case "phone":       return .phone
        case "address":     return .address
        case "date":        return .date
        case "ticketID":    return .ticketID(system: argument ?? "")
        case "commitHash":  return .commitHash
        case "filePath":    return .filePath
        case "hexColor":    return .hexColor
        case "codeBlock":   return .codeBlock(language: argument)
        case "stackTrace":  return .stackTrace
        case "barcode":     return .barcode(symbology: argument)
        default:            return nil
        }
    }
}
