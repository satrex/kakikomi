# Codex 用修正プロンプト（Release ビルドの dSYM 生成を有効化）

以下をそのまま Codex に貼り付けて使う（/codex-cycle はヘッドレス実行する）。

---

macOS アプリ「Kakikomi」の Xcode プロジェクトで、App Store Connect へのアップロード時に次の警告が出ています。

```
The archive did not include a dSYM for the Kakikomi.app with the UUIDs [...].
Ensure that the archive's dSYM folder includes a DWARF file for Kakikomi.app with the expected UUIDs.
```

## 原因

`Kakikomi.xcodeproj/project.pbxproj` はハンドオーサリング（Xcode のプロジェクト作成ウィザードを通していない）で、Release ビルド構成に `DEBUG_INFORMATION_FORMAT` が一切設定されていない。Xcode のテンプレートが自動で入れる `dwarf-with-dsym`（Release）が欠けているため、Archive で dSYM が生成されていない。

## 修正

`Kakikomi.xcodeproj/project.pbxproj` のターゲット `Kakikomi` の **Release** ビルド構成（`buildSettings` 内、`CODE_SIGN_ENTITLEMENTS` 等が並んでいるブロック、`name = Release;` の方）にのみ、次の1行を追加する:

```
DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
```

Debug 構成は変更しない（Debug は dSYM 不要、ビルド時間短縮のため現状の `dwarf` 相当のままでよい）。プロジェクトレベルの Build configuration list（`buildSettings` が `CLANG_ENABLE_MODULES` 等の少数キーだけのブロック）には触れず、ターゲットレベルの Release 構成にのみ追加すること。

他の設定・ファイル・Swift コードは一切変更しないこと。

## 検証

```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Kakikomi.xcodeproj -scheme Kakikomi -configuration Release archive -archivePath /tmp/Kakikomi-verify.xcarchive
```

上記が成功し、`/tmp/Kakikomi-verify.xcarchive/dSYMs/Kakikomi.app.dSYM` が実際に生成されることを `find /tmp/Kakikomi-verify.xcarchive/dSYMs -name "*.dSYM"` 等で確認して報告に含めること。

続けて、既存の Debug ビルドとテスト2本が壊れていないことも確認すること:

```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Kakikomi.xcodeproj -scheme Kakikomi -configuration Debug build
```

（コンパイルコマンドは `codex-fix-prompt.md` の検証節と同じ2本、`Tests/main.swift` と `Tests/ViewModelUndo/main.swift`）

## やらないこと

- DEBUG_INFORMATION_FORMAT 以外の設定変更
- Swift コード・entitlements・Info.plist の変更
