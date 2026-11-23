// ページめくり表示（読書テーマ）。
// CSS の段組みで本文をページに割り、スクロールではなく transform でページを送る。
// 段組みの段は行の進む向きに並ぶので、横書きでは右へ、縦書きでは下へページが並ぶ。
// どちらも「段が並ぶ向き」をページの並ぶ向きとして扱い、画面には 1 ページずつ見せる。
// scroll.js からだけ呼ぶ（スクロールの差異は scroll.js に閉じ込める方針のため）。

const root = document.documentElement;
let scroller;
let content;
let pager;

let enabled = false;
let columns = 1;
/** 1 ページの送り幅（px）。段の幅と段間から決まり、ページをめくってもずれが溜まらない */
let pitch = 0;
let pageIndex = 0;
let pageCount = 1;
/** レイアウトを決めた条件。変わったら位置の記憶を捨てる */
let layoutKey = '';
/** 最後にプログラムで合わせた位置。ユーザーがめくっていなければそのまま返す */
let pinned = null;
/** 最後に分かっている読書位置（窓の大きさが変わったときに戻す先） */
let lastPosition = 0;

let wheelAccum = 0;
let wheelLocked = false;
let wheelTimer = null;

const isVertical = () => root.dataset.writing === 'vertical';

export function init(refs) {
  ({ scroller, content } = refs);
  pager = document.createElement('div');
  pager.id = 'pager';
  pager.setAttribute('aria-hidden', 'true');
  document.body.appendChild(pager);
}

export function configure({ paged, columns: n }) {
  enabled = !!paged;
  columns = n === 2 ? 2 : 1;
  root.dataset.paged = enabled ? 'on' : 'off';
}

/** 今ページめくりで表示しているか（画像タブや空の文書では使わない） */
export function active() {
  return enabled && !content.classList.contains('image-mode') && content.childElementCount > 0;
}

function px(value) {
  return `${Math.round(value * 100) / 100}px`;
}

function measureLength(fontSize) {
  const style = getComputedStyle(root);
  const raw = (style.getPropertyValue('--user-measure') || style.getPropertyValue('--theme-measure')).trim();
  const n = parseFloat(raw);
  if (!Number.isFinite(n) || n <= 0) return fontSize * 40;
  return raw.endsWith('px') ? n : n * fontSize;
}

const VARS = ['--page-inline', '--page-block', '--page-margin', '--page-columns', '--page-pad-start', '--page-pad-end', '--col-w', '--col-h'];

function clearLayout() {
  for (const name of VARS) content.style.removeProperty(name);
  content.style.removeProperty('transform');
  pitch = 0;
  pageIndex = 0;
  pageCount = 1;
  layoutKey = '';
  pinned = null;
  updatePager();
}

/** 窓の大きさと設定からページの寸法を決め、ページ数を数え直す */
export function layout() {
  if (!active()) {
    clearLayout();
    return;
  }
  const vertical = isVertical();
  const W = scroller.clientWidth;
  const H = scroller.clientHeight;
  const fontSize = parseFloat(getComputedStyle(content).fontSize) || 18;
  // ページが並ぶ向き（＝行の向き）の長さと、それに直交する向きの長さ
  const inline = vertical ? H : W;
  const block = vertical ? W : H;

  const minMargin = Math.round(fontSize * (vertical ? 1.75 : 2.25));
  let n = columns;
  // 2 段にすると 1 行が短くなりすぎる窓では 1 段にする
  if (n === 2 && inline / 2 - 2 * minMargin < fontSize * 10) n = 1;
  // 1 行の長さを本文幅に収めるため、広い窓では余白を広げる
  const margin = Math.max(minMargin, Math.floor((inline / n - measureLength(fontSize)) / 2));
  const columnSize = Math.max(fontSize * 4, Math.floor((inline - 2 * n * margin) / n));
  // 段間を余白の 2 倍にすると、次のページの最初の段がちょうど 1 ページ先に来る
  pitch = n * (columnSize + 2 * margin);

  const padStart = Math.round(fontSize * 2.5);
  const padEnd = Math.round(fontSize * (vertical ? 2.5 : 3));
  const columnBlock = block - padStart - padEnd;

  const s = content.style;
  s.setProperty('--page-inline', px(pitch));
  s.setProperty('--page-block', px(block));
  s.setProperty('--page-margin', px(margin));
  s.setProperty('--page-columns', String(n));
  s.setProperty('--page-pad-start', px(padStart));
  s.setProperty('--page-pad-end', px(padEnd));
  s.setProperty('--col-w', px(vertical ? columnBlock : columnSize));
  s.setProperty('--col-h', px(vertical ? columnSize : columnBlock));

  // ページ数は移動をいったん外して、段がどこまで続いているかで数える
  s.transform = 'none';
  const extent = vertical ? scroller.scrollHeight : scroller.scrollWidth;
  pageCount = Math.max(1, Math.ceil((extent - 1) / pitch));
  pageIndex = Math.min(pageIndex, pageCount - 1);
  const key = `${W}x${H}:${n}:${root.dataset.writing}:${fontSize}:${pitch}`;
  if (key !== layoutKey) pinned = null;
  layoutKey = key;
  applyTransform();
}

