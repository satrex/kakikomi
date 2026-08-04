# Codex 用修正プロンプト（v2.0 レビュー指摘）

以下をそのまま Codex に貼り付けて使う（/codex-cycle はヘッドレス実行する）。

---

macOS 画像注釈アプリ「Kakikomi」の v2 実装（未コミットの作業ツリー）に対するレビューで見つかった問題を修正してください。仕様は `DESIGN.md` §14。既存アーキテクチャは変えないこと。

## 必須修正

### 1.【重】モザイクが上下鏡映の位置に描画される

`Kakikomi/Services/AnnotationRenderer.swift` の `drawMosaic`。ピクセレート画像を描く際、コンテキストを `translate(0, imageHeight)` + `scale(1, -1)` で反転した後に **`rect` をそのまま** `context.draw(pixelated, in: rect)` に渡している。反転後の座標系ではトップレフト座標の rect は `y = imageHeight - rect.maxY` に置き換える必要があり、現状は上下鏡映の位置（`imageHeight - rect.minY - rect.height`）にモザイクが描かれる。rect が垂直中央にある場合だけ偶然一致するため、既存テスト（96×96 内の 16,16,64,64）では検出されなかった。視覚確認 PNG では rect(880, 240, 180, 50) のモザイクが y≈70 に現れることで確認済み。

修正: 描画先を `CGRect(x: rect.minX, y: imageHeight - rect.maxY, width: rect.width, height: rect.height)` にする（`imageHeight = CGFloat(image.height)`）。

**テストの強化（必須）**: `Tests/main.swift` のモザイクテストを上下非対称な rect（例: 96×96 内の `(16, 8, 64, 40)`）に変え、
- rect 内部のピクセル（例: (32, 12)）が元画像から変化していること
- **鏡映位置**のピクセル（例: (32, 80) — `imageHeight - y - h` 側）が元画像と一致したままであること
の両方を検証する。トップレフト座標系とピクセル配列の行対応に注意（rgbaPixels は行0が画像の下端になる点を既存テストの流儀に合わせて扱うこと）。

### 2.【中】スクリーンショットの解像度指定がない

`Kakikomi/Services/ScreenshotCaptureService.swift`。`SCScreenshotManager.captureImage` に既定の `SCStreamConfiguration()` を渡しているため、キャプチャが既定サイズ（1920×1080 等）に縮小・変形される恐れがある。

修正: `didUpdateWith filter` で `filter.contentRect` と `filter.pointPixelScale` から `configuration.width / height` を計算して設定し（`contentRect.size × pointPixelScale`）、`configuration.captureResolution = .best` も指定する。

### 3.【小】picker の後始末と再入ガード

同ファイル。`finish` で observer は remove しているが `SCContentSharingPicker.shared.isActive` を `false` に戻していない（システムの共有 UI 状態が残る恐れ）。また `captureImage()` が連続で呼ばれると `continuation` が上書きされ、先の呼び出しが永久に resume されない。

修正: `finish` で `isActive = false` にする。`captureImage()` 冒頭で進行中の `continuation` があれば新しい呼び出しを即 `nil` 返しで拒否する（または先行を キャンセル扱いで resume してから開始する。どちらでも良いが宙吊りを作らない）。

### 4.【メモ→小】画面取込ロジックの重複排除

`KakikomiApp.swift` と `ContentView.swift` に同一の取込 Task が重複している。`DocumentViewModel.importScreenshot()` として一本化し、両方から呼ぶ（破棄確認 → capture → openImage → エラー処理までを含む）。

## 検証

以下がすべて通ること（コマンドは `codex-v2-prompt.md` の検証節と同じ）:

- `xcodebuild ... build`
- レンダラテスト（強化後のモザイク非対称テストを含む）
- Undo テスト

## やらないこと

- 上記以外の変更、リファクタリング
