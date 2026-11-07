// 共通ユーティリティ
/** トークンの行番号を HTML 属性として書き出す */
export function lineAttrs(token) {
  const line = token.attrGet('data-line');
  if (line == null) return '';
  const end = token.attrGet('data-line-end');
  return ` data-line="${line}"` + (end != null ? ` data-line-end="${end}"` : '');
}

export function escapeHtml(s) {
  return String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}
