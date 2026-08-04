# Codex 用実装プロンプト（v2.0: モザイク / トリミング / スクリーンショット取り込み）

以下をそのまま Codex に貼り付けて使う（/codex-cycle はヘッドレス実行する）。

---

macOS 画像注釈アプリ「Kakikomi」に v2 機能3点を追加してください。仕様はリポジトリ直下 `DESIGN.md` の **§14「v2 機能」** に確定済みです。まず §14 を熟読し、矛盾を感じたら DESIGN.md を優先してください。既存の設計制約（AppKit キャンバス、画像ピクセル座標系、画面/書き出し同一レンダラ、`commitPendingTextEditing` フック、外部ライブラリ禁止 — Apple 標準フレームワークは可）は一切変えないこと。

## 機能A: モザイク注釈

- `MosaicAnnotation { id, rect, blockSize = 16 }` を新設し `AnnotationItem.mosaic` に統合（frame/hitTest/translate/duplicated 全対応 — コピー/ペースト/Cmd+D/alt ドラッグが自動で効くこと）
- **描画順の特別扱い**: `AnnotationRenderer` のトップレベル draw で「元画像 → モザイク全部 → その他の注釈（配列順）」に分配する。モザイクの上に矢印・文字・図形が常に描かれること（受け入れ条件）
- 描画は純 CG のピクセレート: 元画像から rect を `cropping(to:)` → `rect.size/blockSize` の小コンテキストへ縮小 → `interpolationQuality = .none` で元サイズへ拡大描画。rect が画像からはみ出す場合は交差部分のみ処理
- ヒットテストは **rect 内部全体**（図形と逆。塗り領域のため）。リサイズは図形と同じ四隅ハンドル方式（Undo名「モザイクを変形」、作成は「モザイクを追加」）
- 作成 UX は図形と同じドラッグ描画（4px 未満破棄 → 選択ツールへ）
- 色フロー（共通色・インスペクタ）ではモザイクを無視（no-op、デフォルト変更にも使わない）
- ツール追加。SF Symbol は `checkerboard.rectangle` 目安

## 機能B: トリミング（クロップ）

- クロップは注釈ではなく baseImage の破壊的変更。`DocumentViewModel.crop(to rect: CGRect)` を新設:
  - rect を画像内にクランプ、幅高 4px 未満は無視
  - `CGImage.cropping(to:)` で新 baseImage、全注釈を `-rect.origin` translate（画像外に出ても削除しない）
  - **複合スナップショット Undo**: (旧 baseImage, 旧 annotations) を登録し undo/redo で両方復元。既存 `restoreSnapshot` と同じ再登録パターンで対称に。Undo名「切り抜き」
- ツール「切り抜き」: ドラッグ中は破線のマーキー矩形をビュー座標で描画（注釈は作らない。CanvasView にドラッグ状態を持つ）。mouseUp で即 `crop(to:)` 適用 → 選択ツールへ。確認ダイアログは出さない
- クロップ直後の描画・ヒットテスト・書き出しが新座標系で一貫すること（受け入れ条件: クロップ後に保存した PNG のサイズが rect と一致し、注釈位置がずれない）

## 機能C: スクリーンショット取り込み

- 新規 `Kakikomi/Services/ScreenshotCaptureService.swift`。**ScreenCaptureKit の `SCContentSharingPicker`（macOS 14+）** でウィンドウ/画面を選ばせ、得られた `SCContentFilter` を `SCScreenshotManager.captureImage(contentFilter:configuration:)` に渡して CGImage を取得する。配置は既存 Services と同様に static ベースでよいが、picker の observer 保持など必要な状態は持ってよい
- **画面収録権限の事前許可フローを実装しない**こと（picker 方式は不要のはず）。`CGWindowListCreateImage` 等の非推奨 API は使わない
- 取得した CGImage は `openImage` と同じ初期化経路で新しい baseImage として開く（注釈クリア・Undo クリア・ペーストカスケードリセット）
- **破棄確認の共通ガード**: 注釈が1つ以上ある状態で「スクリーンショット取込」または「クリップボードから開く」を実行したら、`NSAlert` で「現在の書き込みを破棄して新しい画像を開きますか?」を確認（キャンセルで中断）。ViewModel に共通ヘルパを作り両経路で使う
- UI: ツールバーに「画面取込」ボタン（簡易/詳細 両モード共通、SF Symbol `camera.viewfinder` 目安）+ ファイルメニューに項目（ショートカットは Cmd+Shift+N）
- キャプチャは非同期。完了時は MainActor で反映。ユーザーキャンセルは無言、エラーは `lastErrorMessage`
- ScreenCaptureKit のフレームワークリンクが必要なら pbxproj に追加する

## 検証

以下がすべて通ること:

```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Kakikomi.xcodeproj -scheme Kakikomi -configuration Debug build
```

（サンドボックスで既定 DerivedData に書けない場合は `-derivedDataPath /tmp/KakikomiDerivedData` を付けてよい）

既存テスト2本（コンパイルコマンドは `codex-fix-prompt.md` の検証節と同じ + `Kakikomi/Services/DragExportService.swift` をリンク。**ScreenshotCaptureService はテストにリンクしない**でよい — GUI 前提のため。リンクが必要になる構造にしないこと）:
- `Tests/main.swift`（レンダラ）
- `Tests/ViewModelUndo/main.swift`（Undo）

追加テスト:
- `Tests/main.swift` に: モザイクを含む描画で対象領域のピクセルが変化し、**同一ブロック内の隣接ピクセルが同色**になること（ピクセレートの実証）。モザイクの上に置いたテキストが潰れないこと（モザイク領域内に文字を描き、その位置のピクセルがモザイク単色と異なること）。視覚確認用 PNG（/tmp/KakikomiVisualTest.png）にモザイク領域を追加
- `Tests/ViewModelUndo/main.swift` に: モザイクの duplicated/Codable roundtrip、`crop(to:)` で画像サイズ・注釈座標が正しく変わり Undo で画像と注釈の両方が復元されること、破棄確認ガードのロジック部分（アラート表示は関数注入等で分離してテスト可能にする）

## やらないこと

- 範囲指定スクリーンショット（OS 標準に委ねる）、blockSize/クロップ比率の UI
- 既存アーキテクチャ・レンダラ方式の変更、外部ライブラリ、指示外リファクタリング
