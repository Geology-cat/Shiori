// 数式を Markdown のパース段階で保護する。
// $a_1 + b_1$ の _ や \\ が強調・エスケープに化けないよう、inline 処理より先に切り出す。
// 実際の描画はブラウザ側で data-tex を KaTeX に渡して行う。
import { escapeHtml, lineAttrs } from '../util.js';

function isDigit(code) {
  return code >= 0x30 && code <= 0x39;
}
function isSpace(code) {
  return code === 0x20 || code === 0x09 || code === 0x0a || code === 0x0d;
}

// $...$（Pandoc と同じ判定: 開始直後と終了直前に空白を置かない／終了直後に数字を続けない）
function inlineDollar(state, silent) {
  const { src, pos, posMax } = state;
  if (src.charCodeAt(pos) !== 0x24) return false;
  if (src.charCodeAt(pos + 1) === 0x24) return inlineDoubleDollar(state, silent);
  if (pos + 1 >= posMax || isSpace(src.charCodeAt(pos + 1))) return false;

  let end = pos + 1;
  for (;;) {
    end = src.indexOf('$', end);
    if (end < 0 || end >= posMax) return false;
    // \$ はエスケープされたドル記号
    let backslashes = 0;
    for (let i = end - 1; i > pos && src.charCodeAt(i) === 0x5c; i--) backslashes++;
    if (backslashes % 2 === 0) break;
    end += 1;
  }
  if (isSpace(src.charCodeAt(end - 1))) return false;
  if (end + 1 < posMax && isDigit(src.charCodeAt(end + 1))) return false;
  if (end === pos + 1) return false;

  if (!silent) {
    const token = state.push('math_inline', 'span', 0);
    token.content = src.slice(pos + 1, end);
    token.markup = '$';
  }
  state.pos = end + 1;
  return true;
}

// 段落内の $$...$$（前後に文字があっても数式として扱う）
function inlineDoubleDollar(state, silent) {
  const { src, pos, posMax } = state;
  const end = src.indexOf('$$', pos + 2);
  if (end < 0 || end >= posMax || end === pos + 2) return false;
  if (!silent) {
    const token = state.push('math_inline_display', 'div', 0);
    token.content = src.slice(pos + 2, end).trim();
    token.markup = '$$';
  }
  state.pos = end + 2;
  return true;
}

// \( ... \) と \[ ... \]（段落内）
function inlineBackslash(state, silent) {
  const { src, pos, posMax } = state;
  if (src.charCodeAt(pos) !== 0x5c) return false;
  const next = src.charCodeAt(pos + 1);
  let close;
  let type;
  if (next === 0x28) {
    close = '\\)';
    type = 'math_inline';
  } else if (next === 0x5b) {
    close = '\\]';
    type = 'math_inline_display';
  } else {
    return false;
  }
  const end = src.indexOf(close, pos + 2);
  if (end < 0 || end >= posMax) return false;
  if (!silent) {
    const token = state.push(type, 'span', 0);
    token.content = src.slice(pos + 2, end).trim();
    token.markup = close;
  }
  state.pos = end + 2;
  return true;
}

// $$ ... $$ / \[ ... \] のブロック
function blockMath(state, startLine, endLine, silent) {
  const start = state.bMarks[startLine] + state.tShift[startLine];
  const max = state.eMarks[startLine];
  // コードブロックのインデント内では無視する
  if (state.sCount[startLine] - state.blkIndent >= 4) return false;
  const lineText = state.src.slice(start, max);

  let close;
  let openLen;
  if (lineText.startsWith('$$')) {
    close = '$$';
    openLen = 2;
  } else if (lineText.startsWith('\\[')) {
    close = '\\]';
    openLen = 2;
  } else {
    return false;
  }

  const firstRest = lineText.slice(openLen);
  let content = '';
  let nextLine = startLine;
  let found = false;
  let trailing = '';

  // 1 行で閉じる場合
  const sameLineEnd = firstRest.indexOf(close);
  if (sameLineEnd >= 0) {
    trailing = firstRest.slice(sameLineEnd + close.length).trim();
    // $$x$$ の後ろに文章が続くなら段落内のディスプレイ数式として inline 側で処理する
    if (trailing && !/^\((?:[^)]*)\)$|^\{#[^}]*\}$/.test(trailing)) return false;
    content = firstRest.slice(0, sameLineEnd);
    found = true;
  } else {
    content = firstRest + '\n';
    for (nextLine = startLine + 1; nextLine < endLine; nextLine++) {
      if (state.sCount[nextLine] < state.blkIndent && state.src.slice(state.bMarks[nextLine], state.eMarks[nextLine]).trim() !== '') {
        break; // リストや引用のブロックを抜けた
      }
      const lineStart = state.bMarks[nextLine] + state.tShift[nextLine];
      const lineEnd = state.eMarks[nextLine];
      const text = state.src.slice(lineStart, lineEnd);
      const idx = text.indexOf(close);
      if (idx >= 0) {
        content += text.slice(0, idx);
        trailing = text.slice(idx + close.length).trim();
        found = true;
        break;
      }
      content += text + '\n';
    }
  }
  if (!found) return false;
  if (silent) return true;

  const token = state.push('math_block', 'div', 0);
  token.block = true;
  token.content = content.trim();
  token.map = [startLine, nextLine + 1];
  token.markup = close;
  // $$ ... $$ (1) のような式番号
  const tag = trailing.match(/^\(([^)]*)\)$/);
  if (tag) token.meta = { tag: tag[1] };
  state.line = nextLine + 1;
  return true;
}

export function mathPlugin(md) {
  md.inline.ruler.before('escape', 'math_backslash', inlineBackslash);
  md.inline.ruler.before('escape', 'math_dollar', inlineDollar);
  md.block.ruler.before('fence', 'math_block', blockMath, {
    alt: ['paragraph', 'reference', 'blockquote', 'list'],
  });

  md.renderer.rules.math_inline = (tokens, idx, _o, env) => {
    env.hasMath = true;
    return `<span class="math-inline" data-tex="${escapeHtml(tokens[idx].content)}"></span>`;
  };
  md.renderer.rules.math_inline_display = (tokens, idx, _o, env) => {
    env.hasMath = true;
    return `<span class="math-block math-block-inline" data-tex="${escapeHtml(tokens[idx].content)}"></span>`;
  };
  md.renderer.rules.math_block = (tokens, idx, _o, env) => {
    env.hasMath = true;
    const token = tokens[idx];
    const lineAttr = lineAttrs(token);
    const tag = token.meta?.tag ? ` data-tag="${escapeHtml(token.meta.tag)}"` : '';
    return `<div class="math-block" data-tex="${escapeHtml(token.content)}"${tag}${lineAttr}></div>\n`;
  };
}
