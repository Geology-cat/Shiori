// ビューワー本体。Swift 側からは window.Shiori の API だけを呼ぶ。
import { renderMarkdown } from './markdown.js';
import { sanitize } from './sanitize.js';
import { decorate, renderMath, renderDiagrams, resolveWikiEmbeds, addCodeButtons } from './postprocess.js';
import * as scroll from './scroll.js';
import * as find from './find.js';
import { initLightbox, openLightbox } from './lightbox.js';
import { post } from './bridge.js';

const root = document.documentElement;
const scroller = document.getElementById('scroller');
const content = document.getElementById('content');

const state = {
  source: '',
  path: null,
  renderOptions: { breaks: true, showProperties: true },
  token: 0,
  mode: 'empty', // 'empty' | 'markdown' | 'image'
  appearance: null,
};

// ------------------------------------------------------------
// 描画
// ------------------------------------------------------------

function appearance() {
  return root.dataset.appearance === 'dark' ? 'dark' : 'light';
}

/** Markdown 全文を描画する。古い描画要求は途中で破棄する */
async function render({ markdown, path = null, line = null, keepPosition = false }) {
  const token = ++state.token;
  const previousLine = keepPosition ? scroll.topLine() : null;
  state.source = markdown;
  state.path = path;
  state.mode = 'markdown';
  find.clear();

  const result = renderMarkdown(markdown, state.renderOptions);
  const fragment = sanitize(result.html);
  decorate(fragment, path);

  // 数式と図はオフスクリーンで描画してから差し替える（ちらつき防止）
  await renderMath(fragment);
  if (token !== state.token) return { stale: true };
  await renderDiagrams(fragment, appearance());
  if (token !== state.token) return { stale: true };
  await resolveWikiEmbeds(fragment, path, state.renderOptions);
  if (token !== state.token) return { stale: true };
  addCodeButtons(fragment);

  content.className = 'shiori-doc';
  content.replaceChildren(fragment);
  root.dataset.lang = detectLanguage(content.textContent);
  content.lang = root.dataset.lang;

  const target = line ?? previousLine;
  scroll.resetInteraction();
  if (target != null && target > 0) scroll.scrollToLine(target);
  else scroll.scrollToStart();

  // 画像の読込でレイアウトが動くので、ユーザーが触っていなければ位置を合わせ直す
  const images = Array.from(content.querySelectorAll('img')).filter((img) => !img.complete);
  if (images.length) {
    await Promise.allSettled(images.map((img) => img.decode()));
    if (token === state.token && target != null && target > 0 && !scroll.hasInteracted()) {
      scroll.scrollToLine(target);
    }
  }
  scroll.notify();
  return { title: result.title };
}

/** 画像ファイルをタブに表示する */
function showImage({ path }) {
  state.token += 1;
  state.mode = 'image';
  state.path = path;
  find.clear();
  const url = 'shiori-file://local' + path.split('/').map(encodeURIComponent).join('/');
  const wrap = document.createElement('div');
  wrap.className = 'image-view';
  const img = document.createElement('img');
  img.src = url;
  img.alt = path.split('/').pop();
  img.addEventListener('load', () => {
    post('imageInfo', { width: img.naturalWidth, height: img.naturalHeight });
  });
  wrap.appendChild(img);
  img.addEventListener('click', () => wrap.classList.toggle('actual-size'));
  content.className = 'shiori-doc image-mode';
  content.replaceChildren(wrap);
  scroll.scrollToStart();
}

/** 閲覧中の内容で描画し直す（テーマ変更で図の配色を変える場合など） */
function rerender() {
  if (state.mode === 'markdown') {
    return render({ markdown: state.source, path: state.path, keepPosition: true });
  }
  return Promise.resolve();
}

function clear() {
  state.token += 1;
  state.mode = 'empty';
  state.source = '';
  state.path = null;
  content.className = 'shiori-doc';
  content.replaceChildren();
  find.clear();
}

