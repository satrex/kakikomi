import AppKit

enum PasteboardService {
    static func copy(image: CGImage, annotations: [AnnotationItem]) throws {
        let rendered = try ImageExporter.render(image: image, annotations: annotations)
        let representation = NSBitmapImageRep(cgImage: rendered)
        guard let png = representation.representation(using: .png, properties: [:]) else {
            throw ImageExporterError.finalizeFailed
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.declareTypes([.png, .tiff], owner: nil)
        pasteboard.setData(png, forType: .png)
        pasteboard.setData(representation.tiffRepresentation, forType: .tiff)
    }
}
