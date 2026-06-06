// Generates QR + Code128 PNGs for the test page, fully offline (CoreImage).
// Usage: swift gen-codes.swift <output-dir>
import AppKit
import CoreImage

func writePNG(_ ci: CIImage, to path: String, scale: CGFloat) {
    let scaled = ci.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    guard let cg = CIContext().createCGImage(scaled, from: scaled.extent) else { return }
    let rep = NSBitmapImageRep(cgImage: cg)
    if let data = rep.representation(using: .png, properties: [:]) {
        try? data.write(to: URL(fileURLWithPath: path))
        print("wrote \(path)")
    }
}

func qr(_ s: String) -> CIImage? {
    guard let f = CIFilter(name: "CIQRCodeGenerator") else { return nil }
    f.setValue(s.data(using: .utf8), forKey: "inputMessage")
    f.setValue("M", forKey: "inputCorrectionLevel")
    return f.outputImage
}

func code128(_ s: String) -> CIImage? {
    guard let f = CIFilter(name: "CICode128BarcodeGenerator") else { return nil }
    f.setValue(s.data(using: .ascii), forKey: "inputMessage")
    return f.outputImage
}

let dir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
if let q = qr("https://pasteback.app/welcome") { writePNG(q, to: dir + "/qr-url.png", scale: 8) }
if let q = qr("WIFI:T:WPA;S:PasteBack Cafe;P:oatmilk2026;;") { writePNG(q, to: dir + "/qr-wifi.png", scale: 8) }
if let b = code128("1Z999AA10123456784") { writePNG(b, to: dir + "/barcode.png", scale: 2) }
