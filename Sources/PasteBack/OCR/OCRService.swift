import Foundation
import Vision
import CoreGraphics

/// On-device OCR via Apple Vision. The assembled text remains line-level for
/// readable captures, while table inference consumes per-token boxes when
/// Vision exposes them.
final class OCRService {

    struct OCRResult {
        let text: String
        let lines: [OCRLine]
    }

    func recognize(in image: CGImage) throws -> OCRResult {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])

        let lines: [OCRLine] = (request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return OCRLine(
                text: candidate.string,
                boundingBox: observation.boundingBox,
                tokens: Self.tokens(from: candidate, fallbackBox: observation.boundingBox))
        }
        return OCRResult(text: lines.map(\.text).joined(separator: "\n"), lines: lines)
    }

    private static func tokens(from candidate: VNRecognizedText, fallbackBox: CGRect) -> [OCRToken] {
        let string = candidate.string
        var tokens: [OCRToken] = []
        var index = string.startIndex
        while index < string.endIndex {
            while index < string.endIndex, string[index].isWhitespace {
                index = string.index(after: index)
            }
            guard index < string.endIndex else { break }
            let start = index
            while index < string.endIndex, !string[index].isWhitespace {
                index = string.index(after: index)
            }
            let range = start..<index
            let text = String(string[range])
            guard !text.isEmpty else { continue }
            let box = (try? candidate.boundingBox(for: range))??.boundingBox ?? fallbackBox
            tokens.append(OCRToken(text: text, boundingBox: box))
        }
        return tokens
    }
}
