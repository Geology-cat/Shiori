// レンダラの単体テスト（node --test test/）
import test from 'node:test';
import assert from 'node:assert/strict';
import { renderMarkdown, parseFenceInfo, splitFrontMatter } from '../src/markdown.js';

const html = (src, opts) => renderMarkdown(src, opts).html;

test('数式の中の _ や \\\\ が Markdown として解釈されない', () => {
  const out = html('$a_1 + b_1$ と $c_2 \\\\ d_2$ は *強調* できる');
  assert.match(out, /data-tex="a_1 \+ b_1"/);
  assert.match(out, /data-tex="c_2 \\\\ d_2"/);
  assert.match(out, /<em>強調<\/em>/);
  assert.doesNotMatch(out, /<em>1/);
});

test('ブロック数式と各種デリミタ', () => {
  assert.match(html('$$\nE = mc^2\n$$'), /<div class="math-block" data-tex="E = mc\^2"/);
  assert.match(html('\\[\nx^2\n\\]'), /class="math-block" data-tex="x\^2"/);
  assert.match(html('文 \\(x_1\\) 文'), /class="math-inline" data-tex="x_1"/);
  assert.match(html('```math\na_b\n```'), /class="math-block" data-tex="a_b"/);
  assert.match(html('前 $$x_1$$ 後'), /math-block-inline" data-tex="x_1"/);
});

test('ドル記号の誤検出を避ける', () => {
  assert.doesNotMatch(html('価格は $100 と $200 です'), /data-tex/);
  assert.doesNotMatch(html('\\$x\\$ はエスケープ'), /data-tex/);
  assert.doesNotMatch(html('`$x$` はコード'), /data-tex/);
});

test('リスト内・引用内のブロック数式', () => {
  assert.match(html('- 項目\n\n  $$\n  a_1\n  $$\n'), /data-tex="a_1"/);
  assert.match(html('> $$\n> a_1\n> $$\n'), /data-tex="a_1"/);
});

test('GFM: 表・取り消し線・自動リンク', () => {
  const out = html('| a | b |\n|---|:-:|\n| 1 | 2 |\n\n~~消す~~ https://example.com/x');
  assert.match(out, /<table/);
  assert.match(out, /<s>消す<\/s>/);
  assert.match(out, /href="https:\/\/example\.com\/x"/);
});

test('タスクリスト（行番号つき）', () => {
  const out = html('前書き\n\n- [ ] 未\n- [x] 済\n- [/] 途中\n');
  assert.match(out, /class="task-checkbox" data-task-line="2"/);
  assert.match(out, /data-task-line="3" checked/);
  assert.match(out, /data-task="doing"/);
  assert.match(out, /class="task-list"/);
});

test('フロントマターがあっても行番号がソース基準', () => {
  const out = html('---\ntitle: 表題\nauthor: 著者\ntags: [a, b]\n---\n\n本文\n\n- [ ] 未\n');
  assert.match(out, /class="doc-title">表題/);
  assert.match(out, /class="doc-author">著者/);
  assert.match(out, /<th>tags<\/th><td>a, b<\/td>/);
  assert.match(out, /<p data-line="6" data-line-end="7">本文/);
  assert.match(out, /data-task-line="8"/);
});

test('壊れた YAML でも本文を失わない', () => {
  const fm = splitFrontMatter('---\nfoo: [\n---\n本文');
  assert.equal(fm.data, null);
  assert.equal(fm.body, '本文');
  assert.match(renderMarkdown('---\nfoo: [\n---\n本文').html, /本文/);
});

test('--- で始まるだけの本文はフロントマターにしない', () => {
  assert.match(html('---\n\n本文'), /<hr/);
});

test('ブロックに開始行と終了行が付く（閲覧⇔編集の位置合わせ用）', () => {
  const out = html('一行目\n二行目\n三行目\n\n```js\na\nb\n```\n\n$$\nx\n$$\n');
  assert.match(out, /<p data-line="0" data-line-end="3">/);
  assert.match(out, /class="code-block" data-line="4" data-line-end="8"/);
  assert.match(out, /class="math-block" data-tex="x" data-line="9" data-line-end="12"/);
});

test('脚注・定義リスト・上下付き・マーカー・略語', () => {
  assert.match(html('本文[^1]\n\n[^1]: 注'), /class="footnotes"/);
  assert.match(html('語\n: 定義'), /<dl/);
  assert.match(html('H~2~O と x^2^'), /<sub>2<\/sub>.*<sup>2<\/sup>/s);
  assert.match(html('==強調=='), /<mark>強調<\/mark>/);
  assert.match(html('++追加++'), /<ins>追加<\/ins>/);
  assert.match(html('*[HTML]: Hyper\n\nHTML です'), /<abbr title="Hyper">HTML<\/abbr>/);
  assert.match(html(':smile:'), /😄/);
});

test('GitHub Alerts と Obsidian Callout', () => {
  const a = html('> [!WARNING]\n> 注意して');
  assert.match(a, /<div[^>]*class="callout"[^>]*data-callout="warning"/);
  assert.match(a, /class="callout-title">Warning/);
  assert.match(a, /注意して/);
  assert.doesNotMatch(a, /\[!WARNING\]/);

  const b = html('> [!tip]- 折りたたみ *題*\n> 本文');
  assert.match(b, /<details[^>]*data-callout="tip"/);
  assert.match(b, /<summary class="callout-title">折りたたみ <em>題<\/em><\/summary>/);
  assert.match(b, /<\/details>/);

  // 本文なしでも壊れない
  assert.match(html('> [!note] タイトルだけ'), /タイトルだけ/);
  // 普通の引用はそのまま
  assert.match(html('> 普通の引用'), /<blockquote/);
});

test('MkDocs Admonition と ::: コンテナ', () => {
  const a = html('!!! note "題"\n    本文 *強調*\n\n後続');
  assert.match(a, /data-callout="note"/);
  assert.match(a, /class="callout-title">題/);
  assert.match(a, /<em>強調<\/em>/);
  assert.match(a, /<p data-line="3" data-line-end="4">後続/);

  assert.match(html('??? warning\n    隠す'), /<details[^>]*data-callout="warning"/);
  assert.match(html(':::warning\n注意\n:::'), /data-callout="warning"/);
  assert.match(html(':::details 開く\n中身\n:::'), /<details[\s\S]*<summary[^>]*>開く<\/summary>[\s\S]*中身[\s\S]*<\/details>/);
  assert.match(html(':::message alert\n警告\n:::'), /data-callout="warning"/);
});

test('Wikilink と埋め込み', () => {
  assert.match(html('[[ノート|表示]]'), /data-wikilink="ノート">表示<\/a>/);
  assert.match(html('![[図.png|300]]'), /data-wiki-src="図.png"[^>]*width="300"/);
  assert.match(html('![[別ノート]]'), /data-wiki-embed="別ノート"/);
  assert.doesNotMatch(html('[[toc]]'), /data-wikilink/);
});

test('画像サイズ指定', () => {
  const out = html('![説明|300x200](a.png)');
  assert.match(out, /alt="説明"/);
  assert.match(out, /width="300"/);
  assert.match(out, /height="200"/);
});

test('ルビと傍点', () => {
  assert.match(html('｜青空《あおぞら》'), /<ruby>青空<rp>\(<\/rp><rt>あおぞら<\/rt>/);
  assert.match(html('今日は吾輩《わがはい》です'), /今日は<ruby>|<ruby>吾輩/);
  assert.match(html('{東京|とうきょう}'), /<ruby>東京<rp>\(<\/rp><rt>とうきょう/);
  assert.match(html('{東京|とう|きょう}'), /<ruby>東<rp>\(<\/rp><rt>とう<\/rt><rp>\)<\/rp>京/);
  assert.match(html('《《傍点》》'), /class="bouten">傍点/);
  assert.match(html('`｜青空《あおぞら》`'), /<code>/);
});

test('コードブロック: ハイライトとファイル名', () => {
  const a = html('```python\nprint(1)\n```');
  assert.match(a, /class="hljs language-python"/);
  assert.match(a, /hljs-built_in/);
  assert.match(html('```js:app.js\nlet a\n```'), /class="code-label">app\.js/);
  assert.deepEqual(parseFenceInfo('python title="x.py"'), { lang: 'python', title: 'x.py' });
  assert.deepEqual(parseFenceInfo('{.rust}'), { lang: 'rust', title: '' });
  // 未知の言語でもエスケープされる
  assert.match(html('```unknownlang\n<b>\n```'), /&lt;b&gt;/);
});

test('mermaid は描画待ちのブロックになる', () => {
  const r = renderMarkdown('```mermaid\ngraph TD\nA-->B\n```');
  assert.equal(r.hasMermaid, true);
  assert.match(r.html, /data-diagram="mermaid"/);
  assert.match(r.html, /A--&gt;B/);
});

test('コメントは表示しない', () => {
  assert.doesNotMatch(html('見える %%見えない%% 見える'), /見えない/);
  assert.doesNotMatch(html('%%\n見えない\n%%\n\n見える'), /見えない/);
});

test('タグ', () => {
  assert.match(html('本文 #研究/地質 です'), /class="tag">#研究\/地質/);
  assert.doesNotMatch(html('課題 #123 です'), /class="tag"/);
  assert.match(html('# 見出し'), /<h1/);
});

test('見出し id は日本語を保ち重複を避ける', () => {
  const out = html('# 概要\n\n## 概要\n\n## Hello World!');
  assert.match(out, /id="概要"/);
  assert.match(out, /id="概要-1"/);
  assert.match(out, /id="hello-world"/);
});

test('属性指定', () => {
  assert.match(html('# 題 {#my-id .note}'), /id="my-id"/);
});

test('改行オプション', () => {
  assert.match(html('一\n二', { breaks: true }), /<br/);
  assert.doesNotMatch(html('一\n二', { breaks: false }), /<br/);
});

test('危険なリンクを無効化する', () => {
  assert.doesNotMatch(html('[x](javascript:alert(1))'), /href="javascript/);
});

test('空文書や記号だけでも落ちない', () => {
  for (const src of ['', '\n\n', '$', '$$', '[[', '> [!', ':::', '!!! ', '《', '{|}', '---', '%%', '$$\n未完']) {
    assert.equal(typeof html(src), 'string', src);
  }
});
