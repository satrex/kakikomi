import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ExportFormat {
    case png
    case jpeg(quality: CGFloat)

    var uniformType: UTType {
        switch self {
        case .png: .png
        case .jpeg: .jpeg
        }
    }
}

enum ImageExporterError: LocalizedError {
    case contextCreationFailed
    case imageCreationFailed
    case destinationCreationFailed
    case finalizeFailed

    var errorDescription: String? {
        switch self {
        case .contextCreationFailed: "書き出し用キャンバスを作成できませんでした。"
        case .imageCreationFailed: "結果画像を作成できませんでした。"
        case .destinationCreationFailed: "画像エンコーダーを作成できませんでした。"
        case .finalizeFailed: "画像のエンコードに失敗しました。"
        }
    }
}

enum ImageExporter {
    static func render(image: CGImage, annotations: [AnnotationItem]) throws -> CGImage {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: image.width,
                  height: image.height,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                      | CGBitmapInfo.byteOrder32Big.rawValue
              ) else { throw ImageExporterError.contextCreationFailed }

        // AnnotationRenderer accepts a top-left coordinate system, matching CanvasView.
        context.translateBy(x: 0, y: CGFloat(image.height))
        context.scaleBy(x: 1, y: -1)
        AnnotationRenderer.draw(
            image: image,
            annotations: annotations,
            in: context,
            destinationRect: CGRect(x: 0, y: 0, width: image.width, height: image.height)
        )
        guard let result = context.makeImage() else { throw ImageExporterError.imageCreationFailed }
        return result
    }

    static func data(
        image: CGImage,
        annotations: [AnnotationItem],
        format: ExportFormat
    ) throws -> Data {
        let rendered = try render(image: image, annotations: annotations)
        return try data(renderedImage: rendered, format: format)
    }

    static func data(renderedImage: CGImage, format: ExportFormat) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            format.uniformType.identifier as CFString,
            1,
            nil
        ) else { throw ImageExporterError.destinationCreationFailed }

        let properties: CFDictionary?
        switch format {
        case .png:
            properties = nil
        case .jpeg(let quality):
            properties = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        }
        CGImageDestinationAddImage(destination, renderedImage, properties)
        guard CGImageDestinationFinalize(destination) else { throw ImageExporterError.finalizeFailed }
        return data as Data
    }

    static func write(
        image: CGImage,
        annotations: [AnnotationItem],
        to url: URL,
        format: ExportFormat
    ) throws {
        try data(image: image, annotations: annotations, format: format)
            .write(to: url, options: .atomic)
    }
}
