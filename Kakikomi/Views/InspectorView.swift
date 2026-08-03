import AppKit
import SwiftUI

struct InspectorView: View {
    @ObservedObject var document: DocumentViewModel

    var body: some View {
        Form {
            Section("テキスト") {
                ColorPicker("文字色", selection: Binding(
                    get: { Color(nsColor: document.inspectorTextFillColor) },
                    set: { document.setTextFillColor(NSColor($0)) }
                ), supportsOpacity: true)

                ColorPicker("縁取り色", selection: Binding(
                    get: { Color(nsColor: document.inspectorTextOutlineColor) },
                    set: { document.setTextOutlineColor(NSColor($0)) }
                ), supportsOpacity: true)

                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("縁取り幅")
                        Spacer()
                        Text("\(Int(document.inspectorOutlineRatio * 100))%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: Binding(
                        get: { document.inspectorOutlineRatio },
                        set: { document.setOutlineRatio($0) }
                    ), in: 0.04...0.24, step: 0.01)
                }

                Picker("ウェイト", selection: Binding(
                    get: { document.inspectorFontWeight },
                    set: { document.setFontWeight($0) }
                )) {
                    ForEach(FontWeightOption.allCases) { weight in
                        Text(weight.label).tag(weight)
                    }
                }
            }

            Section("矢印") {
                ColorPicker("矢印色", selection: Binding(
                    get: { Color(nsColor: document.inspectorArrowColor) },
                    set: { document.setArrowColor(NSColor($0)) }
                ), supportsOpacity: true)
            }

            Section {
                Text(document.selectedAnnotationID == nil
                     ? "変更は次に作成する注釈へ適用されます。"
                     : "変更は選択中の注釈へ適用されます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 230, idealWidth: 250, maxWidth: 280)
    }
}
