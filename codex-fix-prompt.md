# Codex 用修正プロンプト（コードレビュー反映）

以下をそのまま Codex に貼り付けて使う。

---

macOS 画像注釈アプリ「Kakikomi」のコードレビューで見つかった問題を修正してください。リポジトリ直下の `DESIGN.md` が仕様書です。設計制約（AppKit キャンバス、2パス縁取り描画、画像ピクセル座標系、スナップショットUndo など）は現状すべて守られているので、**既存のアーキテクチャを変えずに**以下だけを直してください。

## 必須修正

### 1.【中】テキスト編集中に保存すると入力中の文字が消える

現状、テキスト編集の確定（`CanvasView.commitTextEditing`、`Kakikomi/Views/CanvasView.swift`）はキャンバス内クリックか Esc でしか発火しない。編集オーバーレイ（NSTextView）が開いたままツールバーの「ピクチャに保存」、メニューの「結果画像をコピー」（Cmd+C）、「別名で保存」を実行すると、入力中のテキストが未確定のまま書き出され、画像に含まれない。

修正方針: `DocumentViewModel` の `saveToPictures()` / `copyResultToPasteboard()` / `saveAs()` の冒頭で、進行中のテキスト編集を確定させること。実装は任せるが、例えば ViewModel に `var commitPendingTextEditing: (() -> Void)?` のようなフックを持たせ、`CanvasView` が自身の `commitTextEditing` を登録する形が既存構造に合う。加えて `TextEditingOverlay` の `resignFirstResponder` でも確定させると、フォーカス喪失一般に頑健になる（二重確定しても壊れないよう `commitTextEditing` は現状通り冪等のままにすること）。

受け入れ条件: テキスト入力中（オーバーレイ表示中）に「ピクチャに保存」すると、入力途中の文字列が保存画像に描画されている。空文字のまま保存した場合は注釈が破棄され、ゴミが残らない。

### 2.【中】実在しない entitlement キーの削除

`Kakikomi/Kakikomi.entitlements` に `com.apple.security.files.pictures.read-write` が残っているが、このキーは実在しない（正しいのは既に併記されている `com.apple.security.assets.pictures.read-write`）。未認識の entitlement は App Store アップロード検証でエラーになり得る。

- `files.pictures` の行と、その経緯を説明するコメント行を削除する
- `DESIGN.md` §7 の entitlements 例も `assets.pictures` に修正する

### 3.【小】テキスト編集中の Cmd+Z がアプリ全体の Undo を発火する

`KakikomiApp.swift` の `CommandGroup(replacing: .undoRedo)` が Cmd+Z を常に `document.undo()` へ送るため、文字入力中の取り消しのつもりが注釈全体を巻き戻す。

修正方針: undo/redo コマンドの実行時、キーウィンドウの firstResponder が NSTextView（編集オーバーレイ）の場合はそちらの `undoManager` に委譲する（または NSApp 経由で responder chain に `undo:` を送る）。あわせて、メニューの有効/無効が `undoManager.canUndo/canRedo` の変化に追従しない問題も直すこと（`NSUndoManager` の checkpoint 通知を購読して `@Published` プロパティに反映するなど）。

### 4.【小】ドラッグ中にポインタが画像外へ出ると操作が止まる

`CanvasView.imagePoint(from:image:)` が画像矩形外で nil を返すため、移動・文字拡縮・矢印編集のドラッグがポインタが画像外へ出た瞬間に固まる。

修正方針: ドラッグ継続中の座標取得は「画像矩形にクランプした画像座標」を返す変種を使う（Skitch と同じ挙動）。**mouseDown での新規配置・選択判定は現状通り矩形内のみ**とし、挙動を変えないこと。

### 5.【小】`skitchPink` 識別子の改名

`CodableColor.skitchPink`（`Kakikomi/Models/CodableColor.swift`）を `accentPink` に改名し、全参照を更新する。

## 任意（余力があれば）

- 書き出しPNGに元画像のDPIメタデータ（kCGImagePropertyDPIWidth/Height）を引き継ぐ。Retinaスクリーンショット（144dpi）を保存した際、プレビューでの表示寸法が元画像と一致するようになる
- Cmd+V（クリップボードから開く）実行時、注釈が存在する場合は確認アラートを出す

## 検証

修正後、以下がすべて通ることを確認すること:

```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Kakikomi.xcodeproj -scheme Kakikomi -configuration Debug build
```

```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swiftc -o /tmp/kakikomi_renderer_test \
  Tests/main.swift \
  Kakikomi/Models/Annotation.swift Kakikomi/Models/TextAnnotation.swift \
  Kakikomi/Models/ArrowAnnotation.swift Kakikomi/Models/CodableColor.swift \
  Kakikomi/Services/AnnotationRenderer.swift Kakikomi/Services/ImageExporter.swift \
  && /tmp/kakikomi_renderer_test
```

```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swiftc -o /tmp/kakikomi_undo_test \
  Tests/ViewModelUndo/main.swift \
  Kakikomi/Models/Annotation.swift Kakikomi/Models/TextAnnotation.swift \
  Kakikomi/Models/ArrowAnnotation.swift Kakikomi/Models/CodableColor.swift \
  Kakikomi/Services/AnnotationRenderer.swift Kakikomi/Services/ImageExporter.swift \
  Kakikomi/Services/PicturesSaver.swift Kakikomi/Services/PasteboardService.swift \
  Kakikomi/ViewModels/DocumentViewModel.swift \
  && /tmp/kakikomi_undo_test
```

可能なら修正1の回帰テスト（編集確定フックを呼んだ後の annotations に入力中テキストが反映されていること）を `Tests/ViewModelUndo/main.swift` の様式で追加すること。

## やらないこと

- アーキテクチャ変更（NSDocument 化、SwiftUI Canvas 化など）
- 新機能の追加、外部ライブラリの導入
- 上記以外のリファクタリング
