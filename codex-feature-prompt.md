# Codex 用実装プロンプト（v1.1: 簡易モード + オブジェクトコピー）

以下をそのまま Codex に貼り付けて使う。

---

macOS 画像注釈アプリ「Kakikomi」に2機能を追加してください。仕様はリポジトリ直下 `DESIGN.md` の **§10「UI 改訂 v1.1」** に確定済みです。まず §10 を熟読し、既存の設計制約（AppKit キャンバス、2パス縁取り描画、画像ピクセル座標系、スナップショット Undo、画面/書き出し同一レンダラ）を**一切変えずに**実装してください。

## 機能A: 簡易モード（デフォルト）/ 詳細モード切替

- `@AppStorage("uiMode")` でモードを永続化。初回起動は簡易モード
- **簡易モード**: `InspectorView`（サイドパネル）を非表示にし、上部ツールバーへ集約:
  `開く | ペースト | ツール3種(既存Picker) | 共通カラーウェル | ピクチャに保存 | 詳細切替トグル`
  下部のドラッグタブ+ステータス行は両モード共通で残す
- **詳細モード**: 現行 UI そのまま（サイドインスペクタ表示）。切替トグルは両モードで同じ位置（ツールバー右端、SF Symbol は `slider.horizontal.3` など）
- **共通カラーウェル**: 1つの色を文字色と矢印色の両方に適用する
  - 選択中の注釈があればその注釈へ適用（テキストなら fill、矢印なら color）、なければ新規注釈用デフォルト（既存インスペクタと同じ「選択中 or デフォルト」意味論。`DocumentViewModel` に共通色用の setter を追加し、既存の `setTextFillColor` / `setArrowColor` を内部で呼ぶ形でよい）
  - 初期値は `CodableColor.accentPink`
- **縁取り色の自動決定**: 簡易モードで色を設定した際、相対輝度 `L = 0.2126*red + 0.7152*green + 0.0722*blue` を計算し、`L > 0.5` なら `CodableColor.darkOutline`、それ以外なら白をテキストの `outlineColor` に**保存**する（レンダラは変更しない）。詳細モードの縁取り色ピッカーは従来どおり自由指定
- 簡易モードで作る新規テキストは W7・縁取り比 0.12・影あり（= 現行デフォルトのまま。簡易モードにウェイト/縁幅の UI は置かない）
- モード切替は既存注釈を変更せず、Undo スタックにも積まない
- 色変更の Undo は既存の `updateSelectedText` / `setArrowColor` と同じスナップショット方式に乗せる

## 機能B: 注釈オブジェクトのコピー / ペースト / 複製

- カスタム pasteboard 型 `jp.satrex.kakikomi.annotation`（`NSPasteboard.PasteboardType`）に、選択中 `AnnotationItem` を `JSONEncoder` でエンコードして載せる（モデルは Codable 済み）
- **Cmd+C**（`KakikomiApp` のメニュー）:
  1. firstResponder が NSTextView（テキスト編集中）→ そのテキストビューの `copy(_:)` に委譲（既存 `performUndoCommand` と同じパターン）
  2. 選択中の注釈あり → オブジェクトをコピー
  3. それ以外 → 従来どおり結果画像をコピー（`copyResultToPasteboard`）
- **Cmd+V**:
  1. テキスト編集中 → テキストビューの `paste(_:)` に委譲
  2. pasteboard に `jp.satrex.kakikomi.annotation` あり → デコードして **新 UUID を採番**し、`origin`（矢印は start/end とも）を +16px オフセットして `annotations` に追加、ペースト後は選択状態にする。画像未読込時は何もしない。連続ペーストで完全に重ならないようオフセットを継ぐこと（方式は任せる。例: 直近ペースト位置を覚えて +16 ずつ）
  3. それ以外 → 従来どおりクリップボードから画像を開く
- **Cmd+D**: 選択中の注釈を複製（+16px、新 UUID、複製側を選択）。メニュー「編集」に「複製」として追加
- **alt（option）ドラッグ複製**: `CanvasView.mouseDown`（select ツール）で、注釈本体のヒット時に `event.modifierFlags.contains(.option)` なら複製を作って annotations に追加し、**複製側**を選択してそのままドラッグさせる（ハンドル上の option クリックはリサイズ優先で従来どおり）
- Undo: ペースト「ペースト」、複製「複製」、alt ドラッグ「複製」でスナップショット登録。alt ドラッグは既存の移動と同様 mouseUp で1回だけ登録（ドラッグ開始前の配列を before として使えば追加+移動が1エントリで戻る）
- ペースト/複製の座標が画像外へ大きく出る場合、origin が画像内に収まる程度にクランプ（厳密でなくてよい）

## 実装上の注意

- 新 UUID の採番は `AnnotationItem` に `func duplicated(offset: CGSize) -> AnnotationItem` のようなメソッドを生やすと、ペースト/Cmd+D/alt ドラッグの3経路で共有できる
- `ContentView` の分岐が肥大するようなら、ツールバー部分をサブビューに切り出してよい（アーキテクチャ変更はしない）
- 保存/コピー前の `commitPendingTextEditing` フック呼び出しは既存のまま維持すること

## 検証

修正後、以下がすべて通ること:

```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Kakikomi.xcodeproj -scheme Kakikomi -configuration Debug build
```

既存テスト（コンパイル・実行コマンドは `codex-fix-prompt.md` の検証節と同じ）:
- `Tests/main.swift`（レンダラ）
- `Tests/ViewModelUndo/main.swift`（Undo）

追加テスト（`Tests/ViewModelUndo/main.swift` の様式で。UI を伴わない ViewModel/モデルレベルでよい）:
- 輝度自動判定: 白→`darkOutline`、黒→白、`accentPink`→白 になること
- `duplicated(offset:)`: 新 UUID が採番され、テキスト/矢印とも座標が +16 され、他パラメータが等しいこと
- JSON 経由のペースト相当処理: エンコード→デコード→複製追加で annotations が増え、Undo で戻ること

## やらないこと

- 既存アーキテクチャの変更、レンダラの変更、外部ライブラリの導入
- v2 機能（矩形・モザイク等）の追加
- 上記以外のリファクタリング
