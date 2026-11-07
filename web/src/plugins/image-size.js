// ![説明|300](a.png) / ![説明|300x200](a.png) という Obsidian の画像サイズ指定
export function imageSizePlugin(md) {
  md.core.ruler.after('inline', 'image_size', (state) => {
    for (const block of state.tokens) {
      if (block.type !== 'inline' || !block.children) continue;
      for (const child of block.children) {
        if (child.type !== 'image') continue;
        // alt は children のテキストから描画されるので、そちらを書き換える
        const textToken = child.children?.[child.children.length - 1];
        if (!textToken || textToken.type !== 'text') continue;
        const m = textToken.content.match(/^(.*?)\|(\d+)(?:x(\d+))?$/s);
        if (!m) continue;
        textToken.content = m[1];
        child.content = m[1];
        child.attrSet('width', m[2]);
        if (m[3]) child.attrSet('height', m[3]);
      }
    }
  });
}
