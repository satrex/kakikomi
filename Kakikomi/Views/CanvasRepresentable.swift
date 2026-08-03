import SwiftUI

struct CanvasRepresentable: NSViewRepresentable {
    @ObservedObject var document: DocumentViewModel

    func makeNSView(context: Context) -> CanvasView {
        let view = CanvasView()
        view.document = document
        return view
    }

    func updateNSView(_ nsView: CanvasView, context: Context) {
        nsView.document = document
        nsView.needsDisplay = true
    }
}
