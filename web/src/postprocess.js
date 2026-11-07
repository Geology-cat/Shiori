// サニタイズ後の DOM に対する仕上げ（図版化、目次、縦中横、数式・図の描画、画像パスの解決）
import { ask } from './bridge.js';
import { renderMarkdown } from './markdown.js';
import { sanitize } from './sanitize.js';

const IMAGE_FILE = /\.(png|jpe?g|gif|svg|webp|heic|heif|tiff?|bmp|avif)(?:[?#].*)?$/i;

// ------------------------------------------------------------
// 遅延読み込み（数式も図もない文書では重いスクリプトを読まない）
// ------------------------------------------------------------

const scripts = new Map();

function loadScript(src) {
  if (!scripts.has(src)) {
    scripts.set(src, new Promise((resolve, reject) => {
      const el = document.createElement('script');
      el.src = src;
      el.onload = () => resolve();
      el.onerror = () => reject(new Error(`読み込み失敗: ${src}`));
      document.head.appendChild(el);
    }));
  }
  return scripts.get(src);
}

let katexReady;
function ensureKatex() {
  if (!katexReady) {
    const link = document.createElement('link');
    link.rel = 'stylesheet';
    link.href = 'katex/katex.min.css';
    document.head.appendChild(link);
    katexReady = loadScript('katex/katex.min.js').then(() => loadScript('katex/mhchem.min.js'));
  }
  return katexReady;
}

// ------------------------------------------------------------
// パス解決
// ------------------------------------------------------------

export function fileUrl(path) {
  return 'shiori-file://local' + path.split('/').map(encodeURIComponent).join('/');
}

function baseUrlFor(docPath) {
  if (!docPath) return null;
  return fileUrl(docPath.slice(0, docPath.lastIndexOf('/') + 1));
}

function isExternalUrl(src) {
  return /^(?:[a-z][a-z0-9+.-]*:|\/\/)/i.test(src);
}

function resolveMedia(fragment, docPath) {
  const base = baseUrlFor(docPath);
  const elements = fragment.querySelectorAll('img[src], video[src], audio[src], source[src]');
  for (const el of elements) {
    const src = el.getAttribute('src');
    if (!src || isExternalUrl(src) || src.startsWith('#')) continue;
    if (src.startsWith('/')) {
      el.setAttribute('src', fileUrl(decodeSafe(src)));
    } else if (base) {
      try {
        el.setAttribute('src', new URL(src, base).href);
      } catch { /* 不正なパスはそのまま */ }
    }
  }
}

function decodeSafe(s) {
  try { return decodeURIComponent(s); } catch { return s; }
}

// ------------------------------------------------------------
// 図版・表
// ------------------------------------------------------------

// 段落に画像だけが入っているものを figure にして説明文を付ける
function wrapFigures(fragment) {
  for (const p of Array.from(fragment.querySelectorAll('p'))) {
    const meaningful = Array.from(p.childNodes).filter(
      (n) => !(n.nodeType === Node.TEXT_NODE && !n.textContent.trim()) && n.nodeName !== 'BR'
    );
    if (meaningful.length === 0) continue;
    const imgs = meaningful.filter((n) => n.nodeName === 'IMG');
    if (imgs.length !== meaningful.length) continue;

    const figure = document.createElement('figure');
    if (p.dataset.line) figure.dataset.line = p.dataset.line;
    if (imgs.length > 1) figure.classList.add('figure-group');
    for (const img of imgs) figure.appendChild(img);
    // 説明文は title を優先し、なければファイル名らしくない alt を使う
    const first = imgs[0];
    const caption = first.getAttribute('title') || (imgs.length === 1 ? first.getAttribute('alt') : '');
    if (caption && !IMAGE_FILE.test(caption)) {
      const cap = document.createElement('figcaption');
      cap.textContent = caption;
      figure.appendChild(cap);
    }
    p.replaceWith(figure);
  }
}

// 表を横スクロール可能にし、前後の「表 1: …」「Table: …」「: …」を caption にする
const TABLE_CAPTION = /^(?:表\s*[0-9０-９]*\s*[:：.．]?|Table\s*[0-9]*\s*[:.]|:)\s*(.+)$/s;

function wrapTables(fragment) {
  for (const table of Array.from(fragment.querySelectorAll('table'))) {
    if (table.closest('.properties')) continue;
    for (const sibling of [table.nextElementSibling, table.previousElementSibling]) {
      if (sibling?.tagName !== 'P') continue;
      const m = sibling.textContent.trim().match(TABLE_CAPTION);
      if (!m) continue;
      const caption = document.createElement('caption');
      caption.textContent = m[1];
      table.prepend(caption);
      sibling.remove();
      break;
    }
    const wrap = document.createElement('div');
    wrap.className = 'table-wrap';
    if (table.dataset.line) wrap.dataset.line = table.dataset.line;
    table.replaceWith(wrap);
    wrap.appendChild(table);
  }
}

// ------------------------------------------------------------
// 目次
// ------------------------------------------------------------

const TOC_MARKER = /^(?:\[toc\]|\[\[_?toc_?\]\]|\{:toc\}|\[\[toc\]\])$/i;

function buildToc(fragment) {
  const markers = Array.from(fragment.querySelectorAll('p')).filter((p) => TOC_MARKER.test(p.textContent.trim()));
  if (markers.length === 0) return;
  const headings = Array.from(fragment.querySelectorAll('h1,h2,h3,h4,h5,h6')).filter((h) => !h.classList.contains('doc-title'));
  const nav = document.createElement('nav');
  nav.className = 'toc';
  const title = document.createElement('p');
  title.className = 'toc-title';
  title.textContent = '目次';
  nav.appendChild(title);
  const list = document.createElement('ul');
  for (const h of headings) {
    const li = document.createElement('li');
    li.className = `toc-l${h.tagName[1]}`;
    const a = document.createElement('a');
    a.href = `#${h.id}`;
    a.textContent = h.textContent;
    li.appendChild(a);
    list.appendChild(li);
  }
  nav.appendChild(list);
  for (const marker of markers) marker.replaceWith(nav.cloneNode(true));
}

// ------------------------------------------------------------
// 縦中横（縦書きで 2 桁までの数字と !? を正立させる）
// ------------------------------------------------------------

const TCY = /(?<![0-9A-Za-z.,:/_-])(?:[0-9]{1,2}|[!?！？]{2})(?![0-9A-Za-z.,:/_-])/g;
const TCY_SKIP = 'code,pre,kbd,.math-inline,.math-block,.diagram,rt,script,style,a[href^="http"]';

function wrapTateChuYoko(fragment) {
  const walker = document.createTreeWalker(fragment, NodeFilter.SHOW_TEXT);
  const nodes = [];
  while (walker.nextNode()) {
    const node = walker.currentNode;
    if (/[0-9!?！？]/.test(node.nodeValue) && !node.parentElement?.closest(TCY_SKIP)) nodes.push(node);
  }
  for (const node of nodes) {
    const text = node.nodeValue;
    TCY.lastIndex = 0;
    let match;
    let last = 0;
    let out = null;
    while ((match = TCY.exec(text))) {
      out ||= document.createDocumentFragment();
      if (match.index > last) out.appendChild(document.createTextNode(text.slice(last, match.index)));
      const span = document.createElement('span');
      span.className = 'tcy';
      span.textContent = match[0];
      out.appendChild(span);
      last = match.index + match[0].length;
    }
    if (out) {
      if (last < text.length) out.appendChild(document.createTextNode(text.slice(last)));
      node.replaceWith(out);
    }
  }
}

/** DOM の仕上げ（同期処理） */
export function decorate(fragment, docPath) {
  resolveMedia(fragment, docPath);
  wrapFigures(fragment);
  wrapTables(fragment);
  buildToc(fragment);
  wrapTateChuYoko(fragment);
}

// ------------------------------------------------------------
// 数式
// ------------------------------------------------------------

const mathCache = new Map();

export async function renderMath(fragment) {
  const nodes = fragment.querySelectorAll('[data-tex]');
  if (nodes.length === 0) return;
  try {
    await ensureKatex();
  } catch (e) {
    console.warn(e);
    return;
  }
  // \def や \newcommand を文書全体で共有する
  const macros = {};
  for (const el of nodes) {
    const display = el.classList.contains('math-block');
    let tex = el.dataset.tex;
    if (el.dataset.tag) tex += `\\tag{${el.dataset.tag}}`;
    const usesMacro = /\\(?:def|gdef|newcommand|renewcommand)/.test(tex);
    const key = `${display ? 'D' : 'I'}:${tex}`;
    let html = mathCache.get(key);
    if (html == null || usesMacro || Object.keys(macros).length > 0) {
      html = window.katex.renderToString(tex, {
        displayMode: display,
        throwOnError: false,
        strict: 'ignore',
        trust: false,
        macros,
        globalGroup: true,
      });
      if (!usesMacro && Object.keys(macros).length === 0) {
        if (mathCache.size > 2000) mathCache.clear();
        mathCache.set(key, html);
      }
    }
    el.innerHTML = html;
  }
}

// ------------------------------------------------------------
// mermaid
// ------------------------------------------------------------

const diagramCache = new Map();
let mermaidReady;
let mermaidTheme = null;
let diagramSeq = 0;

export async function renderDiagrams(fragment, appearance) {
  const blocks = fragment.querySelectorAll('.diagram[data-diagram="mermaid"]');
  if (blocks.length === 0) return;
  try {
    mermaidReady ||= loadScript('mermaid/mermaid.min.js');
    await mermaidReady;
  } catch (e) {
    console.warn(e);
    return;
  }
  const theme = appearance === 'dark' ? 'dark' : 'neutral';
  if (mermaidTheme !== theme) {
    window.mermaid.initialize({
      startOnLoad: false,
      securityLevel: 'strict',
      theme,
      fontFamily: '"Hiragino Sans", -apple-system, sans-serif',
    });
    mermaidTheme = theme;
  }
  for (const block of blocks) {
    const src = block.querySelector('.diagram-src')?.textContent ?? '';
    const key = `${theme}:${src}`;
    let svg = diagramCache.get(key);
    if (svg == null) {
      const id = `shiori-mermaid-${++diagramSeq}`;
      try {
        ({ svg } = await window.mermaid.render(id, src));
        if (diagramCache.size > 200) diagramCache.clear();
        diagramCache.set(key, svg);
      } catch (e) {
        document.getElementById(`d${id}`)?.remove();
        document.getElementById(id)?.remove();
        const pre = document.createElement('pre');
        pre.className = 'diagram-error';
        pre.textContent = `mermaid の描画に失敗しました\n${e.message || e}\n\n${src}`;
        block.replaceChildren(pre);
        continue;
      }
    }
    block.innerHTML = svg;
  }
}

// ------------------------------------------------------------
// ![[...]] の解決（実体の場所はアプリ側に問い合わせる）
// ------------------------------------------------------------

const MAX_EMBED_DEPTH = 3;

export async function resolveWikiEmbeds(fragment, docPath, options, depth = 0) {
  const images = fragment.querySelectorAll('img[data-wiki-src]');
  for (const img of images) {
    const res = await ask('resolveWikilink', { target: img.dataset.wikiSrc, from: docPath });
    if (res?.path) img.src = fileUrl(res.path);
    else {
      const missing = document.createElement('span');
      missing.className = 'wiki-missing';
      missing.textContent = img.dataset.wikiSrc;
      img.replaceWith(missing);
    }
  }
  // 画像だけの段落を図版にするため、解決後にもう一度まとめる
  if (images.length) wrapFigures(fragment);

  const embeds = fragment.querySelectorAll('.wiki-embed[data-wiki-embed]');
  for (const span of embeds) {
    const target = span.dataset.wikiEmbed;
    const res = depth < MAX_EMBED_DEPTH ? await ask('readWikilink', { target, from: docPath }) : null;
    if (res?.text == null) {
      span.className = 'wiki-missing';
      continue;
    }
    const inner = sanitize(renderMarkdown(res.text, { ...options, showProperties: false }).html);
    decorate(inner, res.path);
    await renderMath(inner);
    await resolveWikiEmbeds(inner, res.path, options, depth + 1);
    const box = document.createElement('div');
    box.className = 'embed';
    const head = document.createElement('a');
    head.className = 'embed-title wikilink';
    head.href = '#';
    head.dataset.wikilink = target;
    head.textContent = target;
    box.append(head, inner);
    // 埋め込み側の行番号はこの文書の行ではないので消す
    box.querySelectorAll('[data-line]').forEach((el) => el.removeAttribute('data-line'));
    box.querySelectorAll('.task-checkbox').forEach((el) => { el.disabled = true; });
    const para = span.parentElement;
    if (para?.tagName === 'P' && para.childNodes.length === 1) para.replaceWith(box);
    else span.replaceWith(box);
  }
}

// ------------------------------------------------------------
// コードブロックのコピーボタン
// ------------------------------------------------------------

export function addCodeButtons(fragment) {
  for (const block of fragment.querySelectorAll('.code-block')) {
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'copy-btn';
    button.textContent = 'コピー';
    block.appendChild(button);
  }
}
