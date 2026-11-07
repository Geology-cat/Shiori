// 注記ブロック。GitHub Alerts / Obsidian Callout / MkDocs Admonition / ::: コンテナに対応する。
import { escapeHtml, lineAttrs } from '../util.js';

// 表記ゆれを色分けのグループへまとめる
const KIND_GROUPS = {
  note: 'note', info: 'note', todo: 'note',
  tip: 'tip', hint: 'tip', important: 'important', success: 'tip', check: 'tip', done: 'tip',
  warning: 'warning', warn: 'warning', caution: 'warning', attention: 'warning', alert: 'warning',
  danger: 'danger', error: 'danger', bug: 'danger', fail: 'danger', failure: 'danger', missing: 'danger',
  question: 'question', help: 'question', faq: 'question',
  example: 'example',
  quote: 'quote', cite: 'quote',
  abstract: 'abstract', summary: 'abstract', tldr: 'abstract',
};

const LABELS = {
  note: 'Note', info: 'Info', todo: 'Todo', tip: 'Tip', hint: 'Hint', important: 'Important',
  success: 'Success', check: 'Check', done: 'Done', warning: 'Warning', warn: 'Warning',
  caution: 'Caution', attention: 'Attention', alert: 'Alert', danger: 'Danger', error: 'Error',
  bug: 'Bug', fail: 'Failure', failure: 'Failure', missing: 'Missing', question: 'Question',
  help: 'Help', faq: 'FAQ', example: 'Example', quote: 'Quote', cite: 'Cite', abstract: 'Abstract',
  summary: 'Summary', tldr: 'TL;DR', message: 'Message', details: 'Details',
};

export function calloutGroup(kind) {
  return KIND_GROUPS[kind] || 'note';
}
function labelFor(kind) {
  return LABELS[kind] || kind.charAt(0).toUpperCase() + kind.slice(1);
}

// > [!NOTE] / > [!tip]+ タイトル
export function calloutPlugin(md) {
  md.core.ruler.after('inline', 'callout', (state) => {
    const tokens = state.tokens;
    const stack = [];
    for (let i = 0; i < tokens.length; i++) {
      const tok = tokens[i];
      if (tok.type === 'blockquote_open') {
        stack.push(tok);
        const para = tokens[i + 1];
        const inline = tokens[i + 2];
        if (para?.type !== 'paragraph_open' || inline?.type !== 'inline') continue;
        const first = inline.children[0];
        if (!first || first.type !== 'text') continue;
        const m = first.content.match(/^\[!([\w-]+)\]([+-]?)[ \t]*(.*)$/);
        if (!m) continue;

        const kind = m[1].toLowerCase();
        const fold = m[2];
        first.content = m[3];

        // 1 行目の残りをタイトル、改行以降を本文にする
        const children = inline.children;
        let breakIndex = children.findIndex((c) => c.type === 'softbreak' || c.type === 'hardbreak');
        if (breakIndex < 0) breakIndex = children.length;
        const titleChildren = children.slice(0, breakIndex);
        const titleHtml = titleChildren.some((c) => c.content || c.type !== 'text')
          ? md.renderer.renderInline(titleChildren, md.options, state.env)
          : escapeHtml(labelFor(kind));
        inline.children = children.slice(breakIndex + 1);
        inline.content = inline.content.split('\n').slice(1).join('\n');

        const useDetails = fold === '+' || fold === '-';
        tok.tag = useDetails ? 'details' : 'div';
        tok.attrJoin('class', 'callout');
        tok.attrSet('data-callout', calloutGroup(kind));
        tok.attrSet('data-kind', kind);
        if (fold === '+') tok.attrSet('open', '');
        tok.meta = { callout: true, useDetails };

        const titleToken = new state.Token('html_block', '', 0);
        const titleTag = useDetails ? 'summary' : 'div';
        titleToken.content = `<${titleTag} class="callout-title">${titleHtml}</${titleTag}>\n`;
        const bodyOpen = new state.Token('html_block', '', 0);
        bodyOpen.content = '<div class="callout-body">\n';
        tokens.splice(i + 1, 0, titleToken, bodyOpen);

        // 本文が空の段落は取り除く
        const newInline = tokens[i + 4];
        if (newInline.children.length === 0) {
          tokens.splice(i + 3, 3);
        }
      } else if (tok.type === 'blockquote_close') {
        const open = stack.pop();
        if (open?.meta?.callout) {
          tok.tag = open.tag;
          const bodyClose = new state.Token('html_block', '', 0);
          bodyClose.content = '</div>\n';
          tokens.splice(i, 0, bodyClose);
          i += 1;
        }
      }
    }
  });
}

