import CoreGraphics
import Foundation

struct ArrowAnnotation: Annotation {
    var id = UUID()
    var start: CGPoint
    var end: CGPoint
    var color: CodableColor = .accentPink
    var lineWidth: CGFloat = 12

    var frame: CGRect {
        get {
            CGRect(x: min(start.x, end.x),
                   y: min(start.y, end.y),
                   width: abs(end.x - start.x),
                   height: abs(end.y - start.y))
        }
        set {
            let oldOrigin = frame.origin
            let delta = CGSize(width: newValue.minX - oldOrigin.x,
                               height: newValue.minY - oldOrigin.y)
            start.x += delta.width
            start.y += delta.height
            end.x += delta.width
            end.y += delta.height
        }
    }

    func hitTest(_ point: CGPoint) -> Bool {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(point.x - start.x, point.y - start.y) < 12 }
        let projection = max(0, min(1, ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared))
        let nearest = CGPoint(x: start.x + projection * dx, y: start.y + projection * dy)
        return hypot(point.x - nearest.x, point.y - nearest.y) <= max(lineWidth, 10)
    }
}
