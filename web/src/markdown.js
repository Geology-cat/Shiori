// Markdown → HTML 変換（DOM に依存しない純粋な処理。Node のテストからも使う）
import MarkdownIt from 'markdown-it';
import footnote from 'markdown-it-footnote';
import deflist from 'markdown-it-deflist';
import sub from 'markdown-it-sub';
import sup from 'markdown-it-sup';
import mark from 'markdown-it-mark';
import ins from 'markdown-it-ins';
import abbr from 'markdown-it-abbr';
import { full as emoji } from 'markdown-it-emoji';
import attrs from 'markdown-it-attrs';
import container from 'markdown-it-container';
import { load as loadYaml } from 'js-yaml';

import hljs from './highlight.js';
import { mathPlugin } from './plugins/math.js';
import { calloutPlugin, admonitionPlugin, containerCallout } from './plugins/callout.js';
import { wikilinkPlugin } from './plugins/wikilink.js';
import { rubyPlugin } from './plugins/ruby.js';
import { commentPlugin } from './plugins/comment.js';
import { taskListPlugin } from './plugins/tasklist.js';
import { tagPlugin } from './plugins/tag.js';
import { headingIdPlugin } from './plugins/heading-id.js';
import { lineMapPlugin } from './plugins/linemap.js';
import { imageSizePlugin } from './plugins/image-size.js';
import { escapeHtml, lineAttrs } from './util.js';

/** 図表（mermaid など）としてブラウザ側で後処理する言語 */
const DIAGRAM_LANGS = new Set(['mermaid']);

/** コードフェンスの情報文字列を解釈する。`js:app.js` / `python title="x.py"` に対応 */
export function parseFenceInfo(info) {
  const raw = (info || '').trim();
  if (!raw) return { lang: '', title: '' };
  const titleMatch = raw.match(/\btitle=(?:"([^"]*)"|'([^']*)'|(\S+))/);
  let title = titleMatch ? (titleMatch[1] ?? titleMatch[2] ?? titleMatch[3]) : '';
  const first = raw.split(/\s+/)[0].replace(/^\{\.?/, '').replace(/\}$/, '');
  let lang = first;
  const colon = first.indexOf(':');
  if (colon >= 0) {
    lang = first.slice(0, colon);
    if (!title) title = first.slice(colon + 1);
  }
  return { lang: lang.toLowerCase(), title };
}

function renderFence(tokens, idx, _options, env, self) {
  const token = tokens[idx];
  const { lang, title } = parseFenceInfo(token.info);
  const lineAttr = lineAttrs(token);

  if (DIAGRAM_LANGS.has(lang)) {
    env.hasMermaid = true;
    return `<div class="diagram" data-diagram="${lang}"${lineAttr}><pre class="diagram-src">${escapeHtml(token.content)}</pre></div>\n`;
  }
  // GitHub の ```math 記法
  if (lang === 'math' || lang === 'latex-math' || lang === 'katex') {
    env.hasMath = true;
    return `<div class="math-block" data-tex="${escapeHtml(token.content.trim())}"${lineAttr}></div>\n`;
  }

  let body;
  let langClass = '';
  // diff-python のように diff を前置した指定はそのまま diff として扱う
  const hlLang = lang.startsWith('diff-') ? 'diff' : lang;
  if (hlLang && hljs.getLanguage(hlLang)) {
    try {
      body = hljs.highlight(token.content, { language: hlLang, ignoreIllegals: true }).value;
      langClass = ` language-${hlLang}`;
    } catch {
      body = escapeHtml(token.content);
    }
  } else {
    body = escapeHtml(token.content);
    if (lang) langClass = ` language-${escapeHtml(lang)}`;
  }
  const label = title || lang;
  const header = label
    ? `<div class="code-label">${escapeHtml(label)}</div>`
    : '';
  return `<div class="code-block${title ? ' has-title' : ''}"${lineAttr}>${header}<pre><code class="hljs${langClass}">${body}</code></pre></div>\n`;
}

/** 表示オプションごとに MarkdownIt インスタンスを作る */
export function createMarkdown({ breaks = true } = {}) {
  const md = new MarkdownIt({
    html: true,
    linkify: true,
    breaks,
    typographer: false,
  });
  // 日本語文中で誤爆しやすいので fuzzy な URL 検出は無効にする
  md.linkify.set({ fuzzyLink: false, fuzzyEmail: false, fuzzyIP: false });
  // 画像・リンクの宛先に日本語やスペースを含むファイル名を許す
  md.validateLink = (url) => !/^\s*(javascript|vbscript|file):/i.test(url);

  md.use(lineMapPlugin);
  md.use(mathPlugin);
  md.use(commentPlugin);
  md.use(wikilinkPlugin);
  md.use(tagPlugin);
  md.use(footnote);
  md.use(deflist);
  md.use(sub);
  md.use(sup);
  md.use(mark);
  md.use(ins);
  md.use(abbr);
  md.use(emoji);
  md.use(admonitionPlugin);
  md.use(calloutPlugin);
  md.use(taskListPlugin);
  md.use(imageSizePlugin);
  md.use(rubyPlugin);
  md.use(headingIdPlugin);
  md.use(attrs, { allowedAttributes: ['id', 'class', 'width', 'height', 'style', 'align', /^data-.*$/] });

  // ::: コンテナ（VuePress / Docusaurus / Zenn / Qiita）
  md.use(container, 'callout', containerCallout(md));

  md.renderer.rules.fence = renderFence;
  md.renderer.rules.code_block = (tokens, idx, _o, _e) => {
    const lineAttr = lineAttrs(tokens[idx]);
    return `<div class="code-block"${lineAttr}><pre><code class="hljs">${escapeHtml(tokens[idx].content)}</code></pre></div>\n`;
  };

  // 脚注の表記を簡潔にする
  md.renderer.rules.footnote_block_open = () =>
    '<section class="footnotes"><ol class="footnotes-list">\n';
  md.renderer.rules.footnote_block_close = () => '</ol></section>\n';
  md.renderer.rules.footnote_caption = (tokens, idx) => {
    let n = Number(tokens[idx].meta.id + 1).toString();
    if (tokens[idx].meta.subId > 0) n += `:${tokens[idx].meta.subId}`;
    return n;
  };
  return md;
}

