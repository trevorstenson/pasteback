import Foundation
import Vision
import CoreGraphics

/// On-device OCR via Apple Vision. Line-level results (not word-level) so
/// multi-column UI reflows sensibly and bounding boxes stay meaningful.
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
            return OCRLine(text: candidate.string, boundingBox: observation.boundingBox)
        }
        return OCRResult(text: lines.map(\.text).joined(separator: "\n"), lines: lines)
    }
}
