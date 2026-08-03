import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

enum FontWeightOption: String, CaseIterable, Identifiable {
    case w6 = "HiraginoSans-W6"
    case w7 = "HiraginoSans-W7"
    case w8 = "HiraginoSans-W8"
    case w9 = "HiraginoSans-W9"

    var id: String { rawValue }
    var label: String { rawValue.components(separatedBy: "-").last ?? rawValue }
}

@MainActor
final class DocumentViewModel: ObservableObject {
    @Published private(set) var baseImage: CGImage?
    @Published private(set) var sourceURL: URL?
    @Published var annotations: [AnnotationItem] = []
    @Published var selectedAnnotationID: UUID?
    @Published var activeTool: Tool = .select
    @Published var lastErrorMessage: String?
    @Published var statusMessage: String?
    @Published private var defaultTextFillColor: CodableColor = .white
    @Published private var defaultTextOutlineColor: CodableColor = .darkOutline
    @Published private var defaultOutlineRatio: CGFloat = 0.12
    @Published private var defaultFontWeight: FontWeightOption = .w7
    @Published private var defaultArrowColor: CodableColor = .accentPink
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    @Published private(set) var isTextEditing = false
    @Published private(set) var textEditingCanUndo = false
    @Published private(set) var textEditingCanRedo = false
    let undoManager = UndoManager()
    var commitPendingTextEditing: (() -> Void)?

    private var undoObservers: [NSObjectProtocol] = []

    var hasImage: Bool { baseImage != nil }
    var canPerformUndo: Bool { isTextEditing ? textEditingCanUndo : canUndo }
    var canPerformRedo: Bool { isTextEditing ? textEditingCanRedo : canRedo }

