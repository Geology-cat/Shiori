// スクロール制御。縦書きでは軸が横になり起点が右端になるので、差異をここに閉じ込める。
import { post } from './bridge.js';

let scroller;
let content;
let interacted = false;
let clickToPage = false;
let notifyTimer = null;
const root = document.documentElement;

const isVertical = () => root.dataset.writing === 'vertical';

export function init(refs) {
  ({ scroller, content } = refs);
  scroller.addEventListener('scroll', schedule, { passive: true });
  scroller.addEventListener('wheel', onWheel, { passive: false });
  window.addEventListener('keydown', onKeyDown);
  window.addEventListener('resize', schedule);
}

export function resetInteraction() {
  interacted = false;
}
export function hasInteracted() {
  return interacted;
}
export function setClickToPage(value) {
  clickToPage = value;
}

function canScrollInside(el, dx, dy) {
  // pre や表など内側に独自のスクロールを持つ要素では、そちらを優先する
  for (let node = el; node && node !== scroller; node = node.parentElement) {
    if (dy && node.scrollHeight > node.clientHeight + 1) {
      const style = getComputedStyle(node);
      if (/(auto|scroll)/.test(style.overflowY)) {
        const atEnd = dy > 0
          ? node.scrollTop + node.clientHeight >= node.scrollHeight - 1
          : node.scrollTop <= 0;
        if (!atEnd) return true;
      }
    }
    if (dx && node.scrollWidth > node.clientWidth + 1) {
      const style = getComputedStyle(node);
      if (/(auto|scroll)/.test(style.overflowX)) return true;
    }
  }
  return false;
}

function onWheel(e) {
  interacted = true;
  if (!isVertical()) return;
  if (!(e.target instanceof Element)) return;
  // 縦ホイールを横スクロールへ読み替える（下へ回すと読み進む＝左へ）
  if (Math.abs(e.deltaY) > Math.abs(e.deltaX)) {
    if (canScrollInside(e.target, 0, e.deltaY)) return;
    e.preventDefault();
    scroller.scrollLeft -= e.deltaY;
  }
}

function lineExtent() {
  const lh = parseFloat(getComputedStyle(content).lineHeight);
  return Number.isFinite(lh) && lh > 0 ? lh : 28;
}

/** 1 画面ぶん進める・戻す。行の途中で切れないよう行単位に丸める */
export function page(direction) {
  interacted = true;
  const line = lineExtent();
  if (isVertical()) {
    const lines = Math.max(1, Math.floor(scroller.clientWidth / line) - 1);
    scroller.scrollBy({ left: -direction * lines * line, behavior: 'smooth' });
  } else {
    const lines = Math.max(1, Math.floor(scroller.clientHeight / line) - 1);
    scroller.scrollBy({ top: direction * lines * line, behavior: 'smooth' });
  }
}

function stepLine(direction) {
  interacted = true;
  const amount = direction * lineExtent() * 2;
  if (isVertical()) scroller.scrollBy({ left: -amount });
  else scroller.scrollBy({ top: amount });
}

function onKeyDown(e) {
  if (e.metaKey || e.ctrlKey || e.altKey) return;
  if (e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement) return;
  const vertical = isVertical();
  switch (e.key) {
    case ' ':
      page(e.shiftKey ? -1 : 1);
      break;
    case 'PageDown':
      page(1);
      break;
    case 'PageUp':
      page(-1);
      break;
    case 'Home':
      interacted = true;
      scrollToStart();
      break;
    case 'End':
      interacted = true;
      scrollToEnd();
      break;
    case 'ArrowDown':
      stepLine(1);
      break;
    case 'ArrowUp':
      stepLine(-1);
      break;
    case 'ArrowLeft':
      if (vertical) page(1);
      else return;
      break;
    case 'ArrowRight':
      if (vertical) page(-1);
      else return;
      break;
    default:
      return;
  }
  e.preventDefault();
}

/** クリックでのページ送り（画面の端をクリック） */
export function handleContentClick(e) {
  if (!clickToPage) return;
  if (window.getSelection()?.toString()) return;
  const x = e.clientX / window.innerWidth;
  const y = e.clientY / window.innerHeight;
  if (isVertical()) {
    if (x < 0.3) page(1);
    else if (x > 0.7) page(-1);
  } else {
    if (y > 0.7) page(1);
    else if (y < 0.3) page(-1);
  }
}

export function scrollToStart() {
  if (isVertical()) scroller.scrollLeft = 0;
  else scroller.scrollTop = 0;
}

