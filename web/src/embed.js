// 外部の埋め込み（<iframe>）。許可した提供元（Google マップ、YouTube など）だけを通す。
//
// 任意の md を開くアプリなので、iframe はそのまま置かない。
//   1. sanitize の直後に、許可リストにある iframe を「置き場所」（.web-embed）に差し替える。
//      ないものは リンクだけを残す。元の iframe の属性は src・幅・高さ・title しか使わない
//   2. 置き場所はクリックするまで通信しない（環境設定で自動読み込みにもできる）
//   3. viewer.html の CSP（frame-src）にも同じ提供元だけを書いている。ここを変えたら CSP も変える
//      （test/embed.test.mjs で一致を確かめている）

/**
 * 提供元の一覧。hosts は CSP の frame-src にそのまま書く。
 * ratio は幅・高さの指定がないときの縦横比
 */
export const EMBED_PROVIDERS = [
  {
    name: 'Google マップ',
    hosts: ['www.google.com', 'maps.google.com'],
    // 埋め込み用の地図（/maps/embed）、マイマップ（/maps/d/embed）、旧形式（?output=embed）
    accept: (u) =>
      /^\/maps\/embed(?:\/|$)/.test(u.pathname) ||
      /^\/maps\/d\/(?:u\/\d+\/)?embed$/.test(u.pathname) ||
      (/^\/maps(?:\/|$)/.test(u.pathname) && u.searchParams.get('output') === 'embed'),
    ratio: [4, 3],
  },
  {
    name: 'OpenStreetMap',
    hosts: ['www.openstreetmap.org'],
    accept: (u) => u.pathname === '/export/embed.html',
    ratio: [4, 3],
  },
  {
    name: 'YouTube',
    hosts: ['www.youtube.com', 'www.youtube-nocookie.com'],
    accept: (u) => /^\/embed\/[\w-]+$/.test(u.pathname),
    ratio: [16, 9],
    // YouTube はリファラのない埋め込みを拒む（エラー 153）。このページは独自スキームなので
    // リファラを送れず、アプリの中では再生できない。クリックでブラウザの再生ページを開く
    openInBrowser: (u) => `https://www.youtube.com/watch?v=${encodeURIComponent(u.pathname.slice('/embed/'.length))}`,
  },
  {
    name: 'Vimeo',
    hosts: ['player.vimeo.com'],
    accept: (u) => /^\/video\/\d+$/.test(u.pathname),
    ratio: [16, 9],
  },
  {
    name: 'Google カレンダー',
    hosts: ['calendar.google.com'],
    accept: (u) => u.pathname === '/calendar/embed',
    ratio: [4, 3],
  },
  {
    name: 'Google ドキュメント',
    hosts: ['docs.google.com'],
    // 「ウェブに公開」したスライド・文書・表（フォームは入力を送るので通さない）
    accept: (u) => /^\/(?:presentation|document|spreadsheets)\/d\/(?:e\/)?[\w-]+\/(?:embed|pub|pubhtml)$/.test(u.pathname),
    ratio: [16, 10],
  },
];

/** CSP の frame-src に書く提供元（ブラウザで開くだけのものは枠に入れないので含めない） */
export function embedHosts() {
  return EMBED_PROVIDERS.filter((p) => !p.openInBrowser).flatMap((p) => p.hosts);
}

/** iframe の src が許可した埋め込みなら、提供元と正規化した URL を返す */
export function matchEmbed(src) {
  if (typeof src !== 'string') return null;
  let u;
  try {
    u = new URL(src.trim());
  } catch {
    return null;
  }
  if (u.protocol !== 'https:' || u.username || u.password || u.port) return null;
  const provider = EMBED_PROVIDERS.find((p) => p.hosts.includes(u.hostname) && p.accept(u));
  if (!provider) return null;
  return { provider, url: u.href, browserURL: provider.openInBrowser ? provider.openInBrowser(u) : null };
}

/** width / height の属性から大きさを決める。数値でなければ提供元の縦横比を使う */
export function embedSize(width, height, provider) {
  const w = toPixels(width);
  const h = toPixels(height);
  const ratio = w && h ? [w, h] : provider.ratio;
  return { maxWidth: w, ratio };
}

