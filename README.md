# Vidarr

AppKit + WKWebView で構成した軽量 macOS ブラウザです。最小UIで、Magic Mouse のジェスチャー操作を主軸にしています。

## 実行手順 (Xcode)
1. `Vidarr.xcodeproj` を Xcode で開く
2. Target `Vidarr` を選択する
3. `Signing & Capabilities` で `Automatically manage signing` を有効にする
4. `Team` で `Personal Team` を選択する
5. Run destination を `My Mac` にして `Run` (⌘R)

## ジェスチャー一覧 (実装)
- `Left` : 前タブ
- `Right` : 次タブ
- `L` : 現在タブを閉じる
- `LL` : 全タブを閉じる
- `U` : 閉じたタブを復元
- `O` : 現在タブをリロード
- `OO` : 全タブをリロード
- `↑→ (UpRight)` : 戻る
- `↑← (UpLeft)` : 進む
- `S` : 検索/URL入力用にアドレスバーへフォーカス
- `↓← (DownLeft)` : 新規タブ

注意:
- 横ストローク (`Left` / `Right`) はタブ切替専用です。
- 戻る/進むは矢印ジェスチャー (`↑→` / `↑←`) のみです。

## 現在の実装状況
- [x] 起動時に `MainWindowController` が立ち上がり、`WKWebView` を表示
- [x] 複数タブ管理（新規、前/次切替、現在閉じる、全閉じ、復元20件）
- [x] 指定10ジェスチャーの認識とアクション実行
- [x] ジェスチャー中HUD（候補+スコア）と確定表示
- [x] 最小UI（上部アドレスバー + 中央WebView）
- [x] `GestureRecognizer` 単体テスト

## テスト実行
```bash
xcodebuild -project Vidarr.xcodeproj -scheme Vidarr -destination 'platform=macOS' test -only-testing:VidarrTests/GestureRecognizerTests
```
