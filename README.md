# Kakikomi（カキコミ）

macOS ネイティブの画像書き込み（注釈）ツール。Skitch（開発終了）の代替を目指しています。

## 特徴

- **縁取り文字** — 塗り＋アウトラインの2パス描画で、込み入った背景のスクリーンショットでも文字がはっきり読める
- **ドラッグでサイズ変更** — 四隅ハンドルのドラッグで文字サイズそのものを拡大縮小（Skitch と同じ操作感）
- **矢印注釈** — 端点ドラッグで編集可能
- **ワンクリック保存** — ピクチャフォルダへ直接 PNG 保存（App Sandbox 対応）
- クリップボードコピー / ドラッグでの書き出し / Undo・Redo

## 動作環境

- macOS 14 (Sonoma) 以降
- Mac App Store での公開を想定（App Sandbox 有効）

## ビルド

```
xcodebuild -project Kakikomi.xcodeproj -scheme Kakikomi build
```

## サポート / プライバシーポリシー

- https://kakikomi.satrex.jp/
- https://kakikomi.satrex.jp/privacy.html

## ドキュメント

- [DESIGN.md](DESIGN.md) — 設計書（アーキテクチャ、描画方式、座標系の設計判断）
- [codex-prompt.md](codex-prompt.md) — 実装時に使用したプロンプト
- [AppReviewNotes.md](AppReviewNotes.md) — App Store 審査用メモ
- [AppStoreListing.md](AppStoreListing.md) — App Store 掲載情報の下書き
