# Skitch代替 画像注釈ツール 設計書

作成日: 2026-08-03

## 1. ゴールと要件

Skitch（開発終了）をそっくり代替できる、macOSネイティブの画像書き込みツール。

| # | 要件 | 備考 |
|---|------|------|
| R1 | macネイティブアプリ、Mac App Store で公開 | Sandbox 必須 |
| R2 | 書き込んだ画像の保存先は「ピクチャ」フォルダ | 保存パネルなしで直接保存したい |
| R3 | 文字を書き込み、ドラッグで文字サイズを拡大縮小 | Skitch と同じ操作感（ハンドルドラッグ＝フォントサイズ変更） |
| R4 | 文字は縁取りでき、込み入った背景でも識別可能（**最重要**） | 塗り＋アウトラインの2パス描画 |

MVP スコープ（v1.0）:

- 画像を開く（ファイル / ドラッグ&ドロップ / クリップボードからペースト）
- テキスト注釈（移動・ドラッグ拡縮・再編集・色変更・縁取り）
- 矢印注釈（Skitch の看板機能。テキストと同じ選択/移動/拡縮の仕組みに乗る）
- Undo / Redo
- ピクチャへのワンクリック保存（PNG）、クリップボードへコピー、ドラッグで書き出し
- 別名保存（NSSavePanel、PNG/JPEG）

v2 以降（設計上は考慮するが実装しない）:

- 矩形・楕円・フリーハンド、蛍光ペン、モザイク（個人情報隠し）、トリミング
- スクリーンショット取り込み（ScreenCaptureKit — 画面収録権限が必要なので分離）

---

## 2. 技術スタック

| 項目 | 選定 | 理由 |
|------|------|------|
| 言語 | Swift 5.10+ | |
| 最低OS | macOS 14 (Sonoma) | SwiftUI の成熟度と市場カバレッジのバランス |
| UIシェル | SwiftUI（ウィンドウ、ツールバー、インスペクタ、設定） | 開発速度 |
| キャンバス | **AppKit カスタム NSView（NSViewRepresentable で埋め込み）+ Core Graphics 描画** | 下記 |
| 配布 | Mac App Store（App Sandbox 有効） | |

### キャンバスを SwiftUI でなく AppKit + Core Graphics にする理由

1. **縁取り文字**: SwiftUI の `Text` はストローク（縁取り）属性を描画できない。Core Graphics / NSAttributedString の 2 パス描画が必要（§6）。どのみち書き出し時は CGContext に描くので、画面描画と書き出しを同一コードにできる。
2. **ヒットテスト・ハンドル操作**: 選択ハンドルのドラッグ、カーソル形状の切替（NSCursor）、mouseDown/Dragged/Up の精密な制御は NSView が素直。
3. **テキストのその場編集**: ダブルクリックでキャンバス上に NSTextView（フィールドエディタ）を重ねて編集する Skitch 流の UX は AppKit でしか組めない。

SwiftUI は「外側」（ツールバー、色・フォントピッカー、環境設定、ウィンドウ管理）に専念させる。

---

## 3. アーキテクチャ

MVVM + 単方向データフロー。注釈は**すべて値型（struct）でベクターデータとして保持**し、書き出し時に初めてラスタライズする（非破壊編集）。

```
┌─────────────────────────────────────────────┐
│ SwiftUI App Shell                            │
│  ContentView / Toolbar / Inspector / Settings│
└──────────────┬──────────────────────────────┘
               │ @Observable
┌──────────────▼──────────────────────────────┐
│ DocumentViewModel                            │
│  - baseImage: CGImage                        │
│  - annotations: [Annotation]                 │
│  - selection, activeTool, textStyle          │
│  - undo/redo（スナップショット方式）           │
└──────┬──────────────────────┬───────────────┘
       │                      │
┌──────▼───────────┐  ┌───────▼───────────────┐
│ CanvasView       │  │ Services              │
│ (NSView)         │  │  - AnnotationRenderer │←描画ロジックを共有
│  マウス処理       │  │  - ImageExporter      │
│  画面描画         │  │  - PicturesSaver      │
│  テキスト編集     │  │  - PasteboardService  │
└──────────────────┘  └───────────────────────┘
```

### 座標系（重要な設計判断）

**注釈の座標・サイズはすべて「元画像のピクセル座標系」で保持する。**