function applyTransform() {
  const offset = -pageIndex * pitch;
  content.style.transform = isVertical() ? `translateY(${offset}px)` : `translateX(${offset}px)`;
  if (scroller.scrollTop || scroller.scrollLeft) {
    scroller.scrollTop = 0;
    scroller.scrollLeft = 0;
  }
  updatePager();
}

function updatePager() {
  if (!pager) return;
  if (!active()) {
    pager.hidden = true;
    pager.textContent = '';
    return;
  }
  pager.hidden = false;
  pager.textContent = `${pageIndex + 1} / ${pageCount}`;
}

/** ページの移動を目で追えるよう、めくる向きから少しだけ滑り込ませる */
function animateTurn(direction) {
  if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;
  // 横書きは次のページが右から、縦書き（右から左へ読む）は左から入ってくる
  const dx = (isVertical() ? -1 : 1) * direction * 28;
  scroller.animate(
    [{ opacity: 0.3, transform: `translateX(${dx}px)` }, { opacity: 1, transform: 'none' }],
    { duration: 200, easing: 'cubic-bezier(0.2, 0.7, 0.3, 1)' },
  );
}

export function go(index, { animate = false } = {}) {
  const next = Math.max(0, Math.min(pageCount - 1, index));
  if (next === pageIndex) return false;
  const direction = Math.sign(next - pageIndex);
  pageIndex = next;
  pinned = null;
  applyTransform();
  if (animate) animateTurn(direction);
  return true;
}

export function turn(direction) {
  return go(pageIndex + direction, { animate: true });
}

export function first() {
  return go(0);
}

export function last() {
  return go(pageCount - 1);
}

export function count() {
  return active() ? pageCount : 0;
}

export function progress() {
  return pageCount > 1 ? pageIndex / (pageCount - 1) : 1;
}

/** 窓の大きさが変わったら、同じ箇所が見えるように割り付け直す */
export function relayoutKeepingPosition() {
  if (!active()) return;
  const position = lastPosition;
  layout();
  scrollToPosition(position);
}

// ------------------------------------------------------------
// ページと位置の変換
// ------------------------------------------------------------

/** 矩形が何ページ目にあるか（段の並ぶ向きの始点で判定する） */
function pageOf(rect) {
  const origin = content.getBoundingClientRect();
  const start = isVertical() ? rect.top - origin.top : rect.left - origin.left;
  return Math.max(0, Math.floor((start + 1) / pitch));
}

function firstRect(target) {
  const rects = target.getClientRects();
  for (const r of rects) {
    if (r.width > 0 || r.height > 0) return r;
  }
  return null;
}

/** 要素や範囲が見えるページへ移る（検索、目次、ページ内リンク） */
export function reveal(target) {
  const r = firstRect(target);
  if (!r) return false;
  go(pageOf(r));
  return true;
}

export function isOnCurrentPage(rect) {
  return pageOf(rect) === pageIndex;
}

export function isAtOrAfterCurrentPage(rect) {
  return pageOf(rect) >= pageIndex;
}

function lineSpan(el) {
  const start = Number(el.dataset.line);
  const end = el.dataset.lineEnd != null ? Number(el.dataset.lineEnd) : start + 1;
  return [start, Math.max(start + 1, end)];
}

function textLength(el) {
  return el.textContent.length;
}

/** 要素の先頭から (node, offset) までの文字数 */
function textOffset(el, node, offset) {
  const walker = document.createTreeWalker(el, NodeFilter.SHOW_TEXT);
  let count = 0;
  while (walker.nextNode()) {
    if (walker.currentNode === node) return count + offset;
    count += walker.currentNode.nodeValue.length;
  }
  return count;
}

/** 要素の先頭から index 文字目の位置 */
function pointAt(el, index) {
  const walker = document.createTreeWalker(el, NodeFilter.SHOW_TEXT);
  let remaining = index;
  let lastNode = null;
  while (walker.nextNode()) {
    const node = walker.currentNode;
    const length = node.nodeValue.length;
    if (remaining < length) return { node, offset: remaining };
    remaining -= length;
    lastNode = node;
  }
  return lastNode ? { node: lastNode, offset: lastNode.nodeValue.length } : null;
}

/** 今のページの読み始めの点（横書きは左上、縦書きは右上） */
function pageStartPoint() {
  const box = scroller.getBoundingClientRect();
  const style = content.style;
  const margin = parseFloat(style.getPropertyValue('--page-margin')) || 0;
  const padStart = parseFloat(style.getPropertyValue('--page-pad-start')) || 0;
  const fontSize = parseFloat(getComputedStyle(content).fontSize) || 18;
  const contentBox = content.getBoundingClientRect();
  if (isVertical()) {
    return {
      x: box.right - padStart - fontSize * 0.5,
      y: contentBox.top + pageIndex * pitch + margin + 2,
    };
  }
  return {
    x: contentBox.left + pageIndex * pitch + margin + 2,
    y: box.top + padStart + fontSize * 0.5,
  };
}

