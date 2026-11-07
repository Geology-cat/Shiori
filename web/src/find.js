// 閲覧モードの検索。CSS Custom Highlight API で全一致を塗り、件数も返す。
// ノードをまたぐ一致（縦中横の span をまたぐ場合など）も拾えるよう、本文を連結して検索する。
const HL_ALL = 'shiori-find';
const HL_CURRENT = 'shiori-find-current';
const MAX_MATCHES = 5000;

let ranges = [];
let index = -1;

const supported = typeof CSS !== 'undefined' && 'highlights' in CSS;

export function clear() {
  ranges = [];
  index = -1;
  if (supported) {
    CSS.highlights.delete(HL_ALL);
    CSS.highlights.delete(HL_CURRENT);
  }
}

function collectText(rootEl) {
  const walker = document.createTreeWalker(rootEl, NodeFilter.SHOW_TEXT, {
    acceptNode(node) {
      const parent = node.parentElement;
      if (!parent) return NodeFilter.FILTER_REJECT;
      // KaTeX の内部表現やコピーボタンは検索対象にしない
      if (parent.closest('.katex-html, .copy-btn, .diagram, style, script')) return NodeFilter.FILTER_REJECT;
      return NodeFilter.FILTER_ACCEPT;
    },
  });
  const nodes = [];
  let text = '';
  while (walker.nextNode()) {
    nodes.push({ node: walker.currentNode, start: text.length });
    text += walker.currentNode.nodeValue;
  }
  return { nodes, text };
}

function locate(nodes, offset) {
  let lo = 0;
  let hi = nodes.length - 1;
  while (lo < hi) {
    const mid = (lo + hi + 1) >> 1;
    if (nodes[mid].start <= offset) lo = mid;
    else hi = mid - 1;
  }
  return { node: nodes[lo].node, offset: offset - nodes[lo].start };
}

export function run(query, rootEl) {
  clear();
  if (!query) return { count: 0, index: -1 };
  const { nodes, text } = collectText(rootEl);
  if (nodes.length === 0) return { count: 0, index: -1 };

  const haystack = text.toLowerCase();
  const needle = query.toLowerCase();
  let from = 0;
  while (ranges.length < MAX_MATCHES) {
    const at = haystack.indexOf(needle, from);
    if (at < 0) break;
    const a = locate(nodes, at);
    const b = locate(nodes, at + needle.length);
    const range = document.createRange();
    range.setStart(a.node, a.offset);
    range.setEnd(b.node, b.offset);
    ranges.push(range);
    from = at + Math.max(1, needle.length);
  }
  if (ranges.length === 0) return { count: 0, index: -1 };
  if (supported) CSS.highlights.set(HL_ALL, new Highlight(...ranges));
  return moveTo(firstVisibleIndex());
}

function firstVisibleIndex() {
  const scroller = document.getElementById('scroller');
  const box = scroller.getBoundingClientRect();
  const vertical = document.documentElement.dataset.writing === 'vertical';
  for (let i = 0; i < ranges.length; i++) {
    const r = ranges[i].getBoundingClientRect();
    if (vertical ? r.right <= box.right : r.top >= box.top) return i;
  }
  return 0;
}

function moveTo(i) {
  if (ranges.length === 0) return { count: 0, index: -1 };
  index = (i + ranges.length) % ranges.length;
  const range = ranges[index];
  if (supported) CSS.highlights.set(HL_CURRENT, new Highlight(range));

  // 閉じた折りたたみの中なら開く
  for (let p = range.startContainer.parentElement; p; p = p.parentElement) {
    if (p.tagName === 'DETAILS') p.open = true;
  }
  const scroller = document.getElementById('scroller');
  const box = scroller.getBoundingClientRect();
  const r = range.getBoundingClientRect();
  const inView = r.top >= box.top && r.bottom <= box.bottom && r.left >= box.left && r.right <= box.right;
  if (!inView) {
    scroller.scrollBy({
      left: r.left + r.width / 2 - (box.left + box.width / 2),
      top: r.top + r.height / 2 - (box.top + box.height / 2),
    });
  }
  return { count: ranges.length, index };
}

export function next(direction) {
  if (ranges.length === 0) return { count: 0, index: -1 };
  return moveTo(index + direction);
}
