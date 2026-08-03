import AppKit
import SwiftUI
import UniformTypeIdentifiers

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

final class ExportDragSourceView: NSView, NSDraggingSource, NSFilePromiseProviderDelegate {
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
        guard let document, let image = document.baseImage,
              let data = try? ImageExporter.data(image: image, annotations: document.annotations, format: .png) else { return }
        let provider = NSFilePromiseProvider(fileType: UTType.png.identifier, delegate: self)
        provider.userInfo = data
        let item = NSDraggingItem(pasteboardWriter: provider)
        let icon = NSImage(systemSymbolName: "photo", accessibilityDescription: "結果画像")
            ?? NSImage(size: CGSize(width: 48, height: 48))
        item.setDraggingFrame(CGRect(origin: convert(event.locationInWindow, from: nil), size: CGSize(width: 48, height: 48)),
                              contents: icon)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
        "注釈.png"
    }

    func filePromiseProvider(
        _ filePromiseProvider: NSFilePromiseProvider,
        writePromiseTo url: URL,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let data = filePromiseProvider.userInfo as? Data else {
            completionHandler(ImageExporterError.imageCreationFailed)
            return
        }
        do {
            try data.write(to: url, options: .atomic)
            completionHandler(nil)
        } catch {
            completionHandler(error)
        }
    }
}
