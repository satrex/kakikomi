---
name: codex-cycle
description: 設計確定後にCodex用実装プロンプトを生成し、実装結果を受けて差分レビューまで行う一連のワークフロー。「Codexに投げて」「実装プロンプトを書いて」「プロンプト出して」と言われたら必ず使うこと。また「修正完了」「出力上がってきた」「実装できた」など実装結果の報告を受けてレビューする場面、仕様の打ち合わせが終わって実装フェーズへ移る場面でも必ず使うこと。コードの実装・修正そのものを頼まれた場合も、直接編集せずこのスキルでプロンプトを作る。
---

# Codex 実装サイクル

このプロジェクトの分担: **実装は Codex、Claude は設計・プロンプト作成・レビュー**。
Claude のトークンは抽象度の高い仕事（設計判断・制約の言語化・検証）に使う。
アプリコードを直接 Edit/Write しないこと（DESIGN.md とプロンプトファイルは Claude が書く）。

## フェーズ判定

- 仕様が固まりプロンプトが必要 → フェーズ1へ
- ユーザーが実装完了を報告した、または `git status` に未レビューの変更がある → フェーズ3へ

## フェーズ1: プロンプト生成

1. 会話で決まった仕様が DESIGN.md に未反映なら、**先に DESIGN.md へ節を追記する**。
   仕様の一次ソースは常に DESIGN.md であり、プロンプトには要点のみ再掲して
   詳細は該当節を参照させる（二重管理を避ける）。
2. `codex-<topic>-prompt.md` をリポジトリ直下に作成する。構成は既存の
   `codex-prompt.md` / `codex-fix-prompt.md` / `codex-feature-prompt.md` を踏襲:
   - 冒頭に「以下をそのまま Codex に貼り付けて使う」+ `---` 区切り
   - DESIGN.md の該当節を熟読させ、矛盾時は DESIGN.md 優先と明記
   - 各項目: 現状の問題/目的 → 修正方針（実装の自由度は残す）→ 受け入れ条件
   - 設計制約を「違反しないこと」として明示列挙（下記「不変制約」から関連するもの）
   - 検証節: 下記のビルド・テストコマンドを完全な形で記載し、
     回帰テストの追加も指示する（`Tests/ViewModelUndo/main.swift` の様式）
   - 「やらないこと」節でスコープ膨張を防ぐ（アーキテクチャ変更・外部ライブラリ・
     指示外リファクタリングは常に禁止）

## フェーズ2: Codex 実行

1. `codex --version` で CLI の動作を確認する（Homebrew cask 版がインストール済み、
   認証は ChatGPT ログイン）。
2. 動く場合: ユーザーに確認のうえプロンプトファイルの `---` 以下を
   `codex exec` に渡してヘッドレス実行し、完了後フェーズ3へ直行する。
   実行例（フラグは `codex exec --help` で都度確認）:
   ```
   awk '/^---$/{found=1; next} found' codex-<topic>-prompt.md | codex exec -
   ```
3. 動かない場合: プロンプトファイルの場所と「`---` 以下を貼り付けて使う」ことを
   案内してターンを終える。ユーザーの完了報告を受けたらフェーズ3へ。
   （過去事例: npm 版はバイナリが Gatekeeper に隔離されて壊れた。
   再発時は Homebrew cask で入れ直す）

## フェーズ3: 差分レビュー

1. `git status --short && git diff --stat` で全体像を掴み、`git diff` 全文を読む。
   直前コミットが Codex の成果の場合は `git show` でそのコミットを読む。
2. 対応するプロンプトの受け入れ条件・チェックリストと、下記「不変制約」に照らして
   1件ずつ検証する。差分に現れない波及先（呼び出し元、再入、Undo、座標系）も読む。
3. ビルド確認（xcode-select が CLT を指しているため DEVELOPER_DIR 必須）:
   ```
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Kakikomi.xcodeproj -scheme Kakikomi -configuration Debug build
   ```
4. テスト実行（スクラッチディレクトリに出力し、2本とも走らせる）:
   ```
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swiftc -o <scratch>/renderer_test \
     Tests/main.swift \
     Kakikomi/Models/Annotation.swift Kakikomi/Models/TextAnnotation.swift \
     Kakikomi/Models/ArrowAnnotation.swift Kakikomi/Models/CodableColor.swift \
     Kakikomi/Services/AnnotationRenderer.swift Kakikomi/Services/ImageExporter.swift \
     && <scratch>/renderer_test
   ```
   ```
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swiftc -o <scratch>/undo_test \
     Tests/ViewModelUndo/main.swift \
     Kakikomi/Models/Annotation.swift Kakikomi/Models/TextAnnotation.swift \
     Kakikomi/Models/ArrowAnnotation.swift Kakikomi/Models/CodableColor.swift \
     Kakikomi/Services/AnnotationRenderer.swift Kakikomi/Services/ImageExporter.swift \
     Kakikomi/Services/PicturesSaver.swift Kakikomi/Services/PasteboardService.swift \
     Kakikomi/ViewModels/DocumentViewModel.swift \
     && <scratch>/undo_test
   ```
   （テスト対象ファイルが増えたらリンク対象も追随させる）
5. レンダラや注釈の見た目に触れる変更なら、renderer_test が出力する
   `/tmp/KakikomiVisualTest.png` を Read で目視し、白背景・黒背景・模様背景の
   3パターンで縁取り文字が判読できることを確認する。
6. 結果を報告する: 冒頭に承認可否の結論 → 各修正の確認結果 → 指摘を重要度順
   （【中】【小】【メモ】）に、`ファイル:行` 参照付きで。問題があればフェーズ1に
   戻り修正プロンプト（`codex-fix-prompt` 形式）を生成する。
7. コミットはユーザーの指示があったときのみ。メッセージは日本語+
   `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>` を付ける。

## 不変制約（レビュー観点の要約 — 正典は DESIGN.md）

- キャンバスは AppKit NSView + Core Graphics（SwiftUI Canvas/Text で注釈を描かない)
- 縁取りは2パス描画（縁のみ→塗り、負の strokeWidth 禁止、lineJoin/lineCap round）
- 縁取り幅はフォントサイズ比で保持（絶対値 pt 禁止）
- 注釈の座標・フォントサイズは元画像のピクセル座標系
- 画面表示と書き出しは同一の AnnotationRenderer を通す（WYSIWYG 保証）
- テキストのハンドルドラッグは枠リサイズではなくフォントサイズ変更
- Undo はスナップショット方式（差分方式にしない）
- Sandbox 有効。ピクチャは `com.apple.security.assets.pictures.read-write`
  （`files.pictures` は実在しないキー。復活させない）
- 保存・コピー・書き出しの前に `commitPendingTextEditing` フックを呼ぶ
- 外部ライブラリ禁止（標準フレームワークのみ）
