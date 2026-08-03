import AppKit
import Combine
import UniformTypeIdentifiers

final class CanvasView: NSView {
    private enum Corner: CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight
    }

    private struct TextResizeState {
        let annotationID: UUID
        let corner: Corner
        let originalAnnotations: [AnnotationItem]
        let original: TextAnnotation
        let anchor: CGPoint
        let initialDistance: CGFloat
    }

    private enum ArrowEndpoint { case start, end }

    private struct ArrowResizeState {
        let annotationID: UUID
        let endpoint: ArrowEndpoint
        let originalAnnotations: [AnnotationItem]
    }

    weak var document: DocumentViewModel? {
        didSet {
            oldValue?.commitPendingTextEditing = nil
            document?.commitPendingTextEditing = { [weak self] in
                self?.commitTextEditing()
            }
            observeDocument()
        }
    }

    private var cancellable: AnyCancellable?
    private var dragStartPoint: CGPoint?
    private var dragStartAnnotations: [AnnotationItem]?
    private var dragStartAnnotation: AnnotationItem?
    private var dragActionName = "注釈を移動"
    private var editingAnnotationID: UUID?
    private weak var textEditor: TextEditingOverlay?
    private var editingStartSnapshot: [AnnotationItem]?
    private var resizeState: TextResizeState?
    private var arrowResizeState: ArrowResizeState?
    private var drawingArrowID: UUID?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        context.setFillColor(NSColor.windowBackgroundColor.cgColor)
        context.fill(bounds)

        guard let image = document?.baseImage else {
            drawEmptyState(in: context)
            return
        }

        let imageRect = fittedImageRect(for: image)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: 2), blur: 12,
                          color: NSColor.black.withAlphaComponent(0.25).cgColor)
        AnnotationRenderer.draw(image: image,
                                annotations: document?.annotations ?? [],
                                in: context,
                                destinationRect: imageRect)
        context.restoreGState()

        if let id = document?.selectedAnnotationID,
           let annotation = document?.annotations.first(where: { $0.id == id }),
           id != editingAnnotationID {
            drawSelection(for: annotation, in: context)
        }
    }

    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard let document else { return }
        if document.activeTool == .text || document.activeTool == .arrow {
            addCursorRect(bounds, cursor: document.activeTool == .text ? .iBeam : .crosshair)
            return
        }
        guard let image = document.baseImage,
              let id = document.selectedAnnotationID,
              let annotation = document.annotations.first(where: { $0.id == id }) else { return }
        addCursorRect(viewRect(from: annotation.frame, image: image), cursor: .openHand)
        switch annotation {
        case .text:
            for corner in Corner.allCases {
                addCursorRect(handleRect(corner, for: annotation, image: image),
                              cursor: diagonalCursor(for: corner))
            }
        case .arrow(let arrow):
            addCursorRect(arrowHandleRect(arrow.start, image: image), cursor: .crosshair)
            addCursorRect(arrowHandleRect(arrow.end, image: image), cursor: .crosshair)
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let document, let image = document.baseImage else { return }
        window?.makeFirstResponder(self)

        if editingAnnotationID != nil {
            commitTextEditing()
        }

        let viewPoint = convert(event.locationInWindow, from: nil)
        guard let imagePoint = imagePoint(from: viewPoint, image: image) else {
            document.selectedAnnotationID = nil
            return
        }

        switch document.activeTool {
        case .text:
            let before = document.annotations
            let id = document.addText(at: imagePoint)
            beginTextEditing(id: id, startSnapshot: before)
        case .arrow:
            let before = document.annotations
            let id = document.addArrow(at: imagePoint)
            drawingArrowID = id
            dragStartPoint = imagePoint
            dragStartAnnotations = before
        case .select:
            if let selectedID = document.selectedAnnotationID,
               let selected = document.annotations.first(where: { $0.id == selectedID }),
               case .arrow(let arrow) = selected,
               let endpoint = hitArrowEndpoint(at: viewPoint, arrow: arrow, image: image) {
                arrowResizeState = ArrowResizeState(annotationID: selectedID,
                                                    endpoint: endpoint,
                                                    originalAnnotations: document.annotations)
                return
            }
            if let selectedID = document.selectedAnnotationID,
               let selected = document.annotations.first(where: { $0.id == selectedID }),
               case .text(let text) = selected,
               let corner = hitCorner(at: viewPoint, annotation: selected, image: image) {
                let anchor = oppositePoint(to: corner, in: text.frame)
                resizeState = TextResizeState(
                    annotationID: selectedID,
                    corner: corner,
                    originalAnnotations: document.annotations,
                    original: text,
                    anchor: anchor,
                    initialDistance: max(hypot(imagePoint.x - anchor.x, imagePoint.y - anchor.y), 0.001)
                )
                return
            }
            guard let id = document.selectAnnotation(at: imagePoint) else { return }
            if event.modifierFlags.contains(.option),
               let original = document.annotations.first(where: { $0.id == id }) {
                let before = document.annotations
                guard let duplicateID = document.appendDuplicate(of: original,
                                                                  offset: .zero,
                                                                  actionName: "複製",
                                                                  registeringUndo: false),
                      let duplicate = document.annotations.first(where: { $0.id == duplicateID }) else {
                    return
                }
                dragStartPoint = imagePoint
                dragStartAnnotations = before
                dragStartAnnotation = duplicate
                dragActionName = "複製"
                return
            }
            if event.clickCount == 2,
               let index = document.annotationIndex(id: id),
               case .text = document.annotations[index] {
                beginTextEditing(id: id, startSnapshot: document.annotations)
                return
            }
            dragStartPoint = imagePoint
            dragStartAnnotations = document.annotations
            dragStartAnnotation = document.annotations.first(where: { $0.id == id })
            dragActionName = "注釈を移動"
        }
    }

    override func mouseDragged(with event: NSEvent) {
        if let arrowResizeState {
            resizeArrow(using: arrowResizeState, event: event)
            return
        }
        if let id = drawingArrowID {
            updateArrowEndpoint(id: id, event: event)
            return
        }
        if let resizeState {
            resizeText(using: resizeState, event: event)
            return
        }
        guard let document,
              let image = document.baseImage,
              let selectedID = document.selectedAnnotationID,
              let startPoint = dragStartPoint,
              let original = dragStartAnnotation,
              let index = document.annotationIndex(id: selectedID) else { return }
        let currentPoint = clampedImagePoint(from: convert(event.locationInWindow, from: nil), image: image)
        var moved = original
        moved.translate(by: CGSize(width: currentPoint.x - startPoint.x,
                                   height: currentPoint.y - startPoint.y))
        document.annotations[index] = moved
    }

    override func mouseUp(with event: NSEvent) {
        if let drawingArrowID, let document, let before = dragStartAnnotations {
            if let index = document.annotationIndex(id: drawingArrowID),
               case .arrow(let arrow) = document.annotations[index],
               hypot(arrow.end.x - arrow.start.x, arrow.end.y - arrow.start.y) < 4 {
                document.removeAnnotation(id: drawingArrowID, registeringUndo: false)
            } else {
                document.commitSnapshot(before, actionName: "矢印を追加")
                document.activeTool = .select
            }
        } else if let arrowResizeState, let document {
            document.commitSnapshot(arrowResizeState.originalAnnotations, actionName: "矢印を編集")
        } else if let resizeState, let document {
            document.commitSnapshot(resizeState.originalAnnotations, actionName: "文字サイズを変更")
        } else if let originals = dragStartAnnotations, let document {
            document.commitSnapshot(originals, actionName: dragActionName)
        }
        resizeState = nil
        arrowResizeState = nil
        drawingArrowID = nil
        dragStartPoint = nil
        dragStartAnnotations = nil
        dragStartAnnotation = nil
        dragActionName = "注釈を移動"
        window?.invalidateCursorRects(for: self)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117 {
            if let id = document?.selectedAnnotationID {
                document?.removeAnnotation(id: id)
            }
            return
        }
        super.keyDown(with: event)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        acceptedImageURL(from: sender.draggingPasteboard) == nil ? [] : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let url = acceptedImageURL(from: sender.draggingPasteboard) else { return false }
        document?.openImage(at: url)
        return true
    }

    private func observeDocument() {
        cancellable = document?.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.needsDisplay = true }
        }
    }

    private func fittedImageRect(for image: CGImage) -> CGRect {
        let insetBounds = bounds.insetBy(dx: 28, dy: 28)
        let scale = min(insetBounds.width / CGFloat(image.width),
                        insetBounds.height / CGFloat(image.height))
        let size = CGSize(width: CGFloat(image.width) * scale,
                          height: CGFloat(image.height) * scale)
        return CGRect(x: bounds.midX - size.width / 2,
                      y: bounds.midY - size.height / 2,
                      width: size.width,
                      height: size.height)
    }

    private func imagePoint(from viewPoint: CGPoint, image: CGImage) -> CGPoint? {
        let rect = fittedImageRect(for: image)
        guard rect.contains(viewPoint) else { return nil }
        let scale = rect.width / CGFloat(image.width)
        return CGPoint(x: (viewPoint.x - rect.minX) / scale,
                       y: (viewPoint.y - rect.minY) / scale)
    }

    private func clampedImagePoint(from viewPoint: CGPoint, image: CGImage) -> CGPoint {
        let rect = fittedImageRect(for: image)
        let scale = rect.width / CGFloat(image.width)
        let clamped = CGPoint(x: min(max(viewPoint.x, rect.minX), rect.maxX),
                              y: min(max(viewPoint.y, rect.minY), rect.maxY))
        return CGPoint(x: (clamped.x - rect.minX) / scale,
                       y: (clamped.y - rect.minY) / scale)
    }

    private func viewRect(from imageRect: CGRect, image: CGImage) -> CGRect {
        let fitted = fittedImageRect(for: image)
        let scale = fitted.width / CGFloat(image.width)
        return CGRect(x: fitted.minX + imageRect.minX * scale,
                      y: fitted.minY + imageRect.minY * scale,
                      width: imageRect.width * scale,
                      height: imageRect.height * scale)
    }

    private func drawSelection(for annotation: AnnotationItem, in context: CGContext) {
        guard let image = document?.baseImage else { return }
        if case .arrow(let arrow) = annotation {
            context.saveGState()
            for point in [arrow.start, arrow.end] {
                let handle = arrowHandleRect(point, image: image)
                context.setFillColor(NSColor.white.cgColor)
                context.fillEllipse(in: handle)
                context.setStrokeColor(NSColor.controlAccentColor.cgColor)
                context.setLineWidth(2)
                context.strokeEllipse(in: handle.insetBy(dx: 1, dy: 1))
            }
            context.restoreGState()
            return
        }
        let rect = viewRect(from: annotation.frame, image: image).insetBy(dx: -4, dy: -4)
        context.saveGState()
        context.setStrokeColor(NSColor.controlAccentColor.cgColor)
        context.setLineWidth(1.5)
        context.setLineDash(phase: 0, lengths: [5, 3])
        context.stroke(rect)
        context.setLineDash(phase: 0, lengths: [])
        for corner in Corner.allCases {
            let handle = handleRect(corner, for: annotation, image: image)
            context.setFillColor(NSColor.white.cgColor)
            context.fillEllipse(in: handle)
            context.setStrokeColor(NSColor.controlAccentColor.cgColor)
            context.setLineWidth(2)
            context.strokeEllipse(in: handle.insetBy(dx: 1, dy: 1))
        }
        context.restoreGState()
    }

    private func beginTextEditing(id: UUID, startSnapshot: [AnnotationItem]) {
        guard let document,
              let image = document.baseImage,
              let index = document.annotationIndex(id: id),
              case .text(let annotation) = document.annotations[index] else { return }

        commitTextEditing()
        let annotationRect = viewRect(from: annotation.frame, image: image)
        let fitted = fittedImageRect(for: image)
        let scale = fitted.width / CGFloat(image.width)
        let editor = TextEditingOverlay(frame: CGRect(
            x: annotationRect.minX,
            y: annotationRect.minY,
            width: max(annotationRect.width + 40, min(320, fitted.maxX - annotationRect.minX)),
            height: max(annotationRect.height + 18, 52)
        ))
        editor.string = annotation.text
        editor.font = NSFont(name: annotation.fontName, size: annotation.fontSize * scale)
            ?? NSFont.systemFont(ofSize: annotation.fontSize * scale, weight: .bold)
        editor.textColor = annotation.fillColor.nsColor
        editor.backgroundColor = NSColor.black.withAlphaComponent(0.28)
        editor.drawsBackground = true
        editor.isRichText = false
        editor.isVerticallyResizable = true
        editor.allowsUndo = true
        editor.textContainerInset = CGSize(width: 4, height: 4)
        editor.onCommit = { [weak self] in self?.commitTextEditing() }
        editor.onUndoAvailabilityChange = { [weak document] canUndo, canRedo in
            document?.updateTextEditingUndoState(isActive: true, canUndo: canUndo, canRedo: canRedo)
        }
        addSubview(editor)
        editingAnnotationID = id
        editingStartSnapshot = startSnapshot
        textEditor = editor
        document.updateTextEditingUndoState(isActive: true)
        window?.makeFirstResponder(editor)
        editor.selectAll(nil)
    }

    private func commitTextEditing() {
        guard let id = editingAnnotationID else { return }
        let value = textEditor?.string ?? ""
        let snapshot = editingStartSnapshot
        let editor = textEditor
        textEditor = nil
        editingAnnotationID = nil
        editingStartSnapshot = nil
        editor?.onCommit = nil
        editor?.onUndoAvailabilityChange = nil
        editor?.removeFromSuperview()
        document?.updateTextEditingUndoState(isActive: false)
        document?.setText(value, for: id)
        if let snapshot {
            document?.commitSnapshot(snapshot, actionName: "テキストを編集")
        }
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    private func handleRect(_ corner: Corner, for annotation: AnnotationItem, image: CGImage) -> CGRect {
        let rect = viewRect(from: annotation.frame, image: image).insetBy(dx: -4, dy: -4)
        let point: CGPoint
        switch corner {
        case .topLeft: point = CGPoint(x: rect.minX, y: rect.minY)
        case .topRight: point = CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomLeft: point = CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomRight: point = CGPoint(x: rect.maxX, y: rect.maxY)
        }
        return CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10)
    }

    private func hitCorner(
        at viewPoint: CGPoint,
        annotation: AnnotationItem,
        image: CGImage
    ) -> Corner? {
        Corner.allCases.first { handleRect($0, for: annotation, image: image).insetBy(dx: -3, dy: -3).contains(viewPoint) }
    }

    private func oppositePoint(to corner: Corner, in frame: CGRect) -> CGPoint {
        switch corner {
        case .topLeft: CGPoint(x: frame.maxX, y: frame.maxY)
        case .topRight: CGPoint(x: frame.minX, y: frame.maxY)
        case .bottomLeft: CGPoint(x: frame.maxX, y: frame.minY)
        case .bottomRight: CGPoint(x: frame.minX, y: frame.minY)
        }
    }

    private func resizeText(using state: TextResizeState, event: NSEvent) {
        guard let document,
              let image = document.baseImage,
              let index = document.annotationIndex(id: state.annotationID) else { return }
        let point = clampedImagePoint(from: convert(event.locationInWindow, from: nil), image: image)
        let distance = hypot(point.x - state.anchor.x, point.y - state.anchor.y)
        var resized = state.original
        resized.fontSize = min(max(state.original.fontSize * distance / state.initialDistance, 8), 400)
        let size = resized.measuredSize
        switch state.corner {
        case .topLeft:
            resized.origin = CGPoint(x: state.anchor.x - size.width, y: state.anchor.y - size.height)
        case .topRight:
            resized.origin = CGPoint(x: state.anchor.x, y: state.anchor.y - size.height)
        case .bottomLeft:
            resized.origin = CGPoint(x: state.anchor.x - size.width, y: state.anchor.y)
        case .bottomRight:
            resized.origin = state.anchor
        }
        document.annotations[index] = .text(resized)
    }

    private func diagonalCursor(for corner: Corner) -> NSCursor {
        let symbol = (corner == .topLeft || corner == .bottomRight)
            ? "arrow.up.left.and.arrow.down.right"
            : "arrow.up.right.and.arrow.down.left"
        guard let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) else {
            return .crosshair
        }
        let configured = image.withSymbolConfiguration(.init(pointSize: 16, weight: .medium)) ?? image
        return NSCursor(image: configured, hotSpot: CGPoint(x: configured.size.width / 2,
                                                            y: configured.size.height / 2))
    }

    private func arrowHandleRect(_ point: CGPoint, image: CGImage) -> CGRect {
        let fitted = fittedImageRect(for: image)
        let scale = fitted.width / CGFloat(image.width)
        let viewPoint = CGPoint(x: fitted.minX + point.x * scale,
                                y: fitted.minY + point.y * scale)
        return CGRect(x: viewPoint.x - 5, y: viewPoint.y - 5, width: 10, height: 10)
    }

    private func hitArrowEndpoint(
        at viewPoint: CGPoint,
        arrow: ArrowAnnotation,
        image: CGImage
    ) -> ArrowEndpoint? {
        if arrowHandleRect(arrow.start, image: image).insetBy(dx: -3, dy: -3).contains(viewPoint) {
            return .start
        }
        if arrowHandleRect(arrow.end, image: image).insetBy(dx: -3, dy: -3).contains(viewPoint) {
            return .end
        }
        return nil
    }

    private func updateArrowEndpoint(id: UUID, event: NSEvent) {
        guard let document,
              let image = document.baseImage,
              let index = document.annotationIndex(id: id),
              case .arrow(var arrow) = document.annotations[index] else { return }
        let point = clampedImagePoint(from: convert(event.locationInWindow, from: nil), image: image)
        arrow.end = point
        document.annotations[index] = .arrow(arrow)
    }

    private func resizeArrow(using state: ArrowResizeState, event: NSEvent) {
        guard let document,
              let image = document.baseImage,
              let index = document.annotationIndex(id: state.annotationID),
              case .arrow(var arrow) = document.annotations[index] else { return }
        let point = clampedImagePoint(from: convert(event.locationInWindow, from: nil), image: image)
        switch state.endpoint {
        case .start: arrow.start = point
        case .end: arrow.end = point
        }
        document.annotations[index] = .arrow(arrow)
    }

    private func acceptedImageURL(from pasteboard: NSPasteboard) -> URL? {
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL] else { return nil }
        return urls.first { url in
            guard let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType else {
                return false
            }
            return type.conforms(to: .image)
        }
    }

    private func drawEmptyState(in context: CGContext) {
        let text = "画像をここにドロップ\nまたは ⌘O / ⌘V"
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let attributed = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 18, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: style
        ])
        let size = attributed.size()
        attributed.draw(in: CGRect(x: bounds.midX - size.width / 2,
                                   y: bounds.midY - size.height / 2,
                                   width: size.width,
                                   height: size.height))
    }
}
