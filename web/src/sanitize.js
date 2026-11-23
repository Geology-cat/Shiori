// md に書かれた生 HTML を無害化する（任意のファイルを開くアプリなので必須）。
// CSP でもスクリプトは止めているが、二重に防ぐ。
import DOMPurify from 'dompurify';
import { replaceFrames } from './embed.js';

const CONFIG = {
  RETURN_DOM_FRAGMENT: true,
  FORCE_BODY: true,
  ALLOW_DATA_ATTR: true,
  // iframe は通すが、そのまま置かずに replaceFrames で許可した埋め込みの置き場所に差し替える
  ADD_TAGS: ['details', 'summary', 'ruby', 'rt', 'rp', 'figure', 'figcaption', 'mark', 'ins', 'kbd', 'section', 'video', 'audio', 'source', 'iframe'],
  ADD_ATTR: ['open', 'controls', 'start', 'align', 'width', 'height', 'id', 'name'],
  FORBID_TAGS: ['script', 'object', 'embed', 'form', 'button', 'select', 'textarea', 'base', 'meta', 'link', 'frame', 'frameset', 'applet'],
  FORBID_ATTR: ['formaction', 'srcdoc', 'ping'],
  // 相対パス・ローカル画像・data 画像も通す
  ALLOWED_URI_REGEXP: /^(?:https?:|mailto:|tel:|shiori-file:|data:image\/|#|[^a-z]|[a-z0-9+.-]+(?:[^a-z0-9+.:-]|$))/i,
};

export function sanitize(html) {
  const fragment = DOMPurify.sanitize(html, CONFIG);
  replaceFrames(fragment);
  return fragment;
}
