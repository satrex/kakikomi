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
                    Image(systemName: "folder")
                }
                .help("開く")
                .accessibilityLabel("開く")
                .accessibilityIdentifier("openImageButton")

                Button {
                    document.performPasteCommand()
                } label: {
                    Image(systemName: "doc.on.clipboard")
                }
                .help("ペースト")
                .accessibilityLabel("ペースト")
                .accessibilityIdentifier("pasteImageButton")

                Button {
                    Task { await document.importScreenshot() }
                } label: {
                    Image(systemName: "camera.viewfinder")
                }
                .help("画面取込")
                .accessibilityLabel("画面取込")
                .accessibilityIdentifier("screenshotCaptureButton")

                Divider().frame(height: 22)

                Picker("ツール", selection: $document.activeTool) {
                    Image(systemName: "cursorarrow").help("選択").accessibilityLabel("選択").tag(Tool.select)
                    Image(systemName: "textformat").help("テキスト").accessibilityLabel("テキスト").tag(Tool.text)
                    Image(systemName: "arrow.up.right").help("矢印").accessibilityLabel("矢印").tag(Tool.arrow)
                    Image(systemName: "rectangle").help("矩形").accessibilityLabel("矩形").tag(Tool.rectangle)
                    Image(systemName: "app").help("角丸").accessibilityLabel("角丸").tag(Tool.roundedRectangle)
                    Image(systemName: "oval").help("楕円").accessibilityLabel("楕円").tag(Tool.ellipse)
                    Image(systemName: "checkerboard.rectangle").help("モザイク").accessibilityLabel("モザイク").tag(Tool.mosaic)
                    Image(systemName: "crop").help("切り抜き").accessibilityLabel("切り抜き").tag(Tool.crop)
                }
                .pickerStyle(.segmented)
                .help("ツール")
                .accessibilityLabel("ツール")
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

                HStack(spacing: 10) {
                    Button {
                        document.saveToPictures()
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .help("ピクチャに保存")
                    .accessibilityLabel("ピクチャに保存")
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
                .fixedSize()
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
