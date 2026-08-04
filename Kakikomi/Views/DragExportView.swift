import AppKit
import SwiftUI

struct DragExportView: NSViewRepresentable {
    @ObservedObject var document: DocumentViewModel

    func makeNSView(context: Context) -> ExportDragSourceView {
        let view = ExportDragSourceView()
        view.document = document
        return view
    }

    func updateNSView(_ nsView: ExportDragSourceView, context: Context) {
        nsView.document = document
        nsView.needsDisplay = true
    }
}

final class ExportDragSourceView: NSView, NSDraggingSource {
    weak var document: DocumentViewModel?

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 8, yRadius: 8)
        NSColor.controlAccentColor.withAlphaComponent(document?.hasImage == true ? 0.16 : 0.05).setFill()
        path.fill()
        NSColor.controlAccentColor.withAlphaComponent(document?.hasImage == true ? 0.7 : 0.2).setStroke()
        path.lineWidth = 1.5
        path.stroke()

        let text = NSAttributedString(string: "↗  結果画像をドラッグ", attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: document?.hasImage == true ? NSColor.labelColor : NSColor.disabledControlTextColor
        ])
        let size = text.size()
        text.draw(at: CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2))
    }

    override func mouseDragged(with event: NSEvent) {
        guard let document, let image = document.baseImage else { return }
        document.commitPendingTextEditing?()
        do {
            let exported = try DragExportService.write(image: image, annotations: document.annotations)
            let item = NSDraggingItem(pasteboardWriter: exported.url as NSURL)
            let thumbnail = thumbnail(for: exported.image)
            let cursor = convert(event.locationInWindow, from: nil)
            item.setDraggingFrame(CGRect(origin: cursor, size: thumbnail.size), contents: thumbnail)
            beginDraggingSession(with: [item], event: event, source: self)
        } catch {
            document.lastErrorMessage = error.localizedDescription
        }
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    private func thumbnail(for image: CGImage) -> NSImage {
        let longestSide = max(CGFloat(image.width), CGFloat(image.height))
        let scale = min(1, 120 / longestSide)
        let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        return NSImage(cgImage: image, size: size)
    }
}
