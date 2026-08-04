import AppKit
import CoreText

enum AnnotationRenderer {
    /// The incoming context uses a top-left origin. Annotation coordinates remain in source-image pixels.
    static func draw(
        image: CGImage,
        annotations: [AnnotationItem],
        in context: CGContext,
        destinationRect: CGRect
    ) {
        let scale = min(destinationRect.width / CGFloat(image.width),
                        destinationRect.height / CGFloat(image.height))
        context.saveGState()
        context.translateBy(x: destinationRect.minX, y: destinationRect.minY)
        context.scaleBy(x: scale, y: scale)

        drawBaseImage(image, in: context)
        for annotation in annotations {
            if case .mosaic(let mosaic) = annotation {
                drawMosaic(mosaic, from: image, in: context)
            }
        }
        for annotation in annotations {
            if case .mosaic = annotation { continue }
            draw(annotation, imageHeight: CGFloat(image.height), in: context)
        }
        context.restoreGState()
    }

    static func draw(_ annotation: AnnotationItem, imageHeight: CGFloat, in context: CGContext) {
        switch annotation {
        case .text(let text):
            drawOutlinedText(text, imageHeight: imageHeight, in: context)
        case .arrow(let arrow):
            drawArrow(arrow, in: context)
        case .shape(let shape):
            drawShape(shape, in: context)
        case .mosaic:
            break
        }
    }

    private static func drawMosaic(_ mosaic: MosaicAnnotation, from image: CGImage, in context: CGContext) {
        let imageRect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let rect = mosaic.rect.intersection(imageRect).integral
        guard !rect.isNull, rect.width > 0, rect.height > 0,
              let cropped = image.cropping(to: rect) else { return }
        let block = max(mosaic.blockSize, 1)
        let smallWidth = max(Int(ceil(rect.width / block)), 1)
        let smallHeight = max(Int(ceil(rect.height / block)), 1)
        let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let small = CGContext(data: nil, width: smallWidth, height: smallHeight,
                                    bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        small.interpolationQuality = .high
        small.draw(cropped, in: CGRect(x: 0, y: 0, width: smallWidth, height: smallHeight))
        guard let pixelated = small.makeImage() else { return }
        context.saveGState()
        context.translateBy(x: 0, y: CGFloat(image.height))
        context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = .none
        let destination = CGRect(x: rect.minX, y: CGFloat(image.height) - rect.maxY,
                                 width: rect.width, height: rect.height)
        context.draw(pixelated, in: destination)
        context.restoreGState()
    }

    private static func drawShape(_ shape: ShapeAnnotation, in context: CGContext) {
        context.saveGState()
        context.setLineCap(.round)
        context.setLineJoin(.round)
        let path = shape.path()
        for (color, width) in [(NSColor.white.cgColor, shape.lineWidth + 4),
                               (shape.color.nsColor.cgColor, shape.lineWidth)] {
            context.addPath(path)
            context.setStrokeColor(color)
            context.setLineWidth(width)
            context.strokePath()
        }
        context.restoreGState()
    }

    private static func drawArrow(_ arrow: ArrowAnnotation, in context: CGContext) {
        let dx = arrow.end.x - arrow.start.x
        let dy = arrow.end.y - arrow.start.y
        let length = hypot(dx, dy)
        guard length > 0.5 else { return }
        let unit = CGPoint(x: dx / length, y: dy / length)
        let normal = CGPoint(x: -unit.y, y: unit.x)
        let headLength = min(length * 0.55, max(arrow.lineWidth * 3.8, 22))
        let headHalfWidth = max(arrow.lineWidth * 1.2, 10)
        let base = CGPoint(x: arrow.end.x - unit.x * headLength,
                           y: arrow.end.y - unit.y * headLength)

        context.saveGState()
        context.setLineCap(.round)
        context.setLineJoin(.round)

        for (color, width) in [(NSColor.white.cgColor, arrow.lineWidth + 4),
                               (arrow.color.nsColor.cgColor, arrow.lineWidth)] {
            context.beginPath()
            context.move(to: arrow.start)
            context.addLine(to: base)
            context.setStrokeColor(color)
            context.setLineWidth(width)
            context.strokePath()
        }

        let outlineHead = CGMutablePath()
        outlineHead.move(to: arrow.end)
        outlineHead.addLine(to: CGPoint(x: base.x + normal.x * (headHalfWidth + 2),
                                        y: base.y + normal.y * (headHalfWidth + 2)))
        outlineHead.addLine(to: CGPoint(x: base.x - normal.x * (headHalfWidth + 2),
                                        y: base.y - normal.y * (headHalfWidth + 2)))
        outlineHead.closeSubpath()
        context.addPath(outlineHead)
        context.setFillColor(NSColor.white.cgColor)
        context.fillPath()

        let colorHead = CGMutablePath()
        colorHead.move(to: arrow.end)
        colorHead.addLine(to: CGPoint(x: base.x + normal.x * headHalfWidth,
                                      y: base.y + normal.y * headHalfWidth))
        colorHead.addLine(to: CGPoint(x: base.x - normal.x * headHalfWidth,
                                      y: base.y - normal.y * headHalfWidth))
        colorHead.closeSubpath()
        context.addPath(colorHead)
        context.setFillColor(arrow.color.nsColor.cgColor)
        context.fillPath()
        context.restoreGState()
    }

    private static func drawBaseImage(_ image: CGImage, in context: CGContext) {
        context.saveGState()
        context.translateBy(x: 0, y: CGFloat(image.height))
        context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        context.restoreGState()
    }

    private static func drawOutlinedText(
        _ annotation: TextAnnotation,
        imageHeight: CGFloat,
        in context: CGContext
    ) {
        let font = annotation.font
        let lines = annotation.text.components(separatedBy: "\n")
        let lineHeight = font.ascender - font.descender + font.leading

        context.saveGState()
        context.translateBy(x: 0, y: imageHeight)
        context.scaleBy(x: 1, y: -1)
        context.textMatrix = .identity

        for (index, string) in lines.enumerated() {
            let baselineFromTop = annotation.origin.y + font.ascender + CGFloat(index) * lineHeight
            let coreTextPoint = CGPoint(x: annotation.origin.x, y: imageHeight - baselineFromTop)

            let strokeAttributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .strokeColor: annotation.outlineColor.nsColor,
                .strokeWidth: annotation.outlineWidthRatio * 100
            ]
            let strokeLine = CTLineCreateWithAttributedString(
                NSAttributedString(string: string, attributes: strokeAttributes)
            )

            context.saveGState()
            context.setLineJoin(.round)
            context.setLineCap(.round)
            if annotation.shadowEnabled {
                context.setShadow(
                    offset: CGSize(width: 0, height: -annotation.fontSize * 0.04),
                    blur: annotation.fontSize * 0.12,
                    color: NSColor.black.withAlphaComponent(0.5).cgColor
                )
            }
            context.textPosition = coreTextPoint
            CTLineDraw(strokeLine, context)
            context.restoreGState()

            let fillAttributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: annotation.fillColor.nsColor
            ]
            let fillLine = CTLineCreateWithAttributedString(
                NSAttributedString(string: string, attributes: fillAttributes)
            )
            context.textPosition = coreTextPoint
            CTLineDraw(fillLine, context)
        }
        context.restoreGState()
    }
}
