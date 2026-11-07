import AppKit
import WebKit

/// 右クリックメニューからページ遷移系の項目を除いた WKWebView
final class ViewerWebView: WKWebView {
    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        let hidden: Set<String> = [
            "WKMenuItemIdentifierReload", "WKMenuItemIdentifierGoBack", "WKMenuItemIdentifierGoForward",
            "WKMenuItemIdentifierOpenLink", "WKMenuItemIdentifierOpenLinkInNewWindow",
            "WKMenuItemIdentifierDownloadLinkedFile", "WKMenuItemIdentifierOpenImageInNewWindow",
            "WKMenuItemIdentifierDownloadImage",
        ]
        menu.items.removeAll { hidden.contains($0.identifier?.rawValue ?? "") }
        super.willOpenMenu(menu, with: event)
    }
}

/// ビューワー（WKWebView）を操作する。Swift 側の窓口はこのクラスに集約する。
final class ViewerController: NSObject {
    let webView: ViewerWebView

    /// ビューワーからの通知の受け先
    weak var delegate: ViewerDelegate?

    private var isReady = false
    private var pendingAfterReady: [() -> Void] = []
    private var renderedTabID: UUID?
    private var renderedVersion = -1

    /// ビューワー用の WebView を作る（書き出しでも同じものを使う）
    static func makeWebView(handlerTarget: WKScriptMessageHandler & WKScriptMessageHandlerWithReply) -> ViewerWebView {
        let config = WKWebViewConfiguration()
        let handler = ShioriSchemeHandler()
        config.setURLSchemeHandler(handler, forURLScheme: ShioriSchemeHandler.appScheme)
        config.setURLSchemeHandler(handler, forURLScheme: ShioriSchemeHandler.fileScheme)
        let content = config.userContentController
        content.add(WeakScriptHandler(target: handlerTarget), name: "shiori")
        content.addScriptMessageHandler(WeakReplyHandler(target: handlerTarget), contentWorld: .page, name: "shioriReply")
        #if DEBUG
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        #endif
        let view = ViewerWebView(frame: .zero, configuration: config)
        view.setValue(false, forKey: "drawsBackground")
        view.allowsMagnification = true
        view.allowsBackForwardNavigationGestures = false
        // ファイルのドロップは WebView でなく窓全体で受ける
        view.unregisterDraggedTypes()
        #if DEBUG
        view.isInspectable = true
        #endif
        return view
    }

    /// WebView からのメッセージの中継（init の途中で self を渡せないため）
    private let handlerProxy: LateBoundHandler

    override init() {
        let proxy = LateBoundHandler()
        handlerProxy = proxy
        webView = Self.makeWebView(handlerTarget: proxy)
        super.init()
        proxy.target = self
        webView.navigationDelegate = self
        webView.load(URLRequest(url: ShioriSchemeHandler.shellURL))
    }

    deinit {
        webView.configuration.userContentController.removeAllScriptMessageHandlers()
    }

    private func whenReady(_ action: @escaping () -> Void) {
        if isReady { action() } else { pendingAfterReady.append(action) }
    }

    private func call(_ script: String, _ arguments: [String: Any] = [:], completion: ((Any?) -> Void)? = nil) {
        whenReady { [weak self] in
            self?.webView.callAsyncJavaScript(script, arguments: arguments, in: nil, in: .page) { result in
                switch result {
                case .success(let value): completion?(value)
                case .failure(let error):
                    NSLog("Shiori viewer: %@", error.localizedDescription)
                    completion?(nil)
                }
            }
        }
    }

    // MARK: - 表示

    /// タブの内容を表示する。内容が変わっていなければ描画し直さず位置だけ合わせる。
    func show(_ tab: DocumentTab, completion: (() -> Void)? = nil) {
        if renderedTabID == tab.id, renderedVersion == tab.version {
            if let fragment = tab.pendingFragment {
                tab.pendingFragment = nil
                call("return Shiori.scrollToFragment(f)", ["f": fragment]) { _ in completion?() }
            } else {
                call("return Shiori.scrollToPosition(n)", ["n": tab.viewerLine]) { _ in completion?() }
            }
            return
        }
        render(tab, position: tab.viewerLine, completion: completion)
    }

    /// 必ず描画し直す
    func render(_ tab: DocumentTab, position: Double? = nil, keepPosition: Bool = false, completion: (() -> Void)? = nil) {
        renderedTabID = tab.id
        renderedVersion = tab.version
        if tab.kind == .image, let url = tab.url {
            call("return Shiori.showImage({path: p})", ["p": url.path]) { _ in completion?() }
            return
        }
        var params: [String: Any] = ["markdown": tab.text, "keepPosition": keepPosition]
        if let url = tab.url { params["path"] = url.path }
        if let position { params["position"] = position }
        let fragment = tab.pendingFragment
        tab.pendingFragment = nil
        call("return await Shiori.render(p)", ["p": params]) { [weak self] _ in
            if let fragment {
                self?.call("return Shiori.scrollToFragment(f)", ["f": fragment]) { _ in completion?() }
            } else {
                completion?()
            }
        }
    }

    func clear() {
        renderedTabID = nil
        renderedVersion = -1
        call("return Shiori.clear()")
    }

    /// 次回の show で必ず描画し直す
    func invalidate() {
        renderedVersion = -1
    }

