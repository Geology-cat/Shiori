// ブロック要素に元の行番号 (data-line) を付ける。
// 閲覧⇔編集の切替で表示位置を保つ、タスクの切替をソースへ反映する、などに使う。
export function lineMapPlugin(md) {
  md.core.ruler.push('line_map', (state) => {
    const offset = state.env.lineOffset || 0;
    for (const token of state.tokens) {
      if (!token.map || token.nesting < 0) continue;
      if (token.level > 6) continue; // 深いネストは位置合わせに不要
      token.attrSet('data-line', String(token.map[0] + offset));
      // 終わりの行（含まない）。ブロック内のどのあたりを見ているかの換算に使う
      token.attrSet('data-line-end', String(token.map[1] + offset));
    }
  });
}
