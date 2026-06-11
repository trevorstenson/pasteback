import Foundation

/// Human-facing label, persistence key, and SF Symbol for each representation.
extension Representation {
    var title: String {
        switch self {
        case .image:      return "Image"
        case .plainText:  return "Text"
        case .markdown:   return "Markdown"
        case .rtf:        return "Rich Text"
        case .html:       return "HTML"
        case .firstURL:   return "First URL"
        case .firstEmail: return "First Email"
        case .firstPhone: return "Phone"
        case .codeBlock:  return "Code"
        case .csv:        return "Table (CSV)"
        }
    }

    var storageKey: String {
        switch self {
        case .image: return "image"; case .plainText: return "plainText"
        case .markdown: return "markdown"; case .rtf: return "rtf"; case .html: return "html"
        case .firstURL: return "firstURL"; case .firstEmail: return "firstEmail"
        case .firstPhone: return "firstPhone"; case .codeBlock: return "codeBlock"
        case .csv: return "csv"
        }
    }

    init?(storageKey: String) {
        switch storageKey {
        case "image": self = .image; case "plainText": self = .plainText
        case "markdown": self = .markdown; case "rtf": self = .rtf; case "html": self = .html
        case "firstURL": self = .firstURL; case "firstEmail": self = .firstEmail
        case "firstPhone": self = .firstPhone; case "codeBlock": self = .codeBlock
        case "csv": self = .csv
        default: return nil
        }
    }

    var symbolName: String {
        switch self {
        case .image:      return "photo"
        case .plainText:  return "textformat"
        case .markdown:   return "text.alignleft"
        case .rtf:        return "doc.richtext"
        case .html:       return "chevron.left.slash.chevron.right"
        case .firstURL:   return "link"
        case .firstEmail: return "envelope"
        case .firstPhone: return "phone"
        case .codeBlock:  return "curlybraces"
        case .csv:        return "tablecells"
        }
    }
}
