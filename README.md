# Vidarr

AppKit + WKWebView で構成した軽量 macOS ブラウザです。最小UIで、Magic Mouse のジェスチャー操作を主軸にしています。

動作環境: macOS 14 Sonoma 以降

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
- `← (Left)` : 次のタブ
- `→ (Right)` : 前のタブ
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
- ジェスチャーと操作の割り当ては Preferences で変更できます。
- 戻る/進むは矢印ジェスチャー (`↑→` / `↑←`) のみです。

## 開発者向け

### 実行手順 (Xcode)
1. `Vidarr.xcodeproj` を Xcode で開く
2. Target `Vidarr` を選択する
3. `Signing & Capabilities` で `Automatically manage signing` を有効にする
4. `Team` で `Personal Team` を選択する
5. Run destination を `My Mac` にして `Run` (⌘R)

### 現在の実装状況

ブラウザ本体:
- [x] 起動時に `MainWindowController` が立ち上がり、`WKWebView` を表示
- [x] 複数タブ管理（新規、前/次切替、現在閉じる、全閉じ、復元20件）
- [x] 保護タブ、ブックマーク状態、タブ並び替え
- [x] セッション復元（前回終了時のタブ状態を保存）
- [x] 非アクティブタブの自動休止と選択時の復元
- [x] タブグループの作成、改名、並べ替え、JSON書き出し
- [x] ローカル `html / pdf / txt` の表示
- [x] ダウンロード、ファイルアップロード、印刷、PDF書き出し

ジェスチャー / UI:
- [x] 指定ジェスチャーの認識とアクション実行
- [x] ジェスチャーHUD表示
- [x] 左右タブ切替と新規タブ生成のアニメーション
- [x] 最小UI（上部ツールバー + タブバー + 中央WebView）
- [x] 全画面時のツールバー自動非表示 / 再表示
- [x] 操作割り当て、入力方式別感度、重複警告を備えた Gesture Studio
- [x] 本番の認識器をそのまま使う別ウィンドウのジェスチャーテスト
- [x] タブ、履歴、ブックマーク、操作を横断するコマンドパレット（⌘K）

ページ互換性 / 安全性:
- [x] JavaScript の `alert` / `confirm` / `prompt` 対応
- [x] ページズーム
- [x] カメラ/マイク要求時の権限確認ダイアログ
- [x] 読み込み失敗時の簡易エラーページ
- [x] 勝手に開くポップアップ/新規タブの抑止
- [x] 主要広告・追跡ドメインのブロックと一部広告要素の非表示
- [x] サイトごとの広告/追跡ブロック例外設定
- [x] `Privacy & Site Controls` で例外ホストと保存済み権限を管理
- [x] 追跡除去、広告要素、ポップアップ、危険サイト、権限判断のプライバシーレポート

データ管理:
- [x] `Downloads / History / Bookmarks` ウィンドウ
- [x] 検索、複数選択、右クリックメニュー、削除操作
- [x] ダウンロード先フォルダ設定
- [x] 閲覧データ削除、設定リセット
- [x] タブグループごとのタブ、Cookie、サイトデータ分離
- [x] ドメインごとのタブグループ自動振り分け
- [x] 同じ Apple ID 間でのブックマーク同期用コード（iCloud Key-Value Store）

開発基盤:
- [x] `VidarrCore` 共有パッケージを追加
- [x] `BrowserPreferences / BrowsingStores / GestureRecognizer` を `VidarrCore` に移設
- [x] `GestureRecognizer` 単体テスト
- [ ] iPad target 追加
- [ ] iPad UI 実装

### ブックマーク同期
- Vidarr は、同じ Apple ID で使っている Vidarr 間で `ブックマークだけ` を同期します。
- 次のデータは同期しません:
  - 履歴
  - 開いているタブ
  - Cookie / サイトデータ
  - ダウンロード一覧
  - サイトごとの権限状態
- 同期コードは入っていますが、実際に使うには `Signing & Capabilities` で `iCloud` を有効にし、`Key-value storage` が使える Team で署名する必要があります。
- `Personal Team` では iCloud capability を使えないため、ローカル開発ビルドでは同期が無効のままになることがあります。

### テスト実行
```bash
xcodebuild -project Vidarr.xcodeproj -scheme Vidarr -destination 'platform=macOS' test -only-testing:VidarrTests/GestureRecognizerTests
```

### GitHub Releases (DMG自動配布)
- `main` への push / PR で、GitHub Actions が自動ビルド検証します。
- `v*` タグを push すると、GitHub Actions が `.dmg` を作成して Releases に自動添付します。

### リリース手順
```bash
git tag v0.1.8
git push origin v0.1.8
```

### ローカルでDMG作成
```bash
./scripts/build_dmg.sh v0.1.8
```

### License
このリポジトリは [MIT License](./LICENSE) です。

### Legal Notice
- 本プロジェクトは Fenrir Inc.（フェンリル株式会社）とは一切関係ありません。
- 権利者（Fenrir Inc. 含む）から申し立て・要請があった場合、公開状態（public/private）を含め、速やかに対応します。
