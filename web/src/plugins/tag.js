// #タグ（Obsidian）。行頭や空白の直後で、数字だけではないものをタグとして扱う。
import { escapeHtml } from '../util.js';

const TAG = /^#((?:[\p{L}\p{N}_/-])+)/u;

export function tagPlugin(md) {
  md.inline.ruler.before('emphasis', 'hashtag', (state, silent) => {
    const { src, pos } = state;
    if (src.charCodeAt(pos) !== 0x23) return false;
    if (pos > 0) {
      const prev = src[pos - 1];
      if (!/[\s（(「『、。]/.test(prev)) return false;
    }
    const m = src.slice(pos, state.posMax).match(TAG);
    if (!m || /^[\d/_-]+$/.test(m[1])) return false;
    if (!silent) {
      const token = state.push('hashtag', '', 0);
      token.content = m[1];
    }
    state.pos += m[0].length;
    return true;
  });
  md.renderer.rules.hashtag = (tokens, idx) =>
    `<span class="tag">#${escapeHtml(tokens[idx].content)}</span>`;
}
