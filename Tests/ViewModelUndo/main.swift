import AppKit
import Foundation

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAILED: \(message)\n", stderr)
        exit(1)
    }
}

Task { @MainActor in
    let document = DocumentViewModel()

    let placementBefore = document.annotations
    let id = document.addText(at: CGPoint(x: 20, y: 30))
    document.setText("最初", for: id)
    document.undoManager.beginUndoGrouping()
    document.commitSnapshot(placementBefore, actionName: "配置")
    document.undoManager.endUndoGrouping()
    document.undo()
    check(document.annotations.isEmpty, "placement undo")
    document.redo()
    check(document.annotations.count == 1, "placement redo")

    var before = document.annotations
    document.annotations[0].translate(by: CGSize(width: 15, height: 25))
    document.undoManager.beginUndoGrouping()
    document.commitSnapshot(before, actionName: "移動")
    document.undoManager.endUndoGrouping()
    document.undo()
    check(document.annotations[0].frame.origin == CGPoint(x: 20, y: 30), "move undo")
    document.redo()
    check(document.annotations[0].frame.origin == CGPoint(x: 35, y: 55), "move redo")

    before = document.annotations
    if case .text(var text) = document.annotations[0] {
        text.fontSize = 144
        document.annotations[0] = .text(text)
    }
    document.undoManager.beginUndoGrouping()
    document.commitSnapshot(before, actionName: "拡縮")
    document.undoManager.endUndoGrouping()
    document.undo()
    if case .text(let text) = document.annotations[0] {
        check(text.fontSize == 48 && text.outlineWidthRatio == 0.12, "resize undo and ratio")
    }
    document.redo()
    if case .text(let text) = document.annotations[0] {
        check(text.fontSize == 144 && text.outlineWidthRatio == 0.12, "resize redo and ratio")
    }

    before = document.annotations
    document.setText("編集後", for: id)
    document.undoManager.beginUndoGrouping()
    document.commitSnapshot(before, actionName: "編集")
    document.undoManager.endUndoGrouping()
    document.undo()
    if case .text(let text) = document.annotations[0] { check(text.text == "最初", "edit undo") }
    document.redo()
    if case .text(let text) = document.annotations[0] { check(text.text == "編集後", "edit redo") }

    document.selectedAnnotationID = id
    document.undoManager.beginUndoGrouping()
    document.removeAnnotation(id: id)
    document.undoManager.endUndoGrouping()
    check(document.annotations.isEmpty, "delete")
    document.undo()
    check(document.annotations.count == 1, "delete undo")
    document.redo()
    check(document.annotations.isEmpty, "delete redo")

    print("Undo snapshot tests passed")
    exit(0)
}

RunLoop.main.run()
