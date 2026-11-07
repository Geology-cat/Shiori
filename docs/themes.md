# テーマの作り方

ビューワーのデザインは CSS で変えられます。

## 使い方

環境設定（⌘,）の「テーマ」タブから操作します。

- **CSS を読み込む**: 手元の `.css` をテーマとして取り込みます
- **雛形から作成**: 変数の説明付きのテーマを作ります
- **フォルダを開く**: `~/Library/Application Support/Shiori/themes/` を開きます。ここに置いた `.css` は自動で一覧に追加されます

テーマは丸ごとの差し替えではなく、共通の `base.css` の上に重なります。保存するとすぐに表示へ反映されます。

見出しの色だけ変えたいといった小さな調整には「追加の CSS」（`custom.css`）が向いています。どのテーマの上にも重なります。

## 変数

ほとんどの見た目は変数で変えられます。

| 変数 | 内容 |
|------|------|
| `--bg` `--fg` | 背景と文字 |
| `--muted` `--faint` | 補助の文字 |
| `--accent` | リンクなど |
| `--rule` | 罫線 |
| `--surface` | 表の見出しなどの面 |
| `--code-bg` | コードの背景 |
| `--mark-bg` `--mark-fg` | `==マーカー==` |
| `--selection` | 選択範囲 |
| `--font-body` `--font-heading` `--font-mono` | 書体 |
| `--theme-font-size` | 基準の文字サイズ |
| `--theme-line-height` | 行間 |
| `--theme-measure` | 本文の幅（縦書きでは 1 行の長さ） |
| `--block-gap` | 段落の間隔 |
| `--heading-weight` | 見出しの太さ |
| `--hl-keyword` `--hl-string` `--hl-number` `--hl-comment` `--hl-function` `--hl-type` `--hl-attr` | コードの色分け |
| `--callout-note` `--callout-tip` `--callout-important` `--callout-warning` `--callout-danger` `--callout-question` `--callout-example` `--callout-quote` `--callout-abstract` | 注記の色 |

ダークモード用の値は次のセレクタに書きます。

```css
:root[data-appearance="dark"] {
  --bg: #1b1d21;
  --fg: #d8dade;
}
```

## 縦書きでも崩れないように

余白や罫線は論理プロパティで書いてください。

| 物理プロパティ | 論理プロパティ |
|------|------|
| `margin-top` / `margin-bottom` | `margin-block` |
| `padding-left` / `padding-right` | `padding-inline` |
| `border-bottom` | `border-block-end` |
| `border-left` | `border-inline-start` |
| `width` | `inline-size` |
| `height` | `block-size` |

縦書きのときだけ変えたい指定は `:root[data-writing="vertical"]` の下に書きます。

## 使えるセレクタ

普通の要素（`h1` `p` `table` `blockquote` など）のほかに、次のものがあります。

| セレクタ | 内容 |
|------|------|
| `.shiori-doc` | 本文全体 |
| `.doc-header` `.doc-title` `.doc-author` `.doc-date` `.doc-abstract` | フロントマターから作る表題 |
| `.properties` | フロントマターのプロパティ |
| `.code-block` `.code-label` | コードブロックとファイル名 |
| `.table-wrap` `caption` | 表とキャプション |
| `figure` `figcaption` | 図とキャプション |
| `.math-block` `.math-inline` | 数式 |
| `.diagram` | mermaid の図 |
| `.callout` `.callout-title` `.callout-body` | 注記（`[data-callout="warning"]` などで種類を指定） |
| `.task-item` `.task-checkbox` | タスク |
| `.toc` | `[[toc]]` の目次 |
| `.footnotes` | 脚注 |
| `.tag` `.wikilink` `.embed` | タグ、Wiki リンク、ノートの埋め込み |
| `em.bouten` `.tcy` | 傍点と縦中横 |

`:root` の属性でも分岐できます。

| 属性 | 値 |
|------|------|
| `data-appearance` | `light` / `dark` |
| `data-writing` | `horizontal` / `vertical` |
| `data-lang` | `ja` / `en`（本文から自動判定） |
| `data-heading-numbers` `data-indent` `data-justify` | `on` / `off` |

同梱テーマのソース（`web/themes/`）も参考になります。