// ------------------------------------------------------------
// フロントマター
// ------------------------------------------------------------

/** 先頭の YAML (---) / TOML (+++) フロントマターを取り除く */
export function splitFrontMatter(source) {
  const text = source.startsWith('﻿') ? source.slice(1) : source;
  const m = text.match(/^(---|\+\+\+)[ \t]*\r?\n([\s\S]*?)\r?\n?(?:\1|\.\.\.)[ \t]*(?:\r?\n|$)/);
  if (!m) return { body: text, data: null, raw: '', lineOffset: 0 };
  const raw = m[2];
  let data = null;
  if (m[1] === '---') {
    try {
      const parsed = loadYaml(raw);
      if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) data = parsed;
    } catch {
      data = null; // 壊れた YAML は本文として扱わず、そのまま原文を表示する
    }
  }
  const consumed = m[0];
  const lineOffset = (consumed.match(/\n/g) || []).length;
  return { body: text.slice(consumed.length), data, raw, lineOffset };
}

function formatValue(value) {
  if (value == null) return '';
  if (value instanceof Date) return value.toISOString().slice(0, 10);
  if (Array.isArray(value)) return value.map(formatValue).join(', ');
  if (typeof value === 'object') return JSON.stringify(value);
  return String(value);
}

const TITLE_KEYS = ['title', 'タイトル'];
const AUTHOR_KEYS = ['author', 'authors', '著者'];
const DATE_KEYS = ['date', '日付'];
const ABSTRACT_KEYS = ['abstract', '概要', '要旨'];

function pick(data, keys) {
  for (const k of keys) if (data[k] != null && data[k] !== '') return { key: k, value: data[k] };
  return null;
}

/** フロントマターから文書の表題ブロックとプロパティ一覧を組み立てる */
export function renderFrontMatter(fm, { showProperties = true } = {}) {
  if (!fm.data && !fm.raw) return { html: '', title: null };
  if (!fm.data) {
    if (!showProperties) return { html: '', title: null };
    return {
      html: `<details class="properties"><summary>プロパティ</summary><pre>${escapeHtml(fm.raw)}</pre></details>\n`,
      title: null,
    };
  }
  const used = new Set();
  const take = (keys) => {
    const hit = pick(fm.data, keys);
    if (hit) used.add(hit.key);
    return hit ? hit.value : null;
  };
  const title = take(TITLE_KEYS);
  const author = take(AUTHOR_KEYS);
  const date = take(DATE_KEYS);
  const abstract = take(ABSTRACT_KEYS);

  let html = '';
  if (title != null) {
    html += '<header class="doc-header">';
    html += `<h1 class="doc-title">${escapeHtml(formatValue(title))}</h1>`;
    if (author != null) html += `<p class="doc-author">${escapeHtml(formatValue(author))}</p>`;
    if (date != null) html += `<p class="doc-date">${escapeHtml(formatValue(date))}</p>`;
    if (abstract != null) html += `<p class="doc-abstract">${escapeHtml(formatValue(abstract))}</p>`;
    html += '</header>\n';
  } else {
    // 表題がないときは著者などもプロパティ側に残す
    used.clear();
  }

  if (showProperties) {
    const rows = Object.entries(fm.data)
      .filter(([k]) => !used.has(k))
      .map(([k, v]) => `<tr><th>${escapeHtml(k)}</th><td>${escapeHtml(formatValue(v))}</td></tr>`)
      .join('');
    if (rows) {
      html += `<details class="properties"><summary>プロパティ</summary><table>${rows}</table></details>\n`;
    }
  }
  return { html, title: title != null ? formatValue(title) : null };
}

// ------------------------------------------------------------
// 公開 API
// ------------------------------------------------------------

const instances = new Map();

function getMarkdown(breaks) {
  const key = breaks ? 'breaks' : 'nobreaks';
  if (!instances.has(key)) instances.set(key, createMarkdown({ breaks }));
  return instances.get(key);
}

/**
 * Markdown 全文を HTML に変換する。
 * @returns {{html: string, title: string|null, hasMath: boolean, hasMermaid: boolean, frontMatter: object|null}}
 */
export function renderMarkdown(source, { breaks = true, showProperties = true } = {}) {
  const fm = splitFrontMatter(source);
  const env = { lineOffset: fm.lineOffset, hasMath: false, hasMermaid: false, usedSlugs: new Map(), docTitle: null };
  const front = renderFrontMatter(fm, { showProperties });
  env.docTitle = front.title;
  const body = getMarkdown(breaks).render(fm.body, env);
  return {
    html: front.html + body,
    title: front.title,
    hasMath: env.hasMath,
    hasMermaid: env.hasMermaid,
    frontMatter: fm.data,
  };
}
