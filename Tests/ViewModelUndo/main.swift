import AppKit
import Foundation

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAILED: \(message)\n", stderr)
        exit(1)
    }
}

private func makeTestImageURL() -> URL {
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(data: nil, width: 320, height: 240, bitsPerComponent: 8,
                            bytesPerRow: 0, space: colorSpace,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(NSColor.white.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: 320, height: 240))
    let representation = NSBitmapImageRep(cgImage: context.makeImage()!)
    let data = representation.representation(using: .png, properties: [:])!
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("kakikomi-view-model-test-\(UUID().uuidString).png")
    try! data.write(to: url)
    return url
}

Task { @MainActor in
    let black = CodableColor(red: 0, green: 0, blue: 0)
    check(CodableColor.white.automaticOutlineColor == .darkOutline,
          "white uses dark automatic outline")
    check(black.automaticOutlineColor == .white,
          "black uses white automatic outline")
    check(CodableColor.accentPink.automaticOutlineColor == .white,
          "accent pink uses white automatic outline")

    let commonColorDocument = DocumentViewModel()
    let commonColorTextID = commonColorDocument.addText(at: CGPoint(x: 8, y: 8))
    commonColorDocument.setText("色テスト", for: commonColorTextID)
    commonColorDocument.undoManager.beginUndoGrouping()
    commonColorDocument.setCommonAnnotationColor(NSColor.white)
    commonColorDocument.undoManager.endUndoGrouping()
    if case .text(let text) = commonColorDocument.annotations[0] {
        check(text.fillColor == .white && text.outlineColor == .darkOutline,
              "common white is stored with a dark outline")
    }
    commonColorDocument.undoManager.beginUndoGrouping()
    commonColorDocument.setCommonAnnotationColor(NSColor.black)
    commonColorDocument.undoManager.endUndoGrouping()
    if case .text(let text) = commonColorDocument.annotations[0] {
        check(text.fillColor == black && text.outlineColor == .white,
              "common black is stored with a white outline")
    }
    commonColorDocument.undoManager.beginUndoGrouping()
    commonColorDocument.setCommonAnnotationColor(CodableColor.accentPink.nsColor)
    commonColorDocument.undoManager.endUndoGrouping()
    if case .text(let text) = commonColorDocument.annotations[0] {
        check(text.fillColor == .accentPink && text.outlineColor == .white,
              "common accent pink is stored with a white outline")
    }

    let originalText = TextAnnotation(
        text: "複製テスト",
        origin: CGPoint(x: 30, y: 40),
        fontSize: 72,
        fontName: "HiraginoSans-W8",
        fillColor: .accentPink,
        outlineColor: .white,
        outlineWidthRatio: 0.18,
        shadowEnabled: false
    )
    let duplicatedTextItem = AnnotationItem.text(originalText)
        .duplicated(offset: CGSize(width: 16, height: 16))
    if case .text(let duplicatedText) = duplicatedTextItem {
        check(duplicatedText.id != originalText.id, "text duplicate gets a new UUID")
        check(duplicatedText.origin == CGPoint(x: 46, y: 56), "text duplicate is offset")
        var expected = originalText
        expected.id = duplicatedText.id
        expected.origin = duplicatedText.origin
        check(duplicatedText == expected, "text duplicate preserves all other parameters")
    }

    let originalArrow = ArrowAnnotation(
        start: CGPoint(x: 12, y: 24),
        end: CGPoint(x: 96, y: 128),
        color: .darkOutline,
        lineWidth: 18
    )
    let duplicatedArrowItem = AnnotationItem.arrow(originalArrow)
        .duplicated(offset: CGSize(width: 16, height: 16))
    if case .arrow(let duplicatedArrow) = duplicatedArrowItem {
        check(duplicatedArrow.id != originalArrow.id, "arrow duplicate gets a new UUID")
        check(duplicatedArrow.start == CGPoint(x: 28, y: 40), "arrow start is offset")
        check(duplicatedArrow.end == CGPoint(x: 112, y: 144), "arrow end is offset")
        var expected = originalArrow
        expected.id = duplicatedArrow.id
        expected.start = duplicatedArrow.start
        expected.end = duplicatedArrow.end
        check(duplicatedArrow == expected, "arrow duplicate preserves all other parameters")
    }

    let pasteDocument = DocumentViewModel()
    let testImageURL = makeTestImageURL()
    pasteDocument.openImage(at: testImageURL)
    try? FileManager.default.removeItem(at: testImageURL)
    let encodedAnnotation = try! JSONEncoder().encode(AnnotationItem.text(originalText))
    pasteDocument.undoManager.beginUndoGrouping()
    let pastedID = pasteDocument.pasteAnnotationData(encodedAnnotation)
    pasteDocument.undoManager.endUndoGrouping()
    check(pastedID != nil, "JSON annotation is pasted")
    check(pasteDocument.annotations.count == 1, "paste appends an annotation")
    check(pasteDocument.selectedAnnotationID == pastedID, "pasted annotation is selected")
    if case .text(let pastedText) = pasteDocument.annotations[0] {
        check(pastedText.id != originalText.id, "pasted annotation gets a new UUID")
        check(pastedText.origin == CGPoint(x: 46, y: 56), "pasted annotation is offset")
    }
    pasteDocument.undo()
    check(pasteDocument.annotations.isEmpty, "paste undo restores the snapshot")

    pasteDocument.undoManager.beginUndoGrouping()
    _ = pasteDocument.pasteAnnotationData(encodedAnnotation)
    pasteDocument.undoManager.endUndoGrouping()
    if case .text(let pastedText) = pasteDocument.annotations[0] {
        check(pastedText.origin == CGPoint(x: 62, y: 72),
              "consecutive paste continues the 16 point cascade")
    }
    pasteDocument.undo()

    let pendingDocument = DocumentViewModel()
    let pendingID = pendingDocument.addText(at: CGPoint(x: 10, y: 10))
    var commitHookCallCount = 0
    pendingDocument.commitPendingTextEditing = {
        commitHookCallCount += 1
        pendingDocument.setText("保存直前の入力", for: pendingID)
    }
    pendingDocument.saveToPictures()
    check(commitHookCallCount == 1, "save invokes pending text editing commit hook")
    if case .text(let text) = pendingDocument.annotations[0] {
        check(text.text == "保存直前の入力", "pending text is reflected before export")
    }

    let emptyPendingDocument = DocumentViewModel()
    let emptyPendingID = emptyPendingDocument.addText(at: CGPoint(x: 10, y: 10))
    emptyPendingDocument.commitPendingTextEditing = {
        emptyPendingDocument.setText("   ", for: emptyPendingID)
    }
    emptyPendingDocument.copyResultToPasteboard()
    check(emptyPendingDocument.annotations.isEmpty, "empty pending text is discarded before export")

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