function detectLanguage(text) {
  const sample = text.slice(0, 4000);
  const cjk = (sample.match(/[぀-ヿ㐀-鿿]/g) || []).length;
  const latin = (sample.match(/[A-Za-z]/g) || []).length;
  // コードや数式で欧文が多くても、和文が 1 割ほどあれば日本語の文書とみなす
  return cjk * 8 >= latin ? 'ja' : 'en';
}

// ------------------------------------------------------------
// 表示設定（ページを再ロードせずに差し替える）
// ------------------------------------------------------------

function setCssVar(name, value) {
  if (value == null || value === '' || value === 0) root.style.removeProperty(name);
  else root.style.setProperty(name, value);
}

function setStylesheet(id, href) {
  const link = document.getElementById(id);
  if (!href) {
    link.disabled = true;
    link.removeAttribute('href');
    return Promise.resolve();
  }
  link.disabled = false;
  if (link.getAttribute('href') === href) return Promise.resolve();
  return new Promise((resolve) => {
    link.onload = link.onerror = () => resolve();
    link.setAttribute('href', href);
  });
}

async function applySettings(s) {
  const line = scroll.topLine();
  const writingChanged = root.dataset.writing !== s.writing;

  await Promise.all([setStylesheet('theme-link', s.themeHref), setStylesheet('custom-link', s.customHref)]);

  root.dataset.theme = s.theme;
  root.dataset.writing = s.writing;
  root.dataset.headingNumbers = s.headingNumbers ? 'on' : 'off';
  root.dataset.indent = s.indent ? 'on' : 'off';
  root.dataset.justify = s.justify ? 'on' : 'off';
  setCssVar('--user-scale', s.fontScale && s.fontScale !== 1 ? String(s.fontScale) : null);
  setCssVar('--user-line-height', s.lineHeight ? String(s.lineHeight) : null);
  setCssVar('--user-measure', s.measure ? `${s.measure}em` : null);
  setCssVar('--user-font', s.fontFamily || null);
  setCssVar('--user-code-font', s.codeFontFamily || null);
  scroll.setClickToPage(!!s.clickToPage);

  const breaksChanged = state.renderOptions.breaks !== s.breaks;
  const propsChanged = state.renderOptions.showProperties !== s.showProperties;
  state.renderOptions = { breaks: !!s.breaks, showProperties: !!s.showProperties };

  if (breaksChanged || propsChanged) {
    await render({ markdown: state.source, path: state.path, line });
  } else if (writingChanged) {
    // 縦⇔横ではスクロール軸が変わるので、行番号を基準に位置を合わせ直す
    scroll.scrollToLine(line);
  } else if (line > 0) {
    scroll.scrollToLine(line);
  }
  scroll.notify();
  return true;
}

function syncAppearance() {
  const dark = window.matchMedia('(prefers-color-scheme: dark)').matches;
  const next = dark ? 'dark' : 'light';
  if (root.dataset.forceAppearance) {
    root.dataset.appearance = root.dataset.forceAppearance;
    return;
  }
  if (root.dataset.appearance === next) return;
  root.dataset.appearance = next;
  // mermaid は描画時に配色が決まるので描き直す
  if (state.mode === 'markdown' && content.querySelector('.diagram')) rerender();
}

// ------------------------------------------------------------
// 書き出し
// ------------------------------------------------------------

/** 描画済みの本文を、外部スクリプトなしで表示できる形で返す */
function exportDocument() {
  const clone = content.cloneNode(true);
  clone.querySelectorAll('.copy-btn').forEach((el) => el.remove());
  return {
    html: clone.innerHTML,
    hasMath: !!content.querySelector('.katex'),
    writing: root.dataset.writing,
    theme: root.dataset.theme,
    appearance: appearance(),
    headingNumbers: root.dataset.headingNumbers,
    indent: root.dataset.indent,
    justify: root.dataset.justify,
    lang: content.lang || 'ja',
    style: root.getAttribute('style') || '',
  };
}

