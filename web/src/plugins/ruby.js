// 日本語のルビ・傍点。読書（特に縦書き）で使う。
//   青空文庫 / なろう / カクヨム: ｜漢字《かんじ》 ・ 漢字《かんじ》 ・ 《《傍点》》
//   でんでんマークダウン       : {漢字|かんじ}  {漢字|かん|じ}
import { escapeHtml } from '../util.js';

const PATTERN = new RegExp(
  [
    '《《([^《》\\n]+)》》', // 1: 傍点
    '[|｜]([^|｜《》\\n]+)《([^《》\\n]+)》', // 2,3: 区切り付きルビ
    '((?:\\p{Script=Han}|[々〆ヶ〇])+)《([^《》\\n]+)》', // 4,5: 漢字直後のルビ
    '\\{([^{}|\\n]+)\\|([^{}\\n]+)\\}', // 6,7: でんでん形式
  ].join('|'),
  'gu'
);

function rubyHtml(base, reading) {
  // {漢字|かん|じ} は 1 文字ずつのモノルビにする
  const parts = reading.split('|');
  const chars = Array.from(base);
  if (parts.length > 1 && parts.length === chars.length) {
    return (
      '<ruby>' +
      chars.map((c, i) => `${escapeHtml(c)}<rp>(</rp><rt>${escapeHtml(parts[i])}</rt><rp>)</rp>`).join('') +
      '</ruby>'
    );
  }
  return `<ruby>${escapeHtml(base)}<rp>(</rp><rt>${escapeHtml(parts.join(''))}</rt><rp>)</rp></ruby>`;
}

function emphasisHtml(text) {
  return `<em class="bouten">${escapeHtml(text)}</em>`;
}

export function rubyPlugin(md) {
  md.core.ruler.after('inline', 'ruby', (state) => {
    for (const block of state.tokens) {
      if (block.type !== 'inline' || !block.children) continue;
      const out = [];
      let changed = false;
      for (const child of block.children) {
        if (child.type !== 'text' || !/[《{]/.test(child.content)) {
          out.push(child);
          continue;
        }
        const text = child.content;
        let last = 0;
        PATTERN.lastIndex = 0;
        let m;
        while ((m = PATTERN.exec(text))) {
          if (m.index > last) {
            const t = new state.Token('text', '', 0);
            t.content = text.slice(last, m.index);
            out.push(t);
          }
          const html = new state.Token('html_inline', '', 0);
          if (m[1] != null) html.content = emphasisHtml(m[1]);
          else if (m[2] != null) html.content = rubyHtml(m[2], m[3]);
          else if (m[4] != null) html.content = rubyHtml(m[4], m[5]);
          else html.content = rubyHtml(m[6], m[7]);
          out.push(html);
          last = m.index + m[0].length;
          changed = true;
        }
        if (last < text.length) {
          const t = new state.Token('text', '', 0);
          t.content = text.slice(last);
          out.push(t);
        }
      }
      if (changed) block.children = out;
    }
  });
}
