import AppKit
import Foundation
import ImageIO

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

    let originalShape = ShapeAnnotation(kind: .roundedRectangle,
                                        rect: CGRect(x: 20, y: 30, width: 80, height: 50),
                                        color: .darkOutline, lineWidth: 18)
    let duplicatedShapeItem = AnnotationItem.shape(originalShape)
        .duplicated(offset: CGSize(width: 16, height: 16))
    if case .shape(let duplicatedShape) = duplicatedShapeItem {
        check(duplicatedShape.id != originalShape.id, "shape duplicate gets a new UUID")
        check(duplicatedShape.rect.origin == CGPoint(x: 36, y: 46), "shape duplicate is offset")
        var expected = originalShape
        expected.id = duplicatedShape.id
        expected.rect.origin = duplicatedShape.rect.origin
        check(duplicatedShape == expected, "shape duplicate preserves all other parameters")
    }
    let shapeRoundTrip = try! JSONDecoder().decode(AnnotationItem.self,
        from: JSONEncoder().encode(AnnotationItem.shape(originalShape)))
    check(shapeRoundTrip == .shape(originalShape), "shape Codable round-trip")
    check(originalShape.hitTest(CGPoint(x: 20, y: 55)), "shape outline is hittable")
    check(!originalShape.hitTest(CGPoint(x: 60, y: 55)), "shape interior is not hittable")

    let originalMosaic = MosaicAnnotation(rect: CGRect(x: 20, y: 30, width: 80, height: 50))
    let duplicatedMosaic = AnnotationItem.mosaic(originalMosaic).duplicated(offset: CGSize(width: 16, height: 16))
    if case .mosaic(let mosaic) = duplicatedMosaic {
        check(mosaic.id != originalMosaic.id && mosaic.rect.origin == CGPoint(x: 36, y: 46), "mosaic duplicate is offset")
    }
    let mosaicRoundTrip = try! JSONDecoder().decode(AnnotationItem.self,
        from: JSONEncoder().encode(AnnotationItem.mosaic(originalMosaic)))
    check(mosaicRoundTrip == .mosaic(originalMosaic), "mosaic Codable round-trip")

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

    let encodedShape = try! JSONEncoder().encode(AnnotationItem.shape(originalShape))
    pasteDocument.undoManager.beginUndoGrouping()
    let pastedShapeID = pasteDocument.pasteAnnotationData(encodedShape)
    pasteDocument.undoManager.endUndoGrouping()
    check(pastedShapeID != nil && pasteDocument.annotations.count == 1, "shape is pasted")
    pasteDocument.undo()
    check(pasteDocument.annotations.isEmpty, "shape paste undo restores the snapshot")

    pasteDocument.annotations = [.mosaic(originalMosaic)]
    var discardAsked = false
    pasteDocument.confirmDiscardAnnotations = { discardAsked = true; return false }
    check(!pasteDocument.shouldDiscardCurrentAnnotations() && discardAsked,
          "discard guard is injectable and can cancel opening")
    pasteDocument.confirmDiscardAnnotations = { true }
    check(pasteDocument.shouldDiscardCurrentAnnotations(), "discard guard accepts confirmation")

    let cropDocument = DocumentViewModel()
    let cropURL = makeTestImageURL()
    cropDocument.openImage(at: cropURL)
    try? FileManager.default.removeItem(at: cropURL)
    let cropTextID = cropDocument.addText(at: CGPoint(x: 40, y: 50))
    cropDocument.setText("crop", for: cropTextID)
    cropDocument.crop(to: CGRect(x: 20, y: 30, width: 100, height: 80))
    check(cropDocument.baseImage?.width == 100 && cropDocument.baseImage?.height == 80, "crop changes image size")
    check(cropDocument.annotations[0].frame.origin == CGPoint(x: 20, y: 20), "crop translates annotations")
    cropDocument.undo()
    check(cropDocument.baseImage?.width == 320 && cropDocument.baseImage?.height == 240, "crop undo restores image")
    check(cropDocument.annotations[0].frame.origin == CGPoint(x: 40, y: 50), "crop undo restores annotations")

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

    let namingDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("kakikomi-name-test-\(UUID().uuidString)", isDirectory: true)
    try! FileManager.default.createDirectory(at: namingDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: namingDirectory) }
    let exportDate = Date(timeIntervalSince1970: 1_704_067_200)
    let firstName = PicturesSaver.annotatedPNGURL(in: namingDirectory, now: exportDate)
    check(firstName.lastPathComponent.hasPrefix("注釈 "), "export name has annotation prefix")
    check(firstName.pathExtension == "png", "export name has png extension")
    try! Data().write(to: firstName)
    let secondName = PicturesSaver.annotatedPNGURL(in: namingDirectory, now: exportDate)
    check(secondName.lastPathComponent.hasSuffix(" 2.png"), "export name adds collision suffix")

    let dragDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("kakikomi-drag-test-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: dragDirectory) }
    let dragSourceURL = makeTestImageURL()
    defer { try? FileManager.default.removeItem(at: dragSourceURL) }
    let source = CGImageSourceCreateWithURL(dragSourceURL as CFURL, nil)!
    let sourceImage = CGImageSourceCreateImageAtIndex(source, 0, nil)!
    let firstDragExport = try! DragExportService.write(image: sourceImage, annotations: [], directory: dragDirectory, now: exportDate)
    check(FileManager.default.fileExists(atPath: firstDragExport.url.path), "drag export writes PNG")
    check(NSImage(contentsOf: firstDragExport.url) != nil, "drag export PNG is decodable")
    let staleURL = dragDirectory.appendingPathComponent("stale.png")
    try! Data().write(to: staleURL)
    let secondDragExport = try! DragExportService.write(
        image: sourceImage,
        annotations: [],
        directory: dragDirectory,
        now: exportDate.addingTimeInterval(60)
    )
    check(!FileManager.default.fileExists(atPath: staleURL.path), "drag export cleans old files")
    check(!FileManager.default.fileExists(atPath: firstDragExport.url.path), "drag export removes prior PNG")
    check(FileManager.default.fileExists(atPath: secondDragExport.url.path), "drag export retains current PNG")
    let dragPasteboard = NSPasteboard(name: .drag)
    check((secondDragExport.url as NSURL).writableTypes(for: dragPasteboard).contains(.fileURL),
          "drag URL writer provides the file URL pasteboard type")

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
