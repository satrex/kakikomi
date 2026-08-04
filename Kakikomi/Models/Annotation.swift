import CoreGraphics
import Foundation

enum Tool: String, Codable, CaseIterable {
    case select
    case text
    case arrow
    case rectangle
    case roundedRectangle
    case ellipse
    case mosaic
    case crop

    var shapeKind: ShapeKind? {
        switch self {
        case .rectangle: .rectangle
        case .roundedRectangle: .roundedRectangle
        case .ellipse: .ellipse
        default: nil
        }
    }
}

enum ShapeKind: String, Codable { case rectangle, roundedRectangle, ellipse }

struct ShapeAnnotation: Annotation {
    var id = UUID()
    var kind: ShapeKind
    var rect: CGRect {
        didSet { rect = rect.standardized }
    }
    var color: CodableColor = .accentPink
    var lineWidth: CGFloat = 12

    init(id: UUID = UUID(), kind: ShapeKind, rect: CGRect, color: CodableColor = .accentPink,
         lineWidth: CGFloat = 12) {
        self.id = id
        self.kind = kind
        self.rect = rect.standardized
        self.color = color
        self.lineWidth = lineWidth
    }

    var frame: CGRect {
        get { rect }
        set { rect = newValue.standardized }
    }

    func path() -> CGPath {
        let path = CGMutablePath()
        switch kind {
        case .rectangle:
            path.addRect(rect)
        case .roundedRectangle:
            let radius = min(min(rect.width, rect.height) * 0.2, 32)
            path.addRoundedRect(in: rect, cornerWidth: radius, cornerHeight: radius)
        case .ellipse:
            path.addEllipse(in: rect)
        }
        return path
    }

    func hitTest(_ point: CGPoint) -> Bool {
        path().copy(strokingWithWidth: max(lineWidth * 2, 20), lineCap: .round,
                    lineJoin: .round, miterLimit: 10).contains(point)
    }
}

struct MosaicAnnotation: Annotation {
    var id = UUID()
    var rect: CGRect { didSet { rect = rect.standardized } }
    var blockSize: CGFloat = 16

    init(id: UUID = UUID(), rect: CGRect, blockSize: CGFloat = 16) {
        self.id = id
        self.rect = rect.standardized
        self.blockSize = blockSize
    }

    var frame: CGRect {
        get { rect }
        set { rect = newValue.standardized }
    }

    func hitTest(_ point: CGPoint) -> Bool { rect.contains(point) }
}

protocol Annotation: Identifiable, Codable, Equatable {
    var id: UUID { get }
    var frame: CGRect { get set }
    func hitTest(_ point: CGPoint) -> Bool
}

enum AnnotationItem: Codable, Equatable, Identifiable {
    case text(TextAnnotation)
    case arrow(ArrowAnnotation)
    case shape(ShapeAnnotation)
    case mosaic(MosaicAnnotation)

    var id: UUID {
        switch self {
        case .text(let annotation): annotation.id
        case .arrow(let annotation): annotation.id
        case .shape(let annotation): annotation.id
        case .mosaic(let annotation): annotation.id
        }
    }

    var frame: CGRect {
        get {
            switch self {
            case .text(let annotation): annotation.frame
            case .arrow(let annotation): annotation.frame
            case .shape(let annotation): annotation.frame
            case .mosaic(let annotation): annotation.frame
            }
        }
        set {
            switch self {
            case .text(var annotation):
                annotation.frame = newValue
                self = .text(annotation)
            case .arrow(var annotation):
                annotation.frame = newValue
                self = .arrow(annotation)
            case .shape(var annotation):
                annotation.frame = newValue
                self = .shape(annotation)
            case .mosaic(var annotation):
                annotation.frame = newValue
                self = .mosaic(annotation)
            }
        }
    }

    func hitTest(_ point: CGPoint) -> Bool {
        switch self {
        case .text(let annotation): annotation.hitTest(point)
        case .arrow(let annotation): annotation.hitTest(point)
        case .shape(let annotation): annotation.hitTest(point)
        case .mosaic(let annotation): annotation.hitTest(point)
        }
    }

    mutating func translate(by delta: CGSize) {
        var moved = frame
        moved.origin.x += delta.width
        moved.origin.y += delta.height
        frame = moved
    }

    func duplicated(offset: CGSize) -> AnnotationItem {
        switch self {
        case .text(var annotation):
            annotation.id = UUID()
            annotation.origin.x += offset.width
            annotation.origin.y += offset.height
            return .text(annotation)
        case .arrow(var annotation):
            annotation.id = UUID()
            annotation.start.x += offset.width
            annotation.start.y += offset.height
            annotation.end.x += offset.width
            annotation.end.y += offset.height
            return .arrow(annotation)
        case .shape(var annotation):
            annotation.id = UUID()
            annotation.rect.origin.x += offset.width
            annotation.rect.origin.y += offset.height
            return .shape(annotation)
        case .mosaic(var annotation):
            annotation.id = UUID()
            annotation.rect.origin.x += offset.width
            annotation.rect.origin.y += offset.height
            return .mosaic(annotation)
        }
    }
}