/** 印刷・PDF 用に常にライト配色で描画する */
function setForcedAppearance(value) {
  if (value) {
    root.dataset.forceAppearance = value;
    root.dataset.appearance = value;
  } else {
    delete root.dataset.forceAppearance;
    syncAppearance();
  }
}

// ------------------------------------------------------------
// 初期化
// ------------------------------------------------------------

scroll.init({ scroller, content });
initLightbox();
syncAppearance();
window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', syncAppearance);

// 本文内のクリックをまとめて扱う
content.addEventListener('click', (e) => {
  const target = e.target;
  if (!(target instanceof Element)) return;

  const copy = target.closest('.copy-btn');
  if (copy) {
    e.preventDefault();
    const code = copy.closest('.code-block')?.querySelector('code');
    post('copy', { text: code?.textContent ?? '' });
    copy.textContent = 'コピーしました';
    setTimeout(() => { copy.textContent = 'コピー'; }, 1200);
    return;
  }

  const checkbox = target.closest('.task-checkbox');
  if (checkbox) {
    post('toggleTask', { line: Number(checkbox.dataset.taskLine), checked: checkbox.checked });
    return;
  }

  const wiki = target.closest('a[data-wikilink]');
  if (wiki) {
    e.preventDefault();
    post('openWikilink', { target: wiki.dataset.wikilink, newTab: e.metaKey });
    return;
  }

  const anchor = target.closest('a[href]');
  if (anchor) {
    e.preventDefault();
    openHref(anchor.getAttribute('href'), e.metaKey);
    return;
  }

  const img = target.closest('img');
  if (img && !target.closest('.image-view')) {
    openLightbox(img);
    return;
  }

  scroll.handleContentClick(e);
});

function openHref(href, newTab) {
  if (!href) return;
  if (href.startsWith('#')) {
    scrollToFragment(href.slice(1));
    return;
  }
  // scheme 付きはそのまま外部へ（http, mailto など）
  if (/^[a-z][a-z0-9+.-]*:/i.test(href)) {
    if (href.startsWith('shiori-file://local')) {
      const u = new URL(href);
      post('openPath', { path: decodeURIComponent(u.pathname), fragment: u.hash.slice(1), newTab });
    } else {
      post('openExternal', { url: href });
    }
    return;
  }
  if (!state.path) return;
  const dir = state.path.slice(0, state.path.lastIndexOf('/') + 1);
  const base = 'shiori-file://local' + dir.split('/').map(encodeURIComponent).join('/');
  const u = new URL(href, base);
  post('openPath', { path: decodeURIComponent(u.pathname), fragment: decodeURIComponent(u.hash.slice(1)), newTab });
}

function scrollToFragment(fragment) {
  if (!fragment) return false;
  let id = fragment;
  try { id = decodeURIComponent(fragment); } catch { /* そのまま使う */ }
  const el = document.getElementById(id) || document.getElementsByName(id)[0];
  if (!el) return false;
  // 閉じた折りたたみの中なら開く
  for (let p = el.parentElement; p; p = p.parentElement) {
    if (p.tagName === 'DETAILS') p.open = true;
  }
  el.scrollIntoView({ block: 'start', inline: 'start' });
  return true;
}

window.Shiori = {
  render,
  rerender,
  clear,
  showImage,
  applySettings,
  setForcedAppearance,
  exportDocument,
  scrollToFragment,
  verticalPageSlices: (width) => scroll.verticalPageSlices(width),
  // 書き出し用: 本文の右端から start の位置を画面の右端へ動かす
  shiftForExport: (start) => {
    content.style.transform = `translateX(${start}px)`;
    return new Promise((resolve) => setTimeout(resolve, 50));
  },
  setExporting: (on) => {
    if (on) root.dataset.exporting = 'on';
    else delete root.dataset.exporting;
  },
  topLine: () => scroll.topLine(),
  scrollToLine: (n) => scroll.scrollToLine(n),
  page: (dir) => scroll.page(dir),
  find: (query) => find.run(query, content),
  findNext: (dir) => find.next(dir),
  clearFind: () => find.clear(),
};

post('ready', {});
