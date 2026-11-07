// Swift 側との通信
const handlers = window.webkit?.messageHandlers;

/** Swift へ一方向の通知を送る */
export function post(type, data = {}) {
  handlers?.shiori?.postMessage({ type, ...data });
}

/** Swift へ問い合わせて返事を待つ（WKScriptMessageHandlerWithReply） */
export function ask(type, data = {}) {
  if (!handlers?.shioriReply) return Promise.resolve(null);
  return handlers.shioriReply.postMessage({ type, ...data });
}