- CanvasView は「画像→ビュー」のアフィン変換（fit + ズーム）を 1 つ持ち、描画とヒットテストの入口で変換するだけ。
- 書き出しは画像ピクセルサイズの CGContext にそのまま描けばよく、Retina/ズーム起因のズレが構造的に発生しない。
- フォントサイズもピクセル座標系で持つ（表示時に変換）。

---

## 4. データモデル

```swift
enum Tool { case select, text, arrow }

protocol Annotation: Identifiable, Codable {
    var id: UUID { get }
    var frame: CGRect { get set }        // 画像ピクセル座標
    func hitTest(_ p: CGPoint) -> Bool
    func draw(in ctx: CGContext)
}

struct TextAnnotation: Annotation {
    var id = UUID()
    var text: String
    var origin: CGPoint            // 左上（画像ピクセル座標）
    var fontSize: CGFloat          // 画像ピクセル単位
    var fontName: String           // 既定: "HiraginoSans-W7"（太めが視認性◎）
    var fillColor: CodableColor    // 既定: 白
    var outlineColor: CodableColor // 既定: ほぼ黒 (#1A1A1A)
    var outlineWidthRatio: CGFloat // フォントサイズ比。既定 0.12（§6）
    var shadowEnabled: Bool        // 既定 true（縁取りに加え薄い影で更に分離）
    // frame は attributedString のサイズから都度計算（computed）
}

struct ArrowAnnotation: Annotation {
    var id = UUID()
    var start: CGPoint
    var end: CGPoint
    var color: CodableColor        // 既定: Skitchピンク (#FF3B7B) or 赤
    var lineWidth: CGFloat         // 白の細い縁取り付きで描く（視認性）
}

struct AnnotationDocument: Codable {
    var annotations: [any Annotation]  // type-erased コンテナで Codable 化
}
```

- `CodableColor` は sRGB RGBA の struct（NSColor を直接 Codable にしない）。
- **Undo/Redo はスナップショット方式**: 操作確定（mouseUp / 編集確定）ごとに `annotations` 配列全体を UndoManager に登録。注釈は軽い値型なのでメモリコストは無視できる。差分方式より実装バグが桁違いに少ない。

---

## 5. キャンバスと操作（Skitch の操作感の再現）

### ツールと状態遷移

- **テキストツール**: キャンバスをクリック → その位置に空の TextAnnotation を作り即編集モード（NSTextView をオーバーレイ）。編集確定は Esc / 外側クリック。空文字なら注釈を破棄。
- **選択ツール**: クリックで選択（前面優先の逆順ヒットテスト）。ドラッグで移動。ダブルクリックで再編集。Delete で削除。
- 描画ツール使用直後は自動で選択状態にする（Skitch 同様、置いてすぐ動かせる）。

### 選択ハンドルとドラッグ拡縮（R3）

選択中の注釈にはバウンディングボックス＋四隅ハンドル（角丸の小円、直径はビュー座標で 10pt 固定）を表示。

**テキストのリサイズ＝フォントサイズ変更**（Skitch と同じ。枠だけ伸びて文字が伸びない、は絶対にやらない）:

```swift
// mouseDown 時に保持: 対角のアンカー点 anchor、元フォントサイズ f0、
// アンカーからマウスまでの初期距離 d0
// mouseDragged:
let d1 = hypot(p.x - anchor.x, p.y - anchor.y)
let scale = d1 / d0
annotation.fontSize = (f0 * scale).clamped(to: 8...400)
// origin はアンカー固定を保つよう再計算（拡縮の基準点が対角に張り付く）
```

- 縁取り幅は `outlineWidthRatio`（フォントサイズ比）なので**拡縮に自動追従**する。ここを絶対値にすると拡大時に縁が細く見えて R4 が破綻するため、比率保持は仕様として固定。
- 矢印は端点 2 つがそのままハンドル。

### カーソル

`NSTrackingArea` + `resetCursorRects` で、ハンドル上は斜め矢印、注釈上は openHand、テキストツール時は IBeam。

---

## 6. 縁取り文字の描画（R4・最重要）

### 方式: NSAttributedString の 2 パス描画

CGContext に対して同じ文字列を 2 回描く。

