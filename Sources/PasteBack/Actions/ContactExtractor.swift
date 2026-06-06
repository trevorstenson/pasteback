import Foundation

/// A contact assembled from a captured signature / business card.
struct Contact {
    var name: String?
    var organization: String?
    var title: String?
    var emails: [String]
    var phones: [String]
    var urls: [String]

    /// Conservative: only a real contact if we have a name AND a way to reach them.
    var isUsable: Bool { name != nil && (!emails.isEmpty || !phones.isEmpty) }
}

/// Extracts a `Contact` from a capture's text + detected entities and builds a
/// vCard. Heuristic and conservative — it won't fire on prose that merely
/// mentions an email.
struct ContactExtractor {

    func extract(from capture: CapturedScreenshot) -> Contact? {
        let emails = values(of: .email, in: capture)
        let phones = values(of: .phone, in: capture)
        guard !emails.isEmpty || !phones.isEmpty else { return nil }

        let lines = capture.canonicalText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard let nameIndex = lines.firstIndex(where: isNameLine) else { return nil }
        let name = lines[nameIndex]
        let (title, org) = titleAndOrg(near: nameIndex, in: lines)

        let contact = Contact(
            name: name, organization: org, title: title,
            emails: emails, phones: phones, urls: values(of: .url, in: capture))
        return contact.isUsable ? contact : nil
    }

    /// Writes a temp `.vcf` for the contact (opens in Contacts; no permission).
    func vCardFileURL(for contact: Contact) -> URL? {
        var lines = ["BEGIN:VCARD", "VERSION:3.0"]
        if let name = contact.name { lines.append("FN:\(name)") }
        if let org = contact.organization { lines.append("ORG:\(org)") }
        if let title = contact.title { lines.append("TITLE:\(title)") }
        for email in contact.emails { lines.append("EMAIL;TYPE=INTERNET:\(email)") }
        for phone in contact.phones { lines.append("TEL:\(phone)") }
        for url in contact.urls { lines.append("URL:\(url)") }
        lines.append("END:VCARD")
        let vcard = lines.joined(separator: "\n")

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pasteback-\(UUID().uuidString).vcf")
        guard (try? vcard.data(using: .utf8)?.write(to: url)) != nil else { return nil }
        return url
    }

    // MARK: - Heuristics

    private func values(of type: EntityType, in capture: CapturedScreenshot) -> [String] {
        var seen = Set<String>()
        return capture.entities.filter { $0.type == type }.map(\.value).filter { seen.insert($0).inserted }
    }

    /// A "name" line: 1–4 capitalized words, letters/.'- only, no digits or '@'.
    private func isNameLine(_ line: String) -> Bool {
        guard !line.contains("@"), line.rangeOfCharacter(from: .decimalDigits) == nil else { return false }
        let words = line.split(separator: " ")
        guard (1...4).contains(words.count) else { return false }
        return words.allSatisfy { word in
            guard let first = word.first, first.isUppercase else { return false }
            return word.allSatisfy { $0.isLetter || ".'-".contains($0) }
        }
    }

    /// Title/org from a comma line ("Senior Engineer, Acme Corp") near the name,
    /// else the line right after the name as the org.
    private func titleAndOrg(near nameIndex: Int, in lines: [String]) -> (String?, String?) {
        let candidates = lines.indices.filter { $0 != nameIndex }
        for i in candidates where lines[i].contains(",")
            && !lines[i].contains("@")
            && lines[i].rangeOfCharacter(from: .decimalDigits) == nil {
            let parts = lines[i].split(separator: ",", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            if parts.count == 2 { return (parts[0], parts[1]) }
        }
        let after = nameIndex + 1
        if lines.indices.contains(after), !lines[after].contains("@"),
           lines[after].rangeOfCharacter(from: .decimalDigits) == nil {
            return (nil, lines[after])
        }
        return (nil, nil)
    }
}
