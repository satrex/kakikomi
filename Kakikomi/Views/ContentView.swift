import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var document: DocumentViewModel
    @AppStorage("uiMode") private var uiMode = UIMode.simple.rawValue

    private enum UIMode: String {
        case simple
        case detailed
    }

    private var isDetailedMode: Bool {
        uiMode == UIMode.detailed.rawValue
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    document.presentOpenPanel()
                } label: {
                    Label("開く", systemImage: "folder")
                }
                .accessibilityIdentifier("openImageButton")

                Button {
                    document.performPasteCommand()
                } label: {
                    Label("ペースト", systemImage: "doc.on.clipboard")
                }
                .accessibilityIdentifier("pasteImageButton")

                Button {
                    Task { await document.importScreenshot() }
                } label: {
                    Label("画面取込", systemImage: "camera.viewfinder")
                }
                .accessibilityIdentifier("screenshotCaptureButton")

                Divider().frame(height: 22)

                Picker("ツール", selection: $document.activeTool) {
                    Label("選択", systemImage: "cursorarrow").tag(Tool.select)
                    Label("テキスト", systemImage: "textformat").tag(Tool.text)
                    Label("矢印", systemImage: "arrow.up.right").tag(Tool.arrow)
                    Label("矩形", systemImage: "rectangle").tag(Tool.rectangle)
                    Label("角丸", systemImage: "app").tag(Tool.roundedRectangle)
                    Label("楕円", systemImage: "oval").tag(Tool.ellipse)
                    Label("モザイク", systemImage: "checkerboard.rectangle").tag(Tool.mosaic)
                    Label("切り抜き", systemImage: "crop").tag(Tool.crop)
                }
                .pickerStyle(.segmented)
                .disabled(!document.hasImage)
                .accessibilityIdentifier("toolPicker")

                if !isDetailedMode {
                    Divider().frame(height: 22)

                    ColorPicker("注釈色", selection: Binding(
                        get: { Color(nsColor: document.commonAnnotationColor) },
                        set: { document.setCommonAnnotationColor(NSColor($0)) }
                    ), supportsOpacity: true)
                    .labelsHidden()
                    .help("文字・矢印・図形の色")
                    .disabled(!document.hasImage)
                    .accessibilityIdentifier("commonColorPicker")
                }

                Spacer()

                Button {
                    document.saveToPictures()
                } label: {
                    Label("ピクチャに保存", systemImage: "square.and.arrow.down")
                }
                .disabled(!document.hasImage)
                .accessibilityIdentifier("picturesSaveButton")

                Button {
                    uiMode = isDetailedMode ? UIMode.simple.rawValue : UIMode.detailed.rawValue
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .help(isDetailedMode ? "簡易モードに切り替える" : "詳細モードに切り替える")
                .accessibilityLabel(isDetailedMode ? "簡易モード" : "詳細モード")
                .accessibilityIdentifier("uiModeToggle")
            }
            .buttonStyle(.bordered)
            .padding(10)
            .background(.bar)

            Divider()

            HStack(spacing: 0) {
                CanvasRepresentable(document: document)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if isDetailedMode {
                    Divider()
                    InspectorView(document: document)
                        .disabled(!document.hasImage)
                }
            }

            HStack {
                DragExportView(document: document)
                    .frame(width: 190, height: 36)
                    .opacity(document.hasImage ? 1 : 0.55)
                Spacer()
                if let status = document.statusMessage {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(10)
            .background(.bar)
        }
        .alert("エラー", isPresented: Binding(
            get: { document.lastErrorMessage != nil },
            set: { if !$0 { document.lastErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { document.lastErrorMessage = nil }
        } message: {
            Text(document.lastErrorMessage ?? "")
        }
    }
}