    init() {
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            .NSUndoManagerCheckpoint,
            .NSUndoManagerDidCloseUndoGroup,
            .NSUndoManagerDidUndoChange,
            .NSUndoManagerDidRedoChange
        ]
        undoObservers = names.map { name in
            center.addObserver(forName: name, object: undoManager, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshUndoAvailability()
                }
            }
        }
    }

    deinit {
        for observer in undoObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.title = "注釈する画像を開く"
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .gif, .heic, .webP]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openImage(at: url)
    }

    func openImage(at url: URL) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [
                  kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else {
            lastErrorMessage = "画像を開けませんでした。"
            return
        }
        baseImage = image
        sourceURL = url
        annotations = []
        selectedAnnotationID = nil
        undoManager.removeAllActions()
        refreshUndoAvailability()
        lastErrorMessage = nil
    }

    func openImageFromPasteboard() {
        let pasteboard = NSPasteboard.general
        if let data = pasteboard.data(forType: .png), loadImage(data: data) { return }
        if let data = pasteboard.data(forType: .tiff), loadImage(data: data) { return }
        if let url = NSURL(from: pasteboard) as URL? {
            openImage(at: url)
            return
        }
        lastErrorMessage = "クリップボードに画像がありません。"
    }

    @discardableResult
    private func loadImage(data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [
                  kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return false }
        baseImage = image
        sourceURL = nil
        annotations = []
        selectedAnnotationID = nil
        undoManager.removeAllActions()
        refreshUndoAvailability()
        lastErrorMessage = nil
        return true
    }

    func annotationIndex(id: UUID) -> Int? {
        annotations.firstIndex { $0.id == id }
    }

    func selectAnnotation(at point: CGPoint) -> UUID? {
        let match = annotations.reversed().first { $0.hitTest(point) }
        selectedAnnotationID = match?.id
        return match?.id
    }

    @discardableResult
    func addText(at point: CGPoint) -> UUID {
        let annotation = TextAnnotation(
            origin: point,
            fontName: defaultFontWeight.rawValue,
            fillColor: defaultTextFillColor,
            outlineColor: defaultTextOutlineColor,
            outlineWidthRatio: defaultOutlineRatio
        )
        annotations.append(.text(annotation))
        selectedAnnotationID = annotation.id
        return annotation.id
    }

    @discardableResult
    func addArrow(at point: CGPoint) -> UUID {
        let annotation = ArrowAnnotation(start: point, end: point, color: defaultArrowColor)
        annotations.append(.arrow(annotation))
        selectedAnnotationID = annotation.id
        return annotation.id
    }

    func setText(_ text: String, for id: UUID) {
        guard let index = annotationIndex(id: id), case .text(var annotation) = annotations[index] else { return }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            annotations.remove(at: index)
            selectedAnnotationID = nil
        } else {
            annotation.text = text
            annotations[index] = .text(annotation)
            selectedAnnotationID = id
            activeTool = .select
        }
    }

    func removeAnnotation(id: UUID, registeringUndo: Bool = true) {
        let before = annotations
        annotations.removeAll { $0.id == id }
        if selectedAnnotationID == id { selectedAnnotationID = nil }
        if registeringUndo { commitSnapshot(before, actionName: "注釈を削除") }
    }

    func commitSnapshot(_ before: [AnnotationItem], actionName: String) {
        guard before != annotations else { return }
        undoManager.registerUndo(withTarget: self) { target in
            target.restoreSnapshot(before, actionName: actionName)
        }
        undoManager.setActionName(actionName)
        refreshUndoAvailability()
    }

    func undo() {
        undoManager.undo()
        refreshUndoAvailability()
    }

    func redo() {
        undoManager.redo()
        refreshUndoAvailability()
    }

    func performUndoCommand() {
        if let textView = NSApp.keyWindow?.firstResponder as? NSTextView {
            textView.undoManager?.undo()
        } else {
            undo()
        }
    }

    func performRedoCommand() {
        if let textView = NSApp.keyWindow?.firstResponder as? NSTextView {
            textView.undoManager?.redo()
        } else {
            redo()
        }
    }

    func updateTextEditingUndoState(isActive: Bool, canUndo: Bool = false, canRedo: Bool = false) {
        isTextEditing = isActive
        textEditingCanUndo = isActive && canUndo
        textEditingCanRedo = isActive && canRedo
    }

    func saveToPictures() {
        commitPendingTextEditing?()
        guard let image = baseImage else { return }
        do {
            let url = try PicturesSaver.save(image: image, annotations: annotations)
            statusMessage = "\(url.lastPathComponent) をピクチャに保存しました"
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func copyResultToPasteboard() {
        commitPendingTextEditing?()
        guard let image = baseImage else { return }
        do {
            try PasteboardService.copy(image: image, annotations: annotations)
            statusMessage = "結果画像をクリップボードにコピーしました"
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func saveAs() {
        commitPendingTextEditing?()
        guard let image = baseImage else { return }
        let panel = NSSavePanel()
        panel.title = "結果画像を別名で保存"
        panel.allowedContentTypes = [.png, .jpeg]
        panel.nameFieldStringValue = "注釈.png"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let isJPEG = ["jpg", "jpeg"].contains(url.pathExtension.lowercased())
        do {
            try ImageExporter.write(image: image, annotations: annotations, to: url,
                                    format: isJPEG ? .jpeg(quality: 0.92) : .png)
            statusMessage = "\(url.lastPathComponent) を保存しました"
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    var inspectorTextFillColor: NSColor {
        selectedText?.fillColor.nsColor ?? defaultTextFillColor.nsColor
    }

    var inspectorTextOutlineColor: NSColor {
        selectedText?.outlineColor.nsColor ?? defaultTextOutlineColor.nsColor
    }

    var inspectorOutlineRatio: CGFloat {
        selectedText?.outlineWidthRatio ?? defaultOutlineRatio
    }

    var inspectorFontWeight: FontWeightOption {
        selectedText.flatMap { FontWeightOption(rawValue: $0.fontName) } ?? defaultFontWeight
    }

    var inspectorArrowColor: NSColor {
        selectedArrow?.color.nsColor ?? defaultArrowColor.nsColor
    }

    func setTextFillColor(_ color: NSColor) {
        let value = CodableColor(color)
        if !updateSelectedText(actionName: "文字色を変更", { $0.fillColor = value }) {
            defaultTextFillColor = value
        }
    }

    func setTextOutlineColor(_ color: NSColor) {
        let value = CodableColor(color)
        if !updateSelectedText(actionName: "縁取り色を変更", { $0.outlineColor = value }) {
            defaultTextOutlineColor = value
        }
    }

    func setOutlineRatio(_ ratio: CGFloat) {
        let value = min(max(ratio, 0.04), 0.24)
        if !updateSelectedText(actionName: "縁取り幅を変更", { $0.outlineWidthRatio = value }) {
            defaultOutlineRatio = value
        }
    }

    func setFontWeight(_ weight: FontWeightOption) {
        if !updateSelectedText(actionName: "フォントウェイトを変更", { $0.fontName = weight.rawValue }) {
            defaultFontWeight = weight
        }
    }

    func setArrowColor(_ color: NSColor) {
        let value = CodableColor(color)
        guard let id = selectedAnnotationID,
              let index = annotationIndex(id: id),
              case .arrow(var arrow) = annotations[index] else {
            defaultArrowColor = value
            return
        }
        let before = annotations
        arrow.color = value
        annotations[index] = .arrow(arrow)
        commitSnapshot(before, actionName: "矢印色を変更")
    }

    private var selectedText: TextAnnotation? {
        guard let id = selectedAnnotationID,
              let index = annotationIndex(id: id),
              case .text(let text) = annotations[index] else { return nil }
        return text
    }

    private var selectedArrow: ArrowAnnotation? {
        guard let id = selectedAnnotationID,
              let index = annotationIndex(id: id),
              case .arrow(let arrow) = annotations[index] else { return nil }
        return arrow
    }

    @discardableResult
    private func updateSelectedText(
        actionName: String,
        _ change: (inout TextAnnotation) -> Void
    ) -> Bool {
        guard let id = selectedAnnotationID,
              let index = annotationIndex(id: id),
              case .text(var text) = annotations[index] else { return false }
        let before = annotations
        change(&text)
        annotations[index] = .text(text)
        commitSnapshot(before, actionName: actionName)
        return true
    }

    private func restoreSnapshot(_ snapshot: [AnnotationItem], actionName: String) {
        let current = annotations
        undoManager.registerUndo(withTarget: self) { target in
            target.restoreSnapshot(current, actionName: actionName)
        }
        undoManager.setActionName(actionName)
        annotations = snapshot
        if let id = selectedAnnotationID, !annotations.contains(where: { $0.id == id }) {
            selectedAnnotationID = nil
        }
        refreshUndoAvailability()
    }

    private func refreshUndoAvailability() {
        canUndo = undoManager.canUndo
        canRedo = undoManager.canRedo
    }
}