```swift
func drawOutlinedText(_ t: TextAnnotation, in ctx: CGContext) {
    let font = NSFont(name: t.fontName, size: t.fontSize)!

    // パス1: 縁取り（ストロークのみ）
    // .strokeWidth に正の値 → ストロークのみ描画。
    // 値は「フォントサイズに対する%」なので、拡縮に自然に追従する。
    let strokeAttrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .strokeColor: t.outlineColor.nsColor,
        .strokeWidth: t.outlineWidthRatio * 100,   // 例: 0.12 → 12(%)
    ]
    ctx.saveGState()
    ctx.setLineJoin(.round)   // "A" や "W" の尖りが刺々しくならないよう必須
    ctx.setLineCap(.round)
    if t.shadowEnabled {      // 縁取りの外側にさらに薄い影 → 白背景でも黒背景でも浮く
        ctx.setShadow(offset: .init(width: 0, height: -t.fontSize * 0.04),
                      blur: t.fontSize * 0.12,
                      color: NSColor.black.withAlphaComponent(0.5).cgColor)
    }
    NSAttributedString(string: t.text, attributes: strokeAttrs)
        .draw(at: t.origin)   // 実装では CTLine/CTFrame で ctx に直接描く
    ctx.restoreGState()

    // パス2: 塗り（縁の上に重ねるので、塗りが縁に侵食されない）
    let fillAttrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: t.fillColor.nsColor,
    ]
    NSAttributedString(string: t.text, attributes: fillAttrs).draw(at: t.origin)
}
```

設計上のポイント:

- **2 パスにする理由**: `.strokeWidth` に負値を渡す 1 パス方式（塗り＋縁）はストロークがグリフ輪郭の中心に乗るため、縁が文字の内側を侵食して細い文字が痩せる。「縁のみ→塗り」の順で重ねると塗りが常にフルに残り、太い縁でも可読性が落ちない。
- **既定スタイル＝白文字＋濃灰縁＋薄影**。どんな背景（明・暗・高周波なスクリーンショット）でも成立する組合せで、Skitch の既定と同じ思想。カラーピッカーで塗りを変えても縁と影が分離を保証する。
- **フォント既定はヒラギノ角ゴ W7**（日本語ユーザー前提）。細いウェイトは縁取りしても潰れるため、UI 上もウェイト選択は W6 以上のみ提示。
- 描画コードは `AnnotationRenderer` に集約し、**画面表示と書き出しで完全に同一コードを使う**（WYSIWYG 保証）。

---

## 7. 保存・書き出し

### ピクチャへの直接保存（R2）

Sandbox 下でも entitlement でピクチャフォルダへ保存パネルなしにアクセスできる:

```xml
<!-- Kakikomi.entitlements -->
<key>com.apple.security.app-sandbox</key><true/>
<key>com.apple.security.assets.pictures.read-write</key><true/>
<key>com.apple.security.files.user-selected.read-write</key><true/>
```

- `FileManager.default.urls(for: .picturesDirectory, ...)` で取得したフォルダに直接書き込み。
- ファイル名: `注釈 2026-08-03 15.04.30.png`（Skitch/スクリーンショット風、衝突時は連番）。
- App Review 対策: ピクチャ entitlement は「画像編集アプリの保存先」という自明な用途なので通常問題ないが、Review ノートに一文添える。
- 任意の場所への保存は `user-selected` + NSSavePanel（別名保存メニュー）。

### 書き出しパイプライン

```
CGContext(width: image.width, height: image.height)  // 元画像のピクセルサイズ
  → 元画像を描画
  → annotations を順に draw(in:)   // 座標系が同一なので変換不要
  → makeImage() → CGImageDestination で PNG/JPEG 書き出し
```

- クリップボードコピー: 同じ CGImage を NSPasteboard へ（Slack 等へ即ペーストする Skitch の主要ユースケース）。
- ウィンドウ下部に Skitch 名物の**ドラッグタブ**を置き、そこから Finder/Slack へ直接ドラッグで書き出し（`NSDraggingSource` で一時ファイルの file promise を提供）。

---

## 8. プロジェクト構成

```
Kakikomi/
├── KakikomiApp.swift          // @main, WindowGroup, Commands(メニュー)
├── Models/
│   ├── Annotation.swift          // protocol + type-erasure
│   ├── TextAnnotation.swift
│   ├── ArrowAnnotation.swift
│   └── CodableColor.swift
├── ViewModels/
│   └── DocumentViewModel.swift   // @Observable, undo, tool state
├── Views/
│   ├── ContentView.swift         // ツールバー + キャンバス + ドラッグタブ
│   ├── CanvasView.swift          // NSView: 描画・マウス・ハンドル
│   ├── CanvasRepresentable.swift
│   ├── TextEditingOverlay.swift  // NSTextView によるその場編集
│   └── InspectorView.swift       // 色・フォント・縁取り幅
├── Services/
│   ├── AnnotationRenderer.swift  // 画面/書き出し共通の描画
│   ├── ImageExporter.swift
│   ├── PicturesSaver.swift
│   └── PasteboardService.swift
└── Kakikomi.entitlements
```

