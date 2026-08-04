import AppKit
import CoreGraphics
import Foundation
import ImageIO

private enum SmokeTestFailure: Error, CustomStringConvertible {
    case failed(String)
    var description: String {
        switch self { case .failed(let message): "FAILED: \(message)" }
    }
}

private func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw SmokeTestFailure.failed(message) }
}

private func makeAsymmetricImage() throws -> CGImage {
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let context = CGContext(data: nil, width: 8, height: 6, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        throw SmokeTestFailure.failed("source context")
    }
    context.setFillColor(NSColor.red.cgColor)
    context.fill(CGRect(x: 0, y: 3, width: 8, height: 3))
    context.setFillColor(NSColor.blue.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: 8, height: 3))
    context.setFillColor(NSColor.green.cgColor)
    context.fill(CGRect(x: 0, y: 4, width: 2, height: 2))
    guard let image = context.makeImage() else { throw SmokeTestFailure.failed("source image") }
    return image
}

private func rgbaPixels(_ image: CGImage) throws -> [UInt8] {
    let width = image.width
    let height = image.height
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let context = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: width * 4, space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        throw SmokeTestFailure.failed("pixel context")
    }
    context.interpolationQuality = .none
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return bytes
}

do {
    let source = try makeAsymmetricImage()
    let roundTrip = try ImageExporter.render(image: source, annotations: [])
    try check(roundTrip.width == source.width && roundTrip.height == source.height,
              "export must preserve source pixel dimensions")
    let roundTripPixels = try rgbaPixels(roundTrip)
    let sourcePixels = try rgbaPixels(source)
    try check(roundTripPixels == sourcePixels,
              "export without annotations must preserve image orientation and pixels")

    let text = TextAnnotation(text: "判読 Test", origin: CGPoint(x: 30, y: 30), fontSize: 48)
    let arrow = ArrowAnnotation(start: CGPoint(x: 25, y: 120), end: CGPoint(x: 260, y: 170))
    let shapes: [AnnotationItem] = [
        .shape(ShapeAnnotation(kind: .rectangle, rect: CGRect(x: 30, y: 30, width: 80, height: 55))),
        .shape(ShapeAnnotation(kind: .roundedRectangle, rect: CGRect(x: 140, y: 35, width: 90, height: 60))),
        .shape(ShapeAnnotation(kind: .ellipse, rect: CGRect(x: 255, y: 30, width: 70, height: 70)))
    ]
    let items: [AnnotationItem] = [.text(text), .arrow(arrow)] + shapes
    let encoded = try JSONEncoder().encode(items)
    let decoded = try JSONDecoder().decode([AnnotationItem].self, from: encoded)
    try check(decoded == items, "annotation value models must round-trip through Codable")
    try check(arrow.hitTest(CGPoint(x: 130, y: 143)), "arrow segment hit testing")

    var enlarged = text
    enlarged.fontSize *= 3
    try check(enlarged.outlineWidthRatio == text.outlineWidthRatio,
              "font scaling must preserve outline ratio")
    try check(enlarged.fontSize == 144, "font scaling should change font size, not only its frame")

    let canvasColor = CGColorSpace(name: CGColorSpace.sRGB)!
    let canvasContext = CGContext(data: nil, width: 360, height: 220, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: canvasColor,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    canvasContext.setFillColor(NSColor(calibratedWhite: 0.45, alpha: 1).cgColor)
    canvasContext.fill(CGRect(x: 0, y: 0, width: 360, height: 220))
    let canvas = canvasContext.makeImage()!
    let annotated = try ImageExporter.render(image: canvas, annotations: items)
    let annotatedPixels = try rgbaPixels(annotated)
    let canvasPixels = try rgbaPixels(canvas)
    try check(annotatedPixels != canvasPixels, "renderer must rasterize annotations")

    let mosaicContext = CGContext(data: nil, width: 96, height: 96, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: canvasColor,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    for y in 0..<96 { for x in 0..<96 {
        mosaicContext.setFillColor(NSColor(calibratedRed: CGFloat(x) / 95, green: CGFloat(y) / 95,
                                            blue: CGFloat((x + y) % 31) / 30, alpha: 1).cgColor)
        mosaicContext.fill(CGRect(x: x, y: y, width: 1, height: 1))
    }}
    let mosaicBase = mosaicContext.makeImage()!
    let mosaic = MosaicAnnotation(rect: CGRect(x: 16, y: 8, width: 64, height: 40), blockSize: 16)
    let mosaicRendered = try ImageExporter.render(image: mosaicBase, annotations: [.mosaic(mosaic)])
    let mosaicPixels = try rgbaPixels(mosaicRendered)
    let basePixels = try rgbaPixels(mosaicBase)
    let pixel = { (pixels: [UInt8], _ x: Int, _ y: Int) in Array(pixels[((y * 96 + x) * 4)..<((y * 96 + x) * 4 + 4)]) }
    // rgbaPixels row 0 is the image bottom; these are the corresponding buffer rows.
    try check(pixel(mosaicPixels, 32, 12) != pixel(basePixels, 32, 12),
              "mosaic changes target pixels")
    try check(pixel(mosaicPixels, 32, 80) == pixel(basePixels, 32, 80),
              "mosaic must not change vertically mirrored pixels")
    try check(pixel(mosaicPixels, 32, 12) == pixel(mosaicPixels, 33, 12),
              "adjacent pixels in a mosaic block match")
    let overText = TextAnnotation(text: "X", origin: CGPoint(x: 30, y: 22), fontSize: 36,
                                  fillColor: .white, outlineColor: .darkOutline)
    let textOverMosaic = try ImageExporter.render(image: mosaicBase, annotations: [.mosaic(mosaic), .text(overText)])
    let textOverMosaicPixels = try rgbaPixels(textOverMosaic)
    try check(pixel(textOverMosaicPixels, 41, 40) != pixel(mosaicPixels, 41, 40),
              "text above mosaic remains visible")

    let png = try ImageExporter.data(image: canvas, annotations: items, format: .png)
    let jpeg = try ImageExporter.data(image: canvas, annotations: items, format: .jpeg(quality: 0.9))
    try check(CGImageSourceCreateWithData(png as CFData, nil) != nil, "PNG must decode")
    try check(CGImageSourceCreateWithData(jpeg as CFData, nil) != nil, "JPEG must decode")

    let visualContext = CGContext(data: nil, width: 1200, height: 360, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: canvasColor,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    visualContext.setFillColor(NSColor.white.cgColor)
    visualContext.fill(CGRect(x: 0, y: 0, width: 400, height: 360))
    visualContext.setFillColor(NSColor.black.cgColor)
    visualContext.fill(CGRect(x: 400, y: 0, width: 400, height: 360))
    for row in 0..<18 {
        for column in 0..<20 {
            let hue = CGFloat((row * 7 + column * 11) % 20) / 20
            visualContext.setFillColor(NSColor(calibratedHue: hue, saturation: 0.9,
                                               brightness: (row + column).isMultiple(of: 2) ? 0.95 : 0.25,
                                               alpha: 1).cgColor)
            visualContext.fill(CGRect(x: 800 + column * 20, y: row * 20, width: 20, height: 20))
        }
    }
    let visualBase = visualContext.makeImage()!
    let visualAnnotations: [AnnotationItem] = [
        .text(TextAnnotation(text: "白背景でも判読", origin: CGPoint(x: 35, y: 125), fontSize: 48)),
        .text(TextAnnotation(text: "黒背景でも判読", origin: CGPoint(x: 435, y: 125), fontSize: 48)),
        .text(TextAnnotation(text: "模様でも判読", origin: CGPoint(x: 835, y: 125), fontSize: 48)),
        .shape(ShapeAnnotation(kind: .rectangle, rect: CGRect(x: 70, y: 210, width: 240, height: 90))),
        .shape(ShapeAnnotation(kind: .roundedRectangle, rect: CGRect(x: 470, y: 210, width: 240, height: 90))),
        .shape(ShapeAnnotation(kind: .ellipse, rect: CGRect(x: 870, y: 210, width: 240, height: 90)))
        ,.mosaic(MosaicAnnotation(rect: CGRect(x: 880, y: 240, width: 180, height: 50)))
    ]
    let visualPNG = try ImageExporter.data(image: visualBase, annotations: visualAnnotations, format: .png)
    try visualPNG.write(to: URL(fileURLWithPath: "/tmp/KakikomiVisualTest.png"), options: .atomic)
    print("Renderer smoke tests passed")
} catch {
    fputs("\(error)\n", stderr)
    exit(1)
}