// MkDocs の !!! note "タイトル" / ??? note（折りたたみ）
export function admonitionPlugin(md) {
  const OPEN = /^(!!!|\?\?\?\+?)[ \t]+([\w-]+)(?:[ \t]+"([^"]*)")?[ \t]*$/;

  md.block.ruler.before('fence', 'admonition', (state, startLine, endLine, silent) => {
    if (state.sCount[startLine] - state.blkIndent >= 4) return false;
    const start = state.bMarks[startLine] + state.tShift[startLine];
    const m = state.src.slice(start, state.eMarks[startLine]).match(OPEN);
    if (!m) return false;
    if (silent) return true;

    // 4 スペース以上インデントされた行を本文として切り出す
    let nextLine = startLine + 1;
    const baseIndent = state.sCount[startLine] + 4;
    for (; nextLine < endLine; nextLine++) {
      if (state.isEmpty(nextLine)) continue;
      if (state.sCount[nextLine] < baseIndent) break;
    }
    let lastLine = nextLine;
    while (lastLine > startLine + 1 && state.isEmpty(lastLine - 1)) lastLine--;

    const kind = m[2].toLowerCase();
    const folded = m[1].startsWith('???');
    const open = m[1] === '???+';
    const tag = folded ? 'details' : 'div';
    const titleTag = folded ? 'summary' : 'div';

    const tokenOpen = state.push('admonition_open', tag, 1);
    tokenOpen.block = true;
    tokenOpen.map = [startLine, lastLine];
    tokenOpen.attrSet('class', 'callout');
    tokenOpen.attrSet('data-callout', calloutGroup(kind));
    tokenOpen.attrSet('data-kind', kind);
    if (open) tokenOpen.attrSet('open', '');

    if (m[3] !== '') {
      const title = state.push('html_block', '', 0);
      title.content = `<${titleTag} class="callout-title">${escapeHtml(m[3] ?? labelFor(kind))}</${titleTag}>\n<div class="callout-body">\n`;
    } else {
      const body = state.push('html_block', '', 0);
      body.content = '<div class="callout-body">\n';
    }

    const oldParent = state.parentType;
    const oldLineMax = state.lineMax;
    const oldIndent = state.blkIndent;
    state.parentType = 'admonition';
    state.lineMax = lastLine;
    state.blkIndent = baseIndent;
    state.md.block.tokenize(state, startLine + 1, lastLine);
    state.blkIndent = oldIndent;
    state.lineMax = oldLineMax;
    state.parentType = oldParent;

    const bodyClose = state.push('html_block', '', 0);
    bodyClose.content = '</div>\n';
    const tokenClose = state.push('admonition_close', tag, -1);
    tokenClose.block = true;
    state.line = nextLine;
    return true;
  }, { alt: ['paragraph', 'reference', 'blockquote', 'list'] });
}

// ::: note タイトル / :::details タイトル / :::message alert / :::note warn
export function containerCallout(md) {
  const parse = (info) => {
    const m = info.trim().match(/^([\w-]+)?\s*(.*)$/);
    return { kind: (m?.[1] || 'note').toLowerCase(), rest: m?.[2] || '' };
  };
  return {
    validate: (params) => /^\s*[\w-]+/.test(params),
    render(tokens, idx) {
      const token = tokens[idx];
      if (token.nesting !== 1) {
        return token.meta?.details ? '</div></details>\n' : '</div></div>\n';
      }
      const { kind, rest } = parse(token.info);
      const lineAttr = lineAttrs(token);

      if (kind === 'details') {
        token.meta = { details: true };
        // 閉じタグ側でも分かるよう対応するトークンへ印を付ける
        markClosing(tokens, idx, { details: true });
        return `<details class="callout" data-callout="note" data-kind="details"${lineAttr}><summary class="callout-title">${md.renderInline(rest || 'Details')}</summary><div class="callout-body">\n`;
      }
      // Zenn / Qiita の補助指定（:::message alert, :::note warn）
      let effective = kind;
      let title = rest;
      if ((kind === 'message' || kind === 'note') && /^(alert|warn|warning)$/.test(rest)) {
        effective = 'warning';
        title = '';
      } else if (kind === 'note' && /^(info)$/.test(rest)) {
        effective = 'info';
        title = '';
      }
      const group = kind === 'message' && effective === 'message' ? 'note' : calloutGroup(effective);
      const label = title ? md.renderInline(title) : escapeHtml(labelFor(effective));
      return `<div class="callout" data-callout="${group}" data-kind="${escapeHtml(effective)}"${lineAttr}><div class="callout-title">${label}</div><div class="callout-body">\n`;
    },
  };
}

function markClosing(tokens, idx, meta) {
  let depth = 0;
  for (let i = idx; i < tokens.length; i++) {
    if (tokens[i].type === 'container_callout_open') depth++;
    if (tokens[i].type === 'container_callout_close') {
      depth--;
      if (depth === 0) {
        tokens[i].meta = meta;
        return;
      }
    }
  }
}
