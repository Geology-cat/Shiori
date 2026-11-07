// [[ノート]] / [[ノート|表示名]] / [[ノート#見出し]] / ![[画像.png|300]] / ![[ノート]]
// 実体の場所はアプリ側で解決するので、ここでは data 属性に名前だけ残す。
import { escapeHtml } from '../util.js';

const IMAGE_EXT = /\.(png|jpe?g|gif|svg|webp|heic|tiff?|bmp|avif)$/i;

function splitTarget(raw) {
  const [target, ...rest] = raw.split('|');
  return { target: target.trim(), alias: rest.join('|').trim() };
}

function wikilinkRule(state, silent) {
  const { src, pos, posMax } = state;
  const isEmbed = src.charCodeAt(pos) === 0x21; // !
  const open = isEmbed ? pos + 1 : pos;
  if (src.charCodeAt(open) !== 0x5b || src.charCodeAt(open + 1) !== 0x5b) return false;

  const end = src.indexOf(']]', open + 2);
  if (end < 0 || end >= posMax) return false;
  const inner = src.slice(open + 2, end);
  if (!inner.trim() || inner.includes('\n') || inner.includes('[')) return false;
  // [[toc]] は目次の指定として残す
  if (/^_?toc_?$/i.test(inner.trim())) return false;

  if (!silent) {
    const token = state.push(isEmbed ? 'wiki_embed' : 'wikilink', '', 0);
    token.meta = splitTarget(inner);
  }
  state.pos = end + 2;
  return true;
}

export function wikilinkPlugin(md) {
  md.inline.ruler.before('link', 'wikilink', wikilinkRule);
  // 画像 (image) ルールより先に ![[...]] を拾う
  md.inline.ruler.before('image', 'wikiembed', (state, silent) => {
    if (state.src.charCodeAt(state.pos) !== 0x21) return false;
    return wikilinkRule(state, silent);
  });

  md.renderer.rules.wikilink = (tokens, idx) => {
    const { target, alias } = tokens[idx].meta;
    const label = alias || target.replace(/#\^?/, ' › ');
    return `<a class="wikilink" href="#" data-wikilink="${escapeHtml(target)}">${escapeHtml(label)}</a>`;
  };
  md.renderer.rules.wiki_embed = (tokens, idx) => {
    const { target, alias } = tokens[idx].meta;
    if (IMAGE_EXT.test(target)) {
      const size = alias.match(/^(\d+)(?:x(\d+))?$/);
      const sizeAttr = size
        ? ` width="${size[1]}"${size[2] ? ` height="${size[2]}"` : ''}`
        : '';
      const alt = size ? '' : alias;
      return `<img class="wiki-image" data-wiki-src="${escapeHtml(target)}" alt="${escapeHtml(alt)}"${sizeAttr}>`;
    }
    return `<span class="wiki-embed" data-wiki-embed="${escapeHtml(target)}">${escapeHtml(alias || target)}</span>`;
  };
}
