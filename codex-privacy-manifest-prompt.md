# Codex 用実装プロンプト（v2.0.2: プライバシーマニフェスト）

以下をそのまま Codex に貼り付けて使う（/codex-cycle はヘッドレス実行する）。

---

macOS 画像注釈アプリ「Kakikomi」に Privacy Manifest を追加してください。背景はリポジトリ直下 `DESIGN.md` の **§16「App Store 提出準備 v2.0.2」** に記載済みです。まず §16 を熟読してください。

## 背景

`Kakikomi/Views/ContentView.swift` で `@AppStorage("uiMode")` を使用しており、これは内部で `UserDefaults` を使う。Apple は 2024年以降、"Required Reason API"（User Defaults APIs を含む）を使うアプリに `PrivacyInfo.xcprivacy` の同梱を求めており、無いと App Store Connect のアップロード検証でエラーになり得る。

## 修正

- `Kakikomi/PrivacyInfo.xcprivacy` を新規作成する。内容は Apple の Privacy Manifest 形式（`NSPrivacyTracking` = false、`NSPrivacyTrackingDomains` = 空配列、`NSPrivacyCollectedDataTypes` = 空配列、`NSPrivacyAccessedAPITypes` に User Defaults APIs のエントリを1つ、理由コードは `CA92.1`）
- この Kakikomi アプリは UserDefaults を自アプリ専用の設定（`uiMode` の1キーのみ）にしか使っておらず、他アプリとの共有や外部送信は一切行っていない。理由コードは「自アプリ専用データへのアクセス」を表す `CA92.1` を使うこと（Apple の公開ドキュメントに基づく標準的な理由コード。念のため提出前に Apple の最新の Privacy Manifest ドキュメントと照合するようコメントで一言添えてよい）
- 新規ファイルを `Kakikomi.xcodeproj/project.pbxproj` の Resources ビルドフェーズに正しく組み込む（他の非 Swift リソース、例えば `Kakikomi/Assets/Kakikomi.icns` と同様の扱い）
- 既存の設計制約（AppKit キャンバス、画像ピクセル座標系、画面/書き出し同一レンダラ、外部ライブラリ禁止）には影響しない変更のはずだが、念のため一切変えないこと

## 検証

以下が通ること:

```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Kakikomi.xcodeproj -scheme Kakikomi -configuration Debug build
```

ビルド成果物 `.app/Contents/Resources/PrivacyInfo.xcprivacy` が実際に生成されることを、ビルド後に `find` 等で確認すること（コマンドと結果を報告に含める）。

既存テスト2本（コンパイルコマンドは `codex-fix-prompt.md` の検証節と同じ + `Kakikomi/Services/DragExportService.swift` をリンク）が壊れていないこと:
- `Tests/main.swift`
- `Tests/ViewModelUndo/main.swift`

新規テストは不要（plist リソースの追加のみのため）。

## やらないこと

- UserDefaults の使い方自体の変更（`@AppStorage` はそのまま）
- 既存アーキテクチャ・レンダラ・ViewModel・View の変更
- 外部ライブラリの追加
