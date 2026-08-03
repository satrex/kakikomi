import AppKit

final class TextEditingOverlay: NSTextView {
    var onCommit: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCommit?()
            return
        }
        super.keyDown(with: event)
    }
}
