import SwiftUI

struct ContentView: View {
    @ObservedObject var document: DocumentViewModel

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
                    document.openImageFromPasteboard()
                } label: {
                    Label("ペースト", systemImage: "doc.on.clipboard")
                }
                .accessibilityIdentifier("pasteImageButton")

                Divider().frame(height: 22)

                Picker("ツール", selection: $document.activeTool) {
                    Label("選択", systemImage: "cursorarrow").tag(Tool.select)
                    Label("テキスト", systemImage: "textformat").tag(Tool.text)
                    Label("矢印", systemImage: "arrow.up.right").tag(Tool.arrow)
                }
                .pickerStyle(.segmented)
                .frame(width: 280)
                .disabled(!document.hasImage)
                .accessibilityIdentifier("toolPicker")

                Spacer()

                Button {
                    document.saveToPictures()
                } label: {
                    Label("ピクチャに保存", systemImage: "square.and.arrow.down")
                }
                .disabled(!document.hasImage)
                .accessibilityIdentifier("picturesSaveButton")
            }
            .buttonStyle(.bordered)
            .padding(10)
            .background(.bar)

            Divider()

            HStack(spacing: 0) {
                CanvasRepresentable(document: document)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                InspectorView(document: document)
                    .disabled(!document.hasImage)
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
