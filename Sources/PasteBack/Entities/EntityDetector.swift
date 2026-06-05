import Foundation

/// Detects entities in text using NSDataDetector (URLs, emails, phones,
/// addresses, dates) plus a regex layer (ticket IDs, commit hashes, hex colors,
/// file paths, stack traces). In M1, AX-derived ground-truth entities are unioned
/// in ahead of these and win on dedup.
struct EntityDetector {

    /// Detect over `text`, optionally seeded with ground-truth `seed` entities
    /// (e.g. real AX URLs). Seeds take precedence on dedup.
    func detect(in text: String, seed: [DetectedEntity] = []) -> [DetectedEntity] {
        var entities = seed
        guard !text.isEmpty else { return dedup(entities) }
        entities.append(contentsOf: dataDetectorEntities(in: text))
        entities.append(contentsOf: regexEntities(in: text))
        return dedup(entities)
    }

    // MARK: - NSDataDetector

    private func dataDetectorEntities(in text: String) -> [DetectedEntity] {
        let types: NSTextCheckingResult.CheckingType = [.link, .phoneNumber, .address, .date]
        guard let detector = try? NSDataDetector(types: types.rawValue) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        var out: [DetectedEntity] = []

        detector.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match, let r = Range(match.range, in: text) else { return }
            let source = String(text[r])
            switch match.resultType {
            case .link:
                if let url = match.url {
                    if url.scheme == "mailto" {
                        out.append(DetectedEntity(type: .email,
                            value: url.absoluteString.replacingOccurrences(of: "mailto:", with: ""),
                            sourceText: source))
                    } else {
                        out.append(DetectedEntity(type: .url, value: url.absoluteString, sourceText: source))
                    }
                }
            case .phoneNumber:
                out.append(DetectedEntity(type: .phone, value: match.phoneNumber ?? source, sourceText: source))
            case .address:
                // NSDataDetector over-matches addresses; reject single-word hits.
                if source.split(whereSeparator: { $0.isWhitespace }).count >= 3 {
                    out.append(DetectedEntity(type: .address, value: source, sourceText: source))
                }
            case .date:
                out.append(DetectedEntity(type: .date, value: source, sourceText: source))
            default: break
            }
        }
        return out
    }

    // MARK: - Regex layer

    private func regexEntities(in text: String) -> [DetectedEntity] {
        var out: [DetectedEntity] = []
        out += matches(text, #"\b[A-Z]{2,10}-\d+\b"#).map {
            DetectedEntity(type: .ticketID(system: String($0.split(separator: "-").first ?? "")),
                           value: $0, sourceText: $0)
        }
        out += matches(text, ##"#\d+\b"##).map {
            DetectedEntity(type: .ticketID(system: "GITHUB"), value: $0, sourceText: $0)
        }
        out += matches(text, ##"#(?:[0-9A-Fa-f]{8}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{3})\b"##).map {
            DetectedEntity(type: .hexColor, value: $0, sourceText: $0)
        }
        out += matches(text, #"\b[0-9a-f]{7,40}\b"#).map {
            DetectedEntity(type: .commitHash, value: $0, sourceText: $0)
        }
        out += matches(text, #"(?:~|\.{0,2})(?:/[\w.\-]+){2,}"#).map {
            DetectedEntity(type: .filePath, value: $0, sourceText: $0)
        }
        if text.contains("Traceback (most recent call last)")
            || matches(text, #"(?m)^\s+at\s+\S+\(\S+:\d+\)"#).count >= 1 {
            out.append(DetectedEntity(type: .stackTrace, value: text, sourceText: text))
        }
        return out
    }

    private func matches(_ text: String, _ pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap {
            Range($0.range, in: text).map { String(text[$0]) }
        }
    }

    // MARK: - Dedup (seed/AX entries kept first → they win)

    private func dedup(_ entities: [DetectedEntity]) -> [DetectedEntity] {
        var seen = Set<String>()
        return entities.filter { seen.insert("\($0.type)|\($0.value)").inserted }
    }
}
