import CoreGraphics
import Foundation

enum Tool: String, Codable, CaseIterable {
    case select
    case text
    case arrow
}

protocol Annotation: Identifiable, Codable, Equatable {
    var id: UUID { get }
    var frame: CGRect { get set }
    func hitTest(_ point: CGPoint) -> Bool
}

enum AnnotationItem: Codable, Equatable, Identifiable {
    case text(TextAnnotation)
    case arrow(ArrowAnnotation)

    var id: UUID {
        switch self {
        case .text(let annotation): annotation.id
        case .arrow(let annotation): annotation.id
        }
    }

    var frame: CGRect {
        get {
            switch self {
            case .text(let annotation): annotation.frame
            case .arrow(let annotation): annotation.frame
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
            }
        }
    }

    func hitTest(_ point: CGPoint) -> Bool {
        switch self {
        case .text(let annotation): annotation.hitTest(point)
        case .arrow(let annotation): annotation.hitTest(point)
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
        }
    }
}
