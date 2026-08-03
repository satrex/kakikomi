import AppKit
import CoreGraphics
import Foundation

do {
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(data: nil, width: 32, height: 24, bitsPerComponent: 8,
                            bytesPerRow: 0, space: colorSpace,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(NSColor.systemTeal.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: 32, height: 24))
    let image = context.makeImage()!
    let url = try PicturesSaver.save(image: image, annotations: [])
    guard FileManager.default.fileExists(atPath: url.path),
          let data = try? Data(contentsOf: url), !data.isEmpty else {
        fputs("Pictures save did not create a readable PNG\n", stderr)
        exit(1)
    }
    try FileManager.default.removeItem(at: url)
    print("Sandbox Pictures save passed: \(url.lastPathComponent)")
} catch {
    fputs("Sandbox Pictures save failed: \(error)\n", stderr)
    exit(1)
}
