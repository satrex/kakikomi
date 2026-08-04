import CoreGraphics
import Foundation

struct DragExportedImage {
    let url: URL
    let image: CGImage
}

enum DragExportService {
    static var directory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("KakikomiDrag", isDirectory: true)
    }

    static func write(
        image: CGImage,
        annotations: [AnnotationItem],
        directory: URL = DragExportService.directory,
        now: Date = Date(),
        fileManager: FileManager = .default
    ) throws -> DragExportedImage {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let existingFiles = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: []
        )
        for url in existingFiles {
            try fileManager.removeItem(at: url)
        }

        let rendered = try ImageExporter.render(image: image, annotations: annotations)
        let url = PicturesSaver.annotatedPNGURL(in: directory, now: now, fileManager: fileManager)
        try ImageExporter.data(renderedImage: rendered, format: .png).write(to: url, options: .atomic)
        return DragExportedImage(url: url, image: rendered)
    }
}