    func applySettings(_ payload: [String: Any], completion: (() -> Void)? = nil) {
        call("return await Shiori.applySettings(s)", ["s": payload]) { _ in completion?() }
    }

    func scrollToLine(_ line: Int) {
        call("return Shiori.scrollToLine(n)", ["n": line])
    }

    func page(_ direction: Int) {
        call("return Shiori.page(d)", ["d": direction])
    }

    // MARK: - 検索

    func find(_ query: String, completion: @escaping (Int, Int) -> Void) {
        call("return Shiori.find(q)", ["q": query]) { value in
            let dict = value as? [String: Any]
            completion(dict?["count"] as? Int ?? 0, dict?["index"] as? Int ?? -1)
        }
    }

    func findNext(_ direction: Int, completion: @escaping (Int, Int) -> Void) {
        call("return Shiori.findNext(d)", ["d": direction]) { value in
            let dict = value as? [String: Any]
            completion(dict?["count"] as? Int ?? 0, dict?["index"] as? Int ?? -1)
        }
    }

    func clearFind() {
        call("return Shiori.clearFind()")
    }
}

/// ビューワーからの通知
protocol ViewerDelegate: AnyObject {
    func viewerDidScroll(position: Double, progress: Double)
    func viewerOpenPath(_ path: String, fragment: String?, newTab: Bool)
    func viewerOpenExternal(_ url: URL)
    func viewerOpenWikilink(_ target: String, newTab: Bool)
    func viewerToggleTask(line: Int, checked: Bool)
    func viewerImageInfo(width: Int, height: Int)
    func viewerResolveWikilink(_ target: String, from: String?) -> URL?
}

// MARK: - WebKit のコールバック

extension ViewerController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // シェル以外へのページ遷移はすべて止める（リンクは JS 側で処理している）
        if action.request.url == ShioriSchemeHandler.shellURL {
            decisionHandler(.allow)
            return
        }
        decisionHandler(.cancel)
        if action.navigationType == .linkActivated, let url = action.request.url {
            delegate?.viewerOpenExternal(url)
        }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        // WebKit のプロセスが落ちても表示を復旧する
        isReady = false
        renderedTabID = nil
        renderedVersion = -1
        webView.load(URLRequest(url: ShioriSchemeHandler.shellURL))
    }
}

extension ViewerController: WKScriptMessageHandler, WKScriptMessageHandlerWithReply {
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "ready":
            isReady = true
            let pending = pendingAfterReady
            pendingAfterReady = []
            pending.forEach { $0() }
        case "scroll":
            let position = (body["position"] as? NSNumber)?.doubleValue ?? 0
            delegate?.viewerDidScroll(position: position, progress: body["progress"] as? Double ?? 0)
        case "openPath":
            guard let path = body["path"] as? String else { return }
            let fragment = (body["fragment"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            delegate?.viewerOpenPath(path, fragment: fragment, newTab: body["newTab"] as? Bool ?? false)
        case "openExternal":
            if let s = body["url"] as? String, let url = URL(string: s) { delegate?.viewerOpenExternal(url) }
        case "openWikilink":
            if let t = body["target"] as? String { delegate?.viewerOpenWikilink(t, newTab: body["newTab"] as? Bool ?? false) }
        case "toggleTask":
            delegate?.viewerToggleTask(line: body["line"] as? Int ?? -1, checked: body["checked"] as? Bool ?? false)
        case "copy":
            if let text = body["text"] as? String {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
        case "imageInfo":
            delegate?.viewerImageInfo(width: body["width"] as? Int ?? 0, height: body["height"] as? Int ?? 0)
        default:
            break
        }
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage, replyHandler: @escaping (Any?, String?) -> Void) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String,
              let target = body["target"] as? String else {
            replyHandler(nil, nil)
            return
        }
        let from = body["from"] as? String
        let url = delegate?.viewerResolveWikilink(target, from: from)
        switch type {
        case "resolveWikilink":
            replyHandler(url.map { ["path": $0.path] }, nil)
        case "readWikilink":
            if let url, FileKinds.isMarkdown(url), let loaded = try? TextFile.read(url) {
                replyHandler(["path": url.path, "text": loaded.text], nil)
            } else {
                replyHandler(nil, nil)
            }
        default:
            replyHandler(nil, nil)
        }
    }
}

// MARK: - メッセージハンドラの循環参照を避ける中継

final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
        target?.userContentController(c, didReceive: m)
    }
}

final class WeakReplyHandler: NSObject, WKScriptMessageHandlerWithReply {
    weak var target: WKScriptMessageHandlerWithReply?
    init(target: WKScriptMessageHandlerWithReply) { self.target = target }
    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage, replyHandler: @escaping (Any?, String?) -> Void) {
        if let target { target.userContentController(c, didReceive: m, replyHandler: replyHandler) } else { replyHandler(nil, nil) }
    }
}

/// init の途中で self をまだ渡せないので、あとから宛先を差し込む中継
final class LateBoundHandler: NSObject, WKScriptMessageHandler, WKScriptMessageHandlerWithReply {
    weak var target: (WKScriptMessageHandler & WKScriptMessageHandlerWithReply)?

    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
        target?.userContentController(c, didReceive: m)
    }
    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage, replyHandler: @escaping (Any?, String?) -> Void) {
        if let target { target.userContentController(c, didReceive: m, replyHandler: replyHandler) } else { replyHandler(nil, nil) }
    }
}
