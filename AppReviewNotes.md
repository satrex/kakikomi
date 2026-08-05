# App Review Notes（審査用メモ）

App Store Connect の「App Review Information」→「Notes」欄に、下記の「---」以降（英語本文）をそのまま貼り付けてください。Apple の審査担当者は英語を前提に読むため、本文は英語で書いています。

提出前に確認・埋めるべき箇所:
- `[CONTACT EMAIL]` — 審査担当者からの連絡先（info@satrex.jp を想定）
- デモ用の手順は現在の UI（v2.0.1 時点、簡易モードがデフォルト）に合わせて書いてあります。UI を変更した場合はこの文書も更新してください

---

Kakikomi is a macOS image markup / annotation tool (similar in spirit to the discontinued Skitch). It lets a user open an image or screenshot and add text callouts, arrows, shapes, and mosaic/pixelate redaction, then save or share the annotated result. There is no account system, no in-app purchase, no advertising, and no network access of any kind — the app works entirely offline and does not collect, transmit, or store any user data outside files the user explicitly saves.

## How to test the core flow

1. Launch the app. The window opens empty with a prompt to drop an image, or use ⌘O / ⌘V.
2. Open any image via File > Open (⌘O), or copy an image to the clipboard and press ⌘V.
3. The toolbar (icons only, with tooltips) lets you pick a tool: Select, Text, Arrow, Rectangle, Rounded Rectangle, Ellipse, Mosaic, Crop.
   - Text tool: click on the canvas, type, click outside to commit. Drag a corner handle to resize (this changes the font size, not just the bounding box).
   - Arrow / Rectangle / Rounded Rectangle / Ellipse: click-drag to draw.
   - Mosaic: click-drag to pixelate a region (useful for redacting sensitive info in a screenshot).
   - Crop: click-drag to crop the image; applies immediately and can be undone (⌘Z).
4. Click the save icon in the toolbar to save the annotated result to the user's Pictures folder (no save panel — this is the app's primary save action). ⌘Shift+S opens a standard Save panel for saving elsewhere. ⌘C copies the result to the clipboard.
5. The icon on the right of the toolbar toggles "detailed mode," which reveals a side inspector for color/outline/font controls.

## Sandbox entitlements — why they're needed

- `com.apple.security.app-sandbox` — the app is fully sandboxed.
- `com.apple.security.assets.pictures.read-write` — the app's primary save action writes the annotated PNG directly into the user's Pictures folder without showing a save panel, matching the one-click workflow of screenshot-markup tools. This is the app's core, user-facing purpose (see step 4 above), not incidental access.
- `com.apple.security.files.user-selected.read-write` — used only for the standard Open panel (⌘O) and the optional "Save As…" panel (⌘Shift+S).

No other file-system, network, camera, or microphone entitlements are requested, because the app doesn't use any of those capabilities.

## Screen capture ("画面取込" / "Capture Screen" button)

The app includes an optional convenience feature to import a screenshot directly via `SCContentSharingPicker` (ScreenCaptureKit, macOS 14+). This intentionally uses Apple's system picker UI as the consent mechanism — the user explicitly selects a window or screen in the system-provided picker, and no separate Screen Recording permission prompt or entry in System Settings > Privacy is required beforehand. If this button is tested in a sandboxed review environment where no capturable windows/screens are available, the picker may simply show nothing to select; this does not affect the rest of the app, which works fully via Open (⌘O) or Paste (⌘V) without ever touching ScreenCaptureKit.

## Privacy

The app does not collect analytics, does not make network requests, does not use third-party SDKs, and does not require sign-in. All image processing happens locally in-process. The only persistent state written by the app is: (1) the annotated PNG file the user explicitly asks to save, and (2) a single local UserDefaults key that remembers whether the toolbar is in "simple" or "detailed" mode (declared in the app's privacy manifest).

## Contact

If anything above needs clarification during review, please reach out to info@satrex.jp.