function toPixels(value) {
  if (value == null) return null;
  const m = String(value).trim().match(/^(\d{2,4})(?:px)?$/);
  if (!m) return null;
  const n = Number(m[1]);
  return n >= 50 && n <= 4000 ? n : null;
}

// ------------------------------------------------------------
// DOM（ここから下はビューワーの中でだけ使う）
// ------------------------------------------------------------

/** sanitize 済みの断片にある iframe を、置き場所かリンクに差し替える */
export function replaceFrames(root) {
  for (const frame of Array.from(root.querySelectorAll('iframe'))) {
    const src = frame.getAttribute('src');
    const hit = matchEmbed(src);
    frame.replaceWith(hit ? placeholder(hit, frame) : blockedNotice(src));
  }
}

function placeholder({ provider, url, browserURL }, frame) {
  const { maxWidth, ratio } = embedSize(frame.getAttribute('width'), frame.getAttribute('height'), provider);
  const box = document.createElement('div');
  box.className = 'web-embed';
  box.dataset.embedSrc = url;
  box.dataset.embedProvider = provider.name;
  const title = frame.getAttribute('title');
  if (title) box.dataset.embedTitle = title;
  box.style.setProperty('--embed-ratio', `${ratio[0]} / ${ratio[1]}`);
  if (maxWidth) box.style.setProperty('--embed-width', `${maxWidth}px`);

  const button = document.createElement('button');
  button.type = 'button';
  button.className = 'web-embed-load';
  const name = document.createElement('span');
  name.className = 'web-embed-provider';
  name.textContent = title ? `${provider.name}：${title}` : provider.name;
  const hint = document.createElement('span');
  hint.className = 'web-embed-hint';
  hint.textContent = browserURL ? 'クリックしてブラウザで見る' : 'クリックして読み込む';
  const address = document.createElement('span');
  address.className = 'web-embed-url';
  address.textContent = url;
  button.append(name, hint, address);
  box.appendChild(button);
  return box;
}

function blockedNotice(src) {
  const p = document.createElement('p');
  p.className = 'web-embed-blocked';
  p.append('表示できない埋め込み');
  let u = null;
  try { u = new URL(src); } catch { /* 不正な URL は文字だけ出す */ }
  if (u && (u.protocol === 'https:' || u.protocol === 'http:')) {
    p.append('：');
    const a = document.createElement('a');
    a.href = u.href;
    a.textContent = u.href;
    p.appendChild(a);
  }
  return p;
}

/** 置き場所に iframe を入れて読み込む */
export function loadEmbed(box, { lazy = false } = {}) {
  if (!box || box.querySelector('iframe')) return;
  const hit = matchEmbed(box.dataset.embedSrc);
  if (!hit || hit.browserURL) return;
  box.replaceChildren(makeFrame(hit.url, box.dataset.embedTitle || hit.provider.name, { lazy }));
  box.classList.add('web-embed-loaded');
}

function makeFrame(url, title, { lazy = false } = {}) {
  const frame = document.createElement('iframe');
  frame.src = url;
  frame.title = title;
  // 提供元のページは別のオリジンなので、allow-same-origin を付けてもこのページには触れない。
  // 「Google マップで見る」などは新しいウインドウとして開かせ、Swift 側でブラウザへ渡す
  frame.setAttribute('sandbox', 'allow-scripts allow-same-origin allow-popups allow-popups-to-escape-sandbox allow-presentation');
  frame.setAttribute('allow', 'fullscreen; picture-in-picture; encrypted-media');
  frame.setAttribute('allowfullscreen', '');
  frame.setAttribute('referrerpolicy', 'strict-origin-when-cross-origin');
  if (lazy) frame.setAttribute('loading', 'lazy');
  return frame;
}

/** 書き出した HTML 用に、置き場所を本物の iframe に戻す */
export function framesForExport(root) {
  for (const box of Array.from(root.querySelectorAll('.web-embed'))) {
    const hit = matchEmbed(box.dataset.embedSrc);
    if (!hit) {
      box.remove();
      continue;
    }
    const frame = makeFrame(hit.url, box.dataset.embedTitle || hit.provider.name, { lazy: true });
    const wrap = document.createElement('div');
    wrap.className = 'web-embed web-embed-loaded';
    wrap.setAttribute('style', box.getAttribute('style') || '');
    wrap.appendChild(frame);
    box.replaceWith(wrap);
  }
}