---

## 9. マイルストーン

| M | 内容 | 完了条件 |
|---|------|---------|
| M1 | Xcodeプロジェクト、画像を開く（D&D/ペースト/ファイル）、fit表示 | 画像が正しく表示される |
| M2 | テキスト注釈: 配置・編集・移動・**縁取り描画** | 込み入った背景で読めることを目視確認 |
| M3 | 選択ハンドル・**ドラッグ拡縮**・Undo/Redo | 拡縮で縁取り比率が保たれる |
| M4 | 矢印注釈 | |
| M5 | ピクチャ保存・クリップボード・ドラッグタブ書き出し | Sandbox有効ビルドで保存成功 |
| M6 | インスペクタ（色/フォント/縁幅）、設定、アイコン | |
| M7 | App Store 提出準備（スクショ、審査ノート、公証） | |

---

## 10. UI 改訂 v1.1: 簡易モード / オブジェクトコピー

「思い付いたら最速で書き込める」ための改訂。2026-08-04 打ち合わせで確定。

### 簡易モード（デフォルト）と詳細モード

- 起動時は**簡易モード**。右端のトグルで**詳細モード**（現行 UI = サイドインスペクタ）へ切替。選択は `@AppStorage` で記憶
- 簡易モードはサイドパネルなし。上部ツールバーに全部品を集約（プレビュー.app のマークアップ風）:
  `開く | ペースト | 選択/テキスト/矢印 | 共通カラーウェル | ピクチャに保存 | 詳細切替`
  下部ドラッグタブは両モード共通で残す
- **共通カラーウェルひとつ**が文字色と矢印色を兼ねる。選択中の注釈があればそれへ適用、なければ新規注釈のデフォルトに（現行インスペクタと同じ意味論）。初期値は `accentPink`
- **縁取り色は自動**: 文字色の相対輝度 L = 0.2126R + 0.7152G + 0.0722B が 0.5 超なら `darkOutline`、以下なら白。**色変更時に計算して従来フィールドに保存**する方式（レンダラ・詳細モード・既存注釈は無変更で済む）
- 簡易モードの新規テキストは **W7 固定**・縁取り比 0.12・影あり（R4 の判読性を優先し、ウェイト選択 UI は詳細モードのみ）
- モード切替自体は既存注釈を一切変更しない・Undo 対象外

### オブジェクトのコピー / ペースト / 複製

- コピーはカスタム pasteboard 型 `jp.satrex.kakikomi.annotation` に AnnotationItem の **Codable JSON** を載せる（モデルが最初から Codable なのを利用）
- **Cmd+C**: 選択注釈があればオブジェクトをコピー、なければ従来どおり結果画像をコピー
- **Cmd+V**: pasteboard に注釈型があればオブジェクトをペースト（新 UUID・+16px オフセット・ペースト後は選択状態）、なければ従来どおり画像を開く。連続ペーストで重ならないようオフセットを継ぐ
- **Cmd+D**: 選択注釈を複製（+16px）
- **alt（option）ドラッグ**: 選択ツールで注釈を option ドラッグすると複製を作りそのままドラッグ（mouseDown 時に判定）
- テキスト編集中の Cmd+C/V はメニューに食わせず編集側へ委譲（Cmd+Z と同じ firstResponder 判定パターン）
- いずれもスナップショット Undo に乗せる（「ペースト」「複製」）

---

## 11. 主なリスクと対策

| リスク | 対策 |
|--------|------|
| `.strokeWidth` 描画がフォント・サイズによって粗く見える | 縁が太い設定では CTFont → CGPath 化して `strokePath` する代替実装を Renderer 内に隠蔽（インタフェース不変） |
| Sandbox でピクチャ保存が審査で問われる | entitlement の用途をレビューノートに明記。拒否された場合は初回のみ NSOpenPanel でピクチャを選ばせ security-scoped bookmark を保存する方式へフォールバック |
| 巨大画像（例: 5K スクショ）での描画性能 | 表示用にダウンサンプルした CGImage をキャッシュ、書き出しのみ原寸。注釈は毎フレーム描いても軽い |
