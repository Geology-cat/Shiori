// タスクリスト。- [ ] / - [x] に加えて Obsidian でよく使う - [/] - [-] も表示する。
// チェックボックスをクリックするとソース側を書き換えられるよう、元の行番号を持たせる。
const STATE = /^\[([ xX/\-])\][ \t]+/;

export function taskListPlugin(md) {
  md.core.ruler.after('inline', 'task_list', (state) => {
    const tokens = state.tokens;
    for (let i = 2; i < tokens.length; i++) {
      const tok = tokens[i];
      if (tok.type !== 'inline') continue;
      if (tokens[i - 1].type !== 'paragraph_open' || tokens[i - 2].type !== 'list_item_open') continue;
      const first = tok.children?.[0];
      if (!first || first.type !== 'text') continue;
      const m = first.content.match(STATE);
      if (!m) continue;

      const mark = m[1];
      first.content = first.content.slice(m[0].length);
      const item = tokens[i - 2];
      item.attrJoin('class', 'task-item');
      item.attrSet('data-task', mark === ' ' ? 'todo' : mark === '/' ? 'doing' : mark === '-' ? 'cancelled' : 'done');

      const line = item.map ? item.map[0] + (state.env.lineOffset || 0) : -1;
      const checked = mark === 'x' || mark === 'X' ? ' checked' : '';
      const html = new state.Token('html_inline', '', 0);
      html.content = `<input type="checkbox" class="task-checkbox" data-task-line="${line}"${checked}>`;
      tok.children.unshift(html);

      // リスト全体に印を付ける（行頭記号を消すため）
      for (let j = i - 3; j >= 0; j--) {
        if ((tokens[j].type === 'bullet_list_open' || tokens[j].type === 'ordered_list_open') && tokens[j].level === item.level - 1) {
          if (!tokens[j].attrGet('class')?.includes('task-list')) tokens[j].attrJoin('class', 'task-list');
          break;
        }
      }
    }
  });
}
