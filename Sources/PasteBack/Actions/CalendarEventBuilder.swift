import Foundation

/// Builds a `.ics` calendar event from a capture's detected `.date` entity, so
/// "Add to Calendar" hands off to the user's calendar app with no permission.
struct CalendarEventBuilder {

    /// Writes a temp `.ics` for the first date in the capture; nil if no date.
    func icsFileURL(for capture: CapturedScreenshot) -> URL? {
        guard let dateEntity = capture.entities.first(where: { $0.type == .date }),
              let start = parseDate(value: dateEntity.value, fallback: dateEntity.sourceText)
        else { return nil }

        let end = start.addingTimeInterval(3600)
        let title = eventTitle(from: capture)
        let location = capture.entities.first { $0.type == .address }?.value ?? ""
        var description = capture.canonicalText
        if let url = capture.source.url { description += "\n\nFrom: \(url.absoluteString)" }

        let ics = """
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//Paste-Back//EN
        BEGIN:VEVENT
        UID:\(UUID().uuidString)@pasteback
        DTSTAMP:\(stamp(Date()))
        DTSTART:\(stamp(start))
        DTEND:\(stamp(end))
        SUMMARY:\(escape(title))
        LOCATION:\(escape(location))
        DESCRIPTION:\(escape(description))
        END:VEVENT
        END:VCALENDAR
        """

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pasteback-\(UUID().uuidString).ics")
        guard (try? ics.data(using: .utf8)?.write(to: url)) != nil else { return nil }
        return url
    }

    // MARK: - Helpers

    private func parseDate(value: String, fallback: String) -> Date? {
        if let d = ISO8601DateFormatter().date(from: value) { return d }
        // Re-parse the raw matched text if the value wasn't ISO-8601.
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        else { return nil }
        let range = NSRange(fallback.startIndex..., in: fallback)
        return detector.firstMatch(in: fallback, range: range)?.date
    }

    /// First non-empty line of the capture, trimmed, as the event title.
    private func eventTitle(from capture: CapturedScreenshot) -> String {
        let firstLine = capture.canonicalText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? "Event"
        return String(firstLine.prefix(80))
    }

    /// Floating local time `yyyyMMddTHHmmss`.
    private func stamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd'T'HHmmss"
        return f.string(from: date)
    }

    private func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}
