# Codex 用実装プロンプト（v1.2.1: ドラッグ書き出し改善）

以下をそのまま Codex に貼り付けて使う（/codex-cycle はヘッドレス実行する）。

---

macOS 画像注釈アプリ「Kakikomi」のドラッグ書き出しを改善してください。仕様はリポジトリ直下 `DESIGN.md` の **§13「ドラッグ書き出しの改善 v1.2.1」** に確定済みです。まず §13 を熟読してください。既存の設計制約（画像ピクセル座標系、スナップショット Undo、画面/書き出し同一レンダラ、`commitPendingTextEditing` フック、外部ライブラリ禁止）は一切変えないこと。

## 修正1: ドラッグを「実ファイル方式」に変更（ブラウザへドロップ可能に）

対象: `Kakikomi/Views/DragExportView.swift`

現状は `NSFilePromiseProvider` のみをドラッグに載せており、Finder には落とせるが Chromium 系ブラウザ（LINE WORKS 等の Web アプリ）はファイル約束を受け付けないためドロップできない。

- `mouseDragged` 開始時に注釈込み PNG を `FileManager.default.temporaryDirectory` 配下の `KakikomiDrag/` ディレクトリへ書き出し、その **file URL（NSURL）を pasteboardWriter** にしてドラッグする。`NSFilePromiseProvider` と delegate 実装は削除する
- ドラッグ開始前に `commitPendingTextEditing?()` を呼ぶこと（編集中テキストの取りこぼし防止。既存の保存系と同じ扱い）
- ファイル名は PicturesSaver と同じ「注釈 yyyy-MM-dd HH.mm.ss.png」形式+衝突連番。命名ロジックは `PicturesSaver` から関数として切り出して共有する（重複実装しない）
- ドラッグ開始のたびに `KakikomiDrag/` 内の既存ファイルを掃除してから今回分を書く（temp なので消えて実害なし）
- 書き出し失敗時はドラッグを開始せず、`document.lastErrorMessage` にメッセージを設定する

受け入れ条件: Finder へのドロップでファイルがコピーされる（従来同等）。ドラッグアイテムのペーストボードに file URL 型が載っている（テストで検証）。

## 修正2: ドラッグ像を生成画像のサムネイルに

- 書き出した CGImage から `NSImage` を作り、**アスペクト比維持で長辺 120pt** に縮小して `NSDraggingItem` の contents に使う
- ドラッグ枠（`setDraggingFrame`）はカーソル位置を基準にサムネイル寸法へ合わせる（現状の 48×48 固定を廃止）

## 修正3: v1.2 レビュー指摘【小】（DESIGN.md §13 併記）

対象: `Kakikomi/Views/CanvasView.swift` の mouseUp 内 option クリック破棄分岐

- 複製破棄時の選択復帰が `originals.last?.id` 固定になっており、クリックした注釈が最前面でない場合に選択が別の注釈へ飛ぶ → mouseDown の option 分岐でクリック元注釈の ID を保持し、破棄時はその ID へ復帰する
- 同分岐の座標取得を `imagePoint`（画像外で nil）から `clampedImagePoint` に変え、画像端でのリリースでも破棄判定が働くようにする
- ついでに同分岐の `document.baseImage!` 強制アンラップを optional binding に直す

受け入れ条件: option クリックだけ（4px 未満）では注釈数が増えず、選択がクリックした注釈に戻る。

## 検証

以下がすべて通ること:

```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Kakikomi.xcodeproj -scheme Kakikomi -configuration Debug build
```

（サンドボックスで既定 DerivedData に書けない場合は `-derivedDataPath /tmp/KakikomiDerivedData` を付けてよい）

既存テスト2本（コンパイルコマンドは `codex-fix-prompt.md` の検証節と同じ。リンク対象ファイルの増減に追随すること）:
- `Tests/main.swift`（レンダラ）
- `Tests/ViewModelUndo/main.swift`（Undo）

追加テスト（`Tests/ViewModelUndo/main.swift` の様式。UI を伴わないレベルでよい）:
- 切り出した命名関数: 「注釈 」プレフィックスと .png 拡張子、既存ファイルがある場合の連番付与
- ドラッグ用 PNG 書き出し関数（ビューから分離した部分）: 一時ディレクトリに PNG が生成され、デコード可能で、再実行で古いファイルが掃除されること

## やらないこと

- ドラッグ以外の書き出し経路（ピクチャ保存・クリップボード・別名保存）の変更
- 既存アーキテクチャの変更、外部ライブラリ、指示外リファクタリング
