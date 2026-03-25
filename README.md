# Vidarr

AppKit + WKWebView で構成した軽量 macOS ブラウザです。最小UIで、Magic Mouse のジェスチャー操作を主軸にしています。

## 一般ユーザー向け

### インストール手順
1. [Releases](https://github.com/mani1261790/Vidarr/releases) から最新版の `Vidarr-*.dmg` をダウンロード
2. `.dmg` を開き、`Vidarr.app` を同梱の `Applications` フォルダへドラッグ
3. 初回起動時の保護解除が必要な場合は、DMG内の `2) First Launch Fix.command` を実行
4. その後 `Vidarr.app` を起動（必要なら右クリック -> `開く`）

注意:
- 現在の配布DMGは署名/公証なしです。環境によって初回起動時に macOS の警告が出る場合があります。
- Appleの公証（notarization）なしでは、この警告を完全になくすことはできません。
- もし `“Vidarr.app” is damaged and can’t be opened.` が出る場合:
```bash
xattr -dr com.apple.quarantine /Applications/Vidarr.app
```
- もし `“Vidarr.app” Not Opened` / `Apple could not verify ...` が出る場合も同様に上記コマンドで解除できます。
- それでも `Move to Trash` のみが出る場合:
  - `システム設定 > プライバシーとセキュリティ` で Vidarr の実行許可を有効化
  - もう一度起動する

## ジェスチャー一覧 (実装)
- `← (Left)` : 前タブ
- `→ (Right)` : 次タブ
- `L (↓→ / DownRight)` : 現在タブを閉じる
- `LL (↓→↓→ / DownRightDownRight)` : 全タブを閉じる
- `U (↓→↑)` : 閉じたタブを復元
- `O` : 現在タブをリロード
- `OO` : 全タブをリロード
- `↑→ (UpRight)` : 戻る
- `↑← (UpLeft)` : 進む
- `S` : 検索/URL入力用にアドレスバーへフォーカス
- `↓← (DownLeft)` : 新規タブ

注意:
- 横ストローク (`Left` / `Right`) はタブ切替専用です。
- 戻る/進むは矢印ジェスチャー (`↑→` / `↑←`) のみです。

## 開発者向け

### 実行手順 (Xcode)
1. `Vidarr.xcodeproj` を Xcode で開く
2. Target `Vidarr` を選択する
3. `Signing & Capabilities` で `Automatically manage signing` を有効にする
4. `Team` で `Personal Team` を選択する
5. Run destination を `My Mac` にして `Run` (⌘R)

### 現在の実装状況
- [x] 起動時に `MainWindowController` が立ち上がり、`WKWebView` を表示
- [x] 複数タブ管理（新規、前/次切替、現在閉じる、全閉じ、復元20件）
- [x] 指定10ジェスチャーの認識とアクション実行
- [x] ジェスチャー中HUD（候補+スコア）と確定表示
- [x] 最小UI（上部アドレスバー + 中央WebView）
- [x] セッション復元（前回終了時のタブ状態を保存）
- [x] ダウンロード対応と `Downloads` ウィンドウ
- [x] ファイルアップロード用の `Open Panel` 対応
- [x] JavaScript の `alert` / `confirm` / `prompt` 対応
- [x] ページズーム、印刷、PDF書き出し
- [x] カメラ/マイク要求時の権限確認ダイアログ
- [x] 読み込み失敗時の簡易エラーページ
- [x] 勝手に開くポップアップ/新規タブの抑止
- [x] 主要広告・追跡ドメインのブロックと一部広告要素の非表示
- [x] サイトごとの広告/追跡ブロック例外設定（Develop > Toggle Content Blocking for Current Site）
- [x] `GestureRecognizer` 単体テスト

### テスト実行
```bash
xcodebuild -project Vidarr.xcodeproj -scheme Vidarr -destination 'platform=macOS' test -only-testing:VidarrTests/GestureRecognizerTests
```

### GitHub Releases (DMG自動配布)
- `main` への push / PR で、GitHub Actions が自動ビルド検証します。
- `v*` タグを push すると、GitHub Actions が `.dmg` を作成して Releases に自動添付します。

### リリース手順
```bash
git tag v0.1.6
git push origin v0.1.6
```

### ローカルでDMG作成
```bash
./scripts/build_dmg.sh v0.1.6
```

### License
このリポジトリは [MIT License](./LICENSE) です。

### Legal Notice
- 本プロジェクトは Fenrir Inc.（フェンリル株式会社）とは一切関係ありません。
- 本プロジェクトは Sleipnir への愛好に基づく非公式な個人プロジェクトです。
- `Sleipnir` などの名称・ロゴ・関連商標は各権利者に帰属します。
- 権利者（Fenrir Inc. 含む）から申し立て・要請があった場合、公開状態（public/private）を含め、速やかに対応します。
