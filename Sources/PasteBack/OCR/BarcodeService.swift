import Foundation
import Vision
import CoreGraphics

/// Decodes QR codes / barcodes present in the captured image via Apple Vision.
/// Image-based (not text), so it runs alongside OCR on the captured pixels.
struct BarcodeService {

    struct Payload {
        let value: String
        let symbology: String
    }

    func decode(in image: CGImage) -> [Payload] {
        let request = VNDetectBarcodesRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil else { return [] }

        return (request.results ?? []).compactMap { observation in
            guard let value = observation.payloadStringValue, !value.isEmpty else { return nil }
            return Payload(value: value, symbology: observation.symbology.rawValue)
        }
    }

    /// Decoded payloads as `.barcode` entities for the detection seed.
    func entities(in image: CGImage) -> [DetectedEntity] {
        decode(in: image).map { payload in
            DetectedEntity(
                type: .barcode(symbology: payload.symbology),
                value: payload.value,
                sourceText: payload.value
            )
        }
    }
}
