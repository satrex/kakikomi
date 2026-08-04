# Codex 用実装プロンプト（v1.2: 図形注釈）

以下をそのまま Codex に貼り付けて使う（/codex-cycle はヘッドレス実行する）。

---

macOS 画像注釈アプリ「Kakikomi」に図形注釈（矩形・角丸矩形・楕円）を追加してください。仕様はリポジトリ直下 `DESIGN.md` の **§12「図形注釈 v1.2」** に確定済みです。まず §12 を熟読し、矛盾を感じたら DESIGN.md を優先してください。既存の設計制約（AppKit キャンバス、画像ピクセル座標系、スナップショット Undo、画面/書き出し同一レンダラ、`commitPendingTextEditing` フック）は**一切変えない**こと。

## 機能: 図形注釈3種

### 1. モデル

- `ShapeKind`（rectangle / roundedRectangle / ellipse）と `ShapeAnnotation`（id, kind, rect, color, lineWidth=12）を §12 のとおり新設。`rect` は画像ピクセル座標で常に正規化（幅・高さ正）
- `AnnotationItem` に `.shape` ケースを追加し、`frame` get/set・`translate`・`duplicated(offset:)`・`hitTest` を実装。これにより既存のコピー/ペースト/Cmd+D/alt ドラッグ複製が図形にもそのまま効くこと（受け入れ条件）
- `Tool` に rectangle / roundedRectangle / ellipse を追加

### 2. 描画（AnnotationRenderer）

- 矢印と同じ白フチ2重ストローク: 同一パスを 白 `lineWidth+4` → `color` `lineWidth` の順でストローク。塗りなし
- 角丸半径は描画時に `min(rect短辺 * 0.2, 32)` を計算（モデルに保存しない）
- パス構築は画像ピクセル座標のまま（座標変換を足さない）

### 3. ヒットテスト（重要）

- **枠線のみヒット、内部は不感**。`CGPath` を作り `copy(strokingWithWidth: max(lineWidth * 2, 20), lineCap: .round, lineJoin: .round, miterLimit: 10)` の `contains(point)` で判定
- 受け入れ条件: 大きな矩形の中央クリックでは選択されず、枠線上（±10px 程度）でのみ選択される

### 4. 操作（CanvasView / ContentView）

- ツール Picker を6種に拡張（SF Symbols 目安: `rectangle` / `app` / `oval`）。固定幅 `.frame(width: 280)` は撤廃し自然幅にする
- 作成は矢印と同じドラッグ方式: mouseDown で始点、ドラッグで対角（正規化しつつ更新）、mouseUp で対角距離 4px 未満なら破棄、作成後は選択ツールへ自動遷移。既存の `clampedImagePoint` に乗せる
- 選択中の図形はテキストと同じ四隅ハンドル UI を出すが、意味は **rect の変形**（対角アンカー固定、ドラッグ中も正規化、Undo名「図形を変形」）。カーソルもテキストの四隅と同じ扱い
- 追加の Undo 名: 「図形を追加」

### 5. 色

- 簡易モードの共通カラーウェル: `commonAnnotationColor` / `setCommonAnnotationColor` に図形を組み込む（選択中の図形→その色、未選択→図形の新規デフォルトも共通色に追従）
- 詳細モード: InspectorView の「矢印」セクションを「矢印・図形」に改名し、同じ ColorPicker が選択中の図形にも適用されるようにする（`inspectorArrowColor` / `setArrowColor` を図形対応に一般化するか、別 setter を足すかは任せる。Undo名「図形色を変更」）

### 6. 既知バグの同時修正（§12 末尾）

- 選択ツールで注釈を **option クリックだけ**（ドラッグせず離す）すると同位置に見えない複製が残る。`CanvasView.mouseUp` で、alt 複製ドラッグの移動量がほぼゼロ（対角 4px 未満）の場合は複製を取り消し、Undo にも積まないこと（矢印の 4px 破棄と同じ発想）。受け入れ条件: option クリックだけでは annotations の数が増えない

## 検証

以下がすべて通ること:

```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Kakikomi.xcodeproj -scheme Kakikomi -configuration Debug build
```

既存テスト2本（コンパイルコマンドは `codex-fix-prompt.md` の検証節と同じ。**新規 Swift ファイルを追加した場合はリンク対象に追随させ、pbxproj にも登録すること**）:
- `Tests/main.swift`（レンダラ）
- `Tests/ViewModelUndo/main.swift`（Undo）

追加テスト:
- `Tests/ViewModelUndo/main.swift` に: 図形の `duplicated(offset:)`（新UUID・+16・他パラメータ保持）、図形の Codable roundtrip、`hitTest`（枠線上 true / 中央 false）、ペースト経由で図形が追加され Undo で戻ること
- `Tests/main.swift` に: 図形3種を含む注釈でレンダリングしてベース画像とピクセルが変わること。**視覚確認用 PNG（/tmp/KakikomiVisualTest.png）にも図形3種を追加**すること（レビューで目視する）

## やらないこと

- 塗りつぶし・線幅 UI・shift 制約（正方形/真円）などの拡張
- 既存アーキテクチャ・レンダラ方式の変更、外部ライブラリ、指示外リファクタリング
