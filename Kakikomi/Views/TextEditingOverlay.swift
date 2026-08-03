import AppKit

final class TextEditingOverlay: NSTextView {
    var onCommit: (() -> Void)?
    var onUndoAvailabilityChange: ((Bool, Bool) -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCommit?()
            return
        }
        super.keyDown(with: event)
    }

    override func didChangeText() {
        super.didChangeText()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.onUndoAvailabilityChange?(self.undoManager?.canUndo ?? false,
                                           self.undoManager?.canRedo ?? false)
        }
    }

    override func resignFirstResponder() -> Bool {
        let didResign = super.resignFirstResponder()
        if didResign { onCommit?() }
        return didResign
    }
}
