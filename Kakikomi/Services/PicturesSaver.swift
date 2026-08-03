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
        let baseName = "注釈 \(formatter.string(from: now))"
        var url = pictures.appendingPathComponent(baseName).appendingPathExtension("png")
        var suffix = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = pictures.appendingPathComponent("\(baseName) \(suffix)").appendingPathExtension("png")
            suffix += 1
        }
        try ImageExporter.write(image: image, annotations: annotations, to: url, format: .png)
        return url
    }
}
