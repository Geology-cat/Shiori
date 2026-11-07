// Obsidian のコメント %%...%% は閲覧時に表示しない
export function commentPlugin(md) {
  md.inline.ruler.before('emphasis', 'percent_comment', (state, silent) => {
    const { src, pos, posMax } = state;
    if (src.charCodeAt(pos) !== 0x25 || src.charCodeAt(pos + 1) !== 0x25) return false;
    const end = src.indexOf('%%', pos + 2);
    if (end < 0 || end >= posMax) return false;
    if (!silent) state.push('percent_comment', '', 0);
    state.pos = end + 2;
    return true;
  });
  md.block.ruler.before('paragraph', 'percent_comment_block', (state, startLine, endLine, silent) => {
    const start = state.bMarks[startLine] + state.tShift[startLine];
    const line = state.src.slice(start, state.eMarks[startLine]);
    if (!line.startsWith('%%')) return false;
    // 同じ行で閉じるものは inline に任せる
    if (line.indexOf('%%', 2) >= 0) return false;
    let next = startLine + 1;
    for (; next < endLine; next++) {
      const s = state.bMarks[next] + state.tShift[next];
      if (state.src.slice(s, state.eMarks[next]).includes('%%')) break;
    }
    if (next >= endLine) return false;
    if (silent) return true;
    state.line = next + 1;
    return true;
  });
  md.renderer.rules.percent_comment = () => '';
}
