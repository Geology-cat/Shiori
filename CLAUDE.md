# Shiori 開発ガイド

macOS 用の軽量な Markdown ビューワー / エディタ。閲覧と編集を 1 ペインで切り替えられ、専用の保管フォルダを作らず Finder の md をそのまま開く。

- ユーザー向けの説明: [README.md](README.md)
- これまでの経緯と判断の理由: [開発履歴.md](開発履歴.md)
- テーマの作り方: [docs/themes.md](docs/themes.md)

## 開発ルール

- **言語**: 会話、コメント、ドキュメント、コミットメッセージはすべて日本語
- **変更したら**: 大きな機能や設計判断は [開発履歴.md](開発履歴.md) に追記する（なぜそうしたかを残す）
- **表示設定の扱い**: 既定のテーマと、テーマごとの既定（組方向・文字・組版、`ViewStyle`）は環境設定だけで変える。表示パネル（Aa）やメニューで変えたものはウインドウの調整（`WorkspaceModel.viewOverrides`）で、同じウインドウで開くファイルに引き継ぐ。保存はせず、新しいウインドウや起動時は既定から始める。既定には書き戻さない
- **開き方**: ファイラーからは `openFromFiler`（環境設定に従い、⌘ で逆）、外からは `AppDelegate.open(_:from:)`（`.external` は環境設定に従う、`.app` は今のウインドウ）を通す
- **データを壊さない**: 保存まわりを変えるときは `TextFile` と `DocumentTab` のテストを必ず通す。Finder にある他人のファイルを開くアプリなので、文字コード・改行・パーミッションを勝手に変えない
- **軽さを保つ**: 重いスクリプトは使う文書でだけ読み込む。常時読み込むものを増やすときは理由を書く

## 構成

```
Shiori/            Swift（AppKit + SwiftUI）
  App/             起動、ウィンドウ、メニュー
  Workspace/       ウィンドウごとの状態、タブ、ファイル入出力、監視、索引
  Viewer/          WKWebView の制御と URL スキーム
  Editor/          NSTextView、構文ハイライト、入力支援
  Settings/        環境設定、テーマ管理
  Export/          PDF / HTML / 印刷
  Views/           SwiftUI の画面
ShioriTests/       Swift の単体テスト
web/               ビューワー本体（WKWebView で動く）
  src/             markdown-it とプラグイン、スクロール、検索など
  css/ themes/     共通 CSS とテーマ
  test/            レンダラのテスト（node --test）
  dist/            ビルド結果。アプリに同梱するのでコミットする
samples/           動作確認用の md（記法ガイドとしてアプリにも同梱）
scripts/           DMG 作成など
```

Xcode プロジェクトは同期フォルダ方式（objectVersion 77）。`Shiori/` にファイルを置くだけでビルド対象になるので、`project.pbxproj` を編集する必要はない。

## よく使うコマンド

```bash
make web         # web/dist を作り直す（web/ を変えたら必要）
make test        # レンダラと Swift のテスト
make run         # デバッグビルドを起動
make app         # リリースビルド
make dmg         # 配布用 DMG
```

`web/` を変更したら `make web` を実行して、`web/dist` も一緒にコミットする。Xcode のビルドは node を必要としない。

## リリース

1. `Info.plist` ではなく `project.pbxproj` の `MARKETING_VERSION` と `CURRENT_PROJECT_VERSION` を上げる
2. `開発履歴.md` を更新してコミットし、push する
3. `make clean && SIGN_IDENTITY=- make dmg` で DMG を作る。公開物はアドホック署名にする（Apple Development の証明書は配布向けではなく、署名にメールアドレスが入るため）
4. 公開前に `otool -l` で `__llvm_prf` が入っていないことを確かめる（計測コードは共有スキームで切っている）
5. `git tag vX.Y.Z` を打ち、`gh release create` で DMG を添付する

## 設計の要点

### 描画は WebView 側に集約する

Markdown の解析は Swift ではなく WKWebView 内の markdown-it で行う。Swift 側は全文を渡すだけ。

- 呼び出し口は `window.Shiori`（`web/src/main.js`）。Swift からは `ViewerController` 経由で呼ぶ
- ブロック要素に `data-line`（ソースの行番号）を振っている。閲覧⇔編集で同じ位置を保つ、チェックボックスをソースへ反映する、などはすべてこの行番号を使う
- 数式はパース段階で切り出す（`plugins/math.js`）。後から auto-render すると `$a_1$` の `_` が強調に化けるため
- KaTeX と mermaid は該当する文書でだけ遅延読み込みする

### 1 ウィンドウに WebView と NSTextView を 1 つずつ

タブを切り替えても WebView は作り直さない。テーマ、組方向、文字サイズはページを再読み込みせず `Shiori.applySettings` で差し替える。エディタは 1 つの `NSTextView` にタブごとの `NSTextStorage` を差し替えて使い回す。

### テキストの正本は `DocumentTab.storage`

文字列のコピーを持ち回らない。変更は `DocumentTab.textDidChange()` を通すと、版番号の更新、未保存判定、自動保存の予約まで行われる。

### 縦書きは論理プロパティで吸収する

テーマは `margin-block` `padding-inline` `border-block-end` などの論理プロパティで書く。`writing-mode` を変えるだけで縦書きになる。スクロールの差異（横軸、右端が起点、ホイールの読み替え）は `web/src/scroll.js` に閉じ込めている。コード、表、数式、図は `base.css` の末尾で横組みの島にしている。

### セキュリティ

任意の md を開くので、本文は信頼しない。

- `viewer.html` の CSP で、同梱以外のスクリプトと外部通信を止めている
- `sanitize.js` の DOMPurify で生 HTML を無害化する
- `shiori-file://` は画像・動画・フォントの拡張子だけを配信する（`ShioriSchemeHandler`）
- リンクは JS で受けて Swift に渡す。WebView 自身は遷移させない

### App Sandbox は使わない

Sandbox 下では Finder から開いたファイル以外に権限がなく、親フォルダの一覧も同じフォルダの画像も読めないため無効にしている。App Store には出せない。

## macOS 26 以降の注意

`NSToolbar` を付けたウィンドウに `NSScrollView` を置くと、スクロールエッジ効果がタイトルバー領域の自前の UI を覆って隠す。上部バーは自前で描いているので `NSToolbar` は付けないこと。

## 動作確認

検証用のサンプルは `samples/` にある。インストール済みの Shiori と取り違えないよう、検証用のビルドは `PRODUCT_BUNDLE_IDENTIFIER=com.geologycat.Shiori.dev` を付けて別のアプリとしてビルドし、パスを指定して開く。

UI を変えたら次を実機で確認する。

- 閲覧⇔編集で同じ箇所が見えているか
- 縦書きとライト / ダークで崩れないか
- `samples/shift_jis_sample.md` を編集して保存しても Shift_JIS と CRLF のままか