export function scrollToEnd() {
  if (isVertical()) scroller.scrollLeft = -(scroller.scrollWidth - scroller.clientWidth);
  else scroller.scrollTop = scroller.scrollHeight;
}

/** 画面の先頭に見えているブロックのソース行を返す */
export function topLine() {
  const box = scroller.getBoundingClientRect();
  const vertical = isVertical();
  let line = 0;
  for (const el of content.querySelectorAll('[data-line]')) {
    const r = el.getBoundingClientRect();
    if (r.width === 0 && r.height === 0) continue; // 閉じた折りたたみの中など
    const started = vertical ? r.right <= box.right + 4 : r.top <= box.top + 4;
    if (!started) break;
    const n = Number(el.dataset.line);
    if (n >= line) line = n;
  }
  return line;
}

/** 指定行を含むブロックが画面の先頭に来るようにスクロールする */
export function scrollToLine(n) {
  let best = null;
  for (const el of content.querySelectorAll('[data-line]')) {
    const line = Number(el.dataset.line);
    if (line > n) break;
    const r = el.getBoundingClientRect();
    if (r.width === 0 && r.height === 0) continue;
    best = el;
  }
  if (!best || n <= 0) {
    scrollToStart();
    return;
  }
  best.scrollIntoView({ block: 'start', inline: 'nearest' });
}

/**
 * 縦書きを紙に割り付けるための改ページ位置を計算する。
 * WebKit の印刷は縦書きを横方向にページ分割できないので、行が切れない位置を自前で探す。
 * 位置は本文の右端からの距離で返す。
 */
export function verticalPageSlices(pageWidth) {
  const ISLANDS = '.code-block, .table-wrap, .math-block, .diagram, .properties, .toc, figure, img, svg, .callout-title';
  const box = content.getBoundingClientRect();
  const right = box.right;
  const intervals = [];
  const add = (rect) => {
    if (rect.width > 0 && rect.height > 0) intervals.push([right - rect.right, right - rect.left]);
  };

  for (const el of content.querySelectorAll(ISLANDS)) add(el.getBoundingClientRect());

  // 本文の行はテキストノードの断片として測る（ルビの分も含まれる）
  const walker = document.createTreeWalker(content, NodeFilter.SHOW_TEXT);
  const range = document.createRange();
  while (walker.nextNode()) {
    const node = walker.currentNode;
    if (!node.nodeValue.trim() || node.parentElement?.closest(ISLANDS)) continue;
    range.selectNodeContents(node);
    for (const rect of range.getClientRects()) add(rect);
  }
  if (intervals.length === 0) return [];

  // 重なりをまとめて「文字がある帯」の列にする
  intervals.sort((a, b) => a[0] - b[0]);
  const bands = [];
  for (const [start, end] of intervals) {
    const last = bands[bands.length - 1];
    if (last && start <= last[1] + 0.5) last[1] = Math.max(last[1], end);
    else bands.push([start, end]);
  }

  const slices = [];
  let index = 0;
  while (index < bands.length) {
    const start = Math.floor(bands[index][0]) - 1;
    let end = bands[index][1];
    let next = index + 1;
    while (next < bands.length && bands[next][1] - start <= pageWidth) {
      end = bands[next][1];
      next += 1;
    }
    if (end - start > pageWidth) {
      // 1 ページに収まらない大きな要素は諦めて途中で切る
      slices.push({ start, end: start + pageWidth });
      bands[index][0] = start + pageWidth;
      continue;
    }
    slices.push({ start, end: Math.ceil(end) + 1 });
    index = next;
  }
  return slices;
}

function progress() {
  if (isVertical()) {
    const max = scroller.scrollWidth - scroller.clientWidth;
    return max > 0 ? Math.min(1, -scroller.scrollLeft / max) : 1;
  }
  const max = scroller.scrollHeight - scroller.clientHeight;
  return max > 0 ? Math.min(1, scroller.scrollTop / max) : 1;
}

function schedule() {
  const bar = document.getElementById('progress');
  if (bar) bar.style.setProperty('--progress', String(progress()));
  if (notifyTimer) return;
  notifyTimer = setTimeout(() => {
    notifyTimer = null;
    notify();
  }, 180);
}

export function notify() {
  const value = progress();
  const bar = document.getElementById('progress');
  if (bar) bar.style.setProperty('--progress', String(value));
  post('scroll', { topLine: topLine(), progress: value });
}
