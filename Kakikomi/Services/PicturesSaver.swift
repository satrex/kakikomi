import CoreGraphics
import Foundation

enum PicturesSaver {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return formatter
    }()

    static func save(image: CGImage, annotations: [AnnotationItem], now: Date = Date()) throws -> URL {
        let pictures = try FileManager.default.url(
            for: .picturesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let url = annotatedPNGURL(in: pictures, now: now)
        try ImageExporter.write(image: image, annotations: annotations, to: url, format: .png)
        return url
    }

    static func annotatedPNGURL(in directory: URL, now: Date = Date(), fileManager: FileManager = .default) -> URL {
        let baseName = "注釈 \(formatter.string(from: now))"
        var url = directory.appendingPathComponent(baseName).appendingPathExtension("png")
        var suffix = 2
        while fileManager.fileExists(atPath: url.path) {
            url = directory.appendingPathComponent("\(baseName) \(suffix)").appendingPathExtension("png")
            suffix += 1
        }
        return url
    }
}
