import SwiftUI

@main
struct KakikomiApp: App {
    @StateObject private var document = DocumentViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(document: document)
                .frame(minWidth: 900, minHeight: 620)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("画像を開く…") {
                    document.presentOpenPanel()
                }
                .keyboardShortcut("o")
            }

            CommandGroup(replacing: .pasteboard) {
                Button("結果画像をコピー") {
                    document.copyResultToPasteboard()
                }
                .keyboardShortcut("c")
                .disabled(!document.hasImage)

                Button("クリップボードから画像を開く") {
                    document.openImageFromPasteboard()
                }
                .keyboardShortcut("v")
            }

            CommandGroup(after: .saveItem) {
                Button("別名で保存…") { document.saveAs() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                    .disabled(!document.hasImage)
            }

            CommandGroup(replacing: .undoRedo) {
                Button("取り消す") { document.performUndoCommand() }
                    .keyboardShortcut("z")
                    .disabled(!document.canPerformUndo)
                Button("やり直す") { document.performRedoCommand() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(!document.canPerformRedo)
            }
        }
    }
}
