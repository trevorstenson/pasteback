import Foundation

/// Builds an Apple Maps URL for a detected address (opens in Maps; no permission).
struct MapsLinkBuilder {
    func url(for address: String) -> URL? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [URLQueryItem(name: "q", value: trimmed)]
        return components?.url
    }
}