/**
 * 今のページの先頭に見えている位置をソースの行で返す。
 * 整数部が行、小数部はブロックの中を何文字目まで読んだか（段落が何ページにもわたる小説でも、閲覧⇔編集でずれないように）。
 */
export function topPosition() {
  if (!active()) return 0;
  if (pinned && pinned.page === pageIndex && pinned.key === layoutKey) return pinned.position;

  const point = pageStartPoint();
  const caret = document.caretRangeFromPoint?.(point.x, point.y);
  const node = caret?.startContainer;
  const el = node && content.contains(node)
    ? (node.nodeType === Node.ELEMENT_NODE ? node : node.parentElement)?.closest('[data-line]')
    : null;
  if (el && content.contains(el)) {
    const [start, end] = lineSpan(el);
    const total = textLength(el);
    const fraction = total > 0 ? Math.min(0.999, textOffset(el, caret.startContainer, caret.startOffset) / total) : 0;
    lastPosition = start + fraction * (end - start);
    return lastPosition;
  }

  // 文字のない所（図や余白）から始まるページは、このページで最初に始まるブロックを使う
  for (const block of content.querySelectorAll('[data-line]')) {
    const r = firstRect(block);
    if (r && pageOf(r) >= pageIndex) {
      lastPosition = Number(block.dataset.line);
      return lastPosition;
    }
  }
  lastPosition = 0;
  return 0;
}

/** topPosition で得た位置を含むページを開く */
export function scrollToPosition(position) {
  if (!active()) return;
  pinned = null;
  if (!(position > 0)) {
    go(0);
    lastPosition = 0;
    return;
  }
  const line = Math.floor(position);
  let best = null;
  for (const el of content.querySelectorAll('[data-line]')) {
    if (Number(el.dataset.line) > line) break;
    if (!firstRect(el)) continue; // 閉じた折りたたみの中など
    best = el;
  }
  if (!best) {
    go(0);
    lastPosition = 0;
    return;
  }
  const [start, end] = lineSpan(best);
  const fraction = Math.min(1, Math.max(0, (position - start) / (end - start)));
  let rect = null;
  if (fraction > 0) {
    const at = pointAt(best, Math.floor(fraction * textLength(best)));
    if (at) {
      const range = document.createRange();
      range.setStart(at.node, at.offset);
      range.setEnd(at.node, Math.min(at.node.nodeValue.length, at.offset + 1));
      rect = firstRect(range);
    }
  }
  rect = rect || firstRect(best);
  if (rect) go(pageOf(rect));
  lastPosition = position;
  pinned = { position, page: pageIndex, key: layoutKey };
}

// ------------------------------------------------------------
// 入力
// ------------------------------------------------------------

/** ホイールとトラックパッド。慣性で何十回も届くので、1 回の操作で 1 ページだけめくる */
export function wheel(e) {
  e.preventDefault();
  clearTimeout(wheelTimer);
  wheelTimer = setTimeout(() => {
    wheelLocked = false;
    wheelAccum = 0;
  }, 160);
  if (wheelLocked) return false;
  const scale = e.deltaMode === 1 ? 16 : e.deltaMode === 2 ? scroller.clientHeight : 1;
  const dx = e.deltaX * scale;
  const dy = e.deltaY * scale;
  // 横方向のスワイプは、縦書きでは右へ払うと次のページ（左のページ）へ進む
  const delta = Math.abs(dx) > Math.abs(dy) ? (isVertical() ? -dx : dx) : dy;
  wheelAccum += delta;
  if (Math.abs(wheelAccum) < 20) return false;
  const direction = Math.sign(wheelAccum);
  wheelLocked = true;
  wheelAccum = 0;
  return turn(direction);
}

/** 画面の左右の端をクリックしてめくる */
export function click(e) {
  const x = e.clientX / window.innerWidth;
  if (x < 0.3) return turn(isVertical() ? 1 : -1);
  if (x > 0.7) return turn(isVertical() ? -1 : 1);
  return false;
}

/** キー操作。めくったら true */
export function key(e) {
  const vertical = isVertical();
  switch (e.key) {
    case ' ':
      turn(e.shiftKey ? -1 : 1);
      return true;
    case 'PageDown':
    case 'ArrowDown':
      turn(1);
      return true;
    case 'PageUp':
    case 'ArrowUp':
      turn(-1);
      return true;
    case 'ArrowLeft':
      turn(vertical ? 1 : -1);
      return true;
    case 'ArrowRight':
      turn(vertical ? -1 : 1);
      return true;
    case 'Home':
      first();
      return true;
    case 'End':
      last();
      return true;
    default:
      return false;
  }
}
