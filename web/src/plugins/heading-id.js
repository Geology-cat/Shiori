// 見出しに id を振る。日本語の見出しもそのまま使えるようにする（GitHub 互換の簡易スラッグ）。
export function slugify(text) {
  return text
    .trim()
    .toLowerCase()
    .replace(/[\s]+/g, '-')
    .replace(/[^\p{L}\p{N}\p{M}_-]/gu, '');
}

export function headingIdPlugin(md) {
  md.core.ruler.push('heading_id', (state) => {
    const used = state.env.usedSlugs || new Map();
    const tokens = state.tokens;
    for (let i = 0; i < tokens.length; i++) {
      if (tokens[i].type !== 'heading_open' || tokens[i].attrGet('id')) continue;
      const text = (tokens[i + 1]?.children || [])
        .filter((t) => t.type === 'text' || t.type === 'code_inline')
        .map((t) => t.content)
        .join('');
      const base = slugify(text) || 'section';
      const count = used.get(base) || 0;
      used.set(base, count + 1);
      tokens[i].attrSet('id', count === 0 ? base : `${base}-${count}`);
    }
  });
}
