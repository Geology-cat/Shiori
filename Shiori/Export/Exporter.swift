import AppKit
import WebKit

/// PDF・HTML の書き出しと印刷。
/// 画面のビューワーとは別の WebView に同じ設定で描画してから出力する（常にライト配色）。
final class Exporter: NSObject, WKNavigationDelegate, WKScriptMessageHandler, WKScriptMessageHandlerWithReply {
    enum Output {
        case pdf(URL)
        case html(URL)
        case print
    }

    private let output: Output
    private let markdown: String
    private let path: String?
    private let settings: [String: Any]
    private let resolver: (String, String?) -> URL?
    private let completion: (Error?) -> Void

    private var webView: ViewerWebView!
    private var window: NSWindow!
    private var didStart = false

    /// 進行中の書き出しを完了まで保持する
    private static var active: [Exporter] = []

    static func run(
        _ output: Output,
        markdown: String,
        path: String?,
        settings: [String: Any],
        resolver: @escaping (String, String?) -> URL?,
        completion: @escaping (Error?) -> Void
    ) {
        let exporter = Exporter(output: output, markdown: markdown, path: path, settings: settings, resolver: resolver, completion: completion)
        active.append(exporter)
        exporter.start()
    }

    private init(output: Output, markdown: String, path: String?, settings: [String: Any],
                 resolver: @escaping (String, String?) -> URL?, completion: @escaping (Error?) -> Void) {
        self.output = output
        self.markdown = markdown
        self.path = path
        self.settings = settings
        self.resolver = resolver
        self.completion = completion
    }

    private func start() {
        // A4 の版面に合わせた幅でレイアウトする
        let frame = NSRect(x: 0, y: 0, width: 794, height: 1123)
        webView = ViewerController.makeWebView(handlerTarget: self)
        webView.frame = frame
        webView.navigationDelegate = self
        // 描画を止められないよう、見えない位置のウィンドウへ載せる
        window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
        window.contentView?.addSubview(webView)
        window.orderBack(nil)
        webView.load(URLRequest(url: ShioriSchemeHandler.shellURL))
    }

    private func finish(_ error: Error?) {
        webView?.configuration.userContentController.removeAllScriptMessageHandlers()
        webView?.removeFromSuperview()
        window?.orderOut(nil)
        completion(error)
        Self.active.removeAll { $0 === self }
    }

    // MARK: - ビューワーの通知

    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], body["type"] as? String == "ready", !didStart else { return }
        didStart = true
        renderDocument()
    }

    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage, replyHandler: @escaping (Any?, String?) -> Void) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String,
              let target = body["target"] as? String else {
            replyHandler(nil, nil)
            return
        }
        let url = resolver(target, body["from"] as? String)
        switch type {
        case "resolveWikilink": replyHandler(url.map { ["path": $0.path] }, nil)
        case "readWikilink":
            if let url, FileKinds.isMarkdown(url), let loaded = try? TextFile.read(url) {
                replyHandler(["path": url.path, "text": loaded.text], nil)
            } else {
                replyHandler(nil, nil)
            }
        default: replyHandler(nil, nil)
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(action.request.url == ShioriSchemeHandler.shellURL ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(error)
    }

    // MARK: - 描画

    private func renderDocument() {
        var params: [String: Any] = ["markdown": markdown]
        if let path { params["path"] = path }
        let script = """
        Shiori.setForcedAppearance('light');
        await Shiori.applySettings(s);
        await Shiori.render(p);
        await Promise.all(Array.from(document.images).map((img) => img.complete ? null : img.decode().catch(() => null)));
        await document.fonts.ready;
        return Shiori.exportDocument();
        """
        webView.callAsyncJavaScript(script, arguments: ["s": settings, "p": params], in: nil, in: .page) { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                self.finish(error)
            case .success(let value):
                switch self.output {
                case .html(let url):
                    self.writeHTML(value as? [String: Any] ?? [:], to: url)
                case .pdf(let url):
                    self.writePDF(to: url)
                case .print:
                    self.showPrintPanel()
                }
            }
        }
    }

    // MARK: - PDF / 印刷

    private func printInfo() -> NSPrintInfo {
        let info = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
        info.paperSize = NSSize(width: 595.28, height: 841.89) // A4
        info.topMargin = 56
        info.bottomMargin = 56
        info.leftMargin = 56
        info.rightMargin = 56
        info.isHorizontallyCentered = true
        info.isVerticallyCentered = false
        info.horizontalPagination = .automatic
        info.verticalPagination = .automatic
        return info
    }

    private func writePDF(to url: URL) {
        let info = printInfo()
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
        let operation = webView.printOperation(with: info)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        // 印刷処理はモーダルのイベントループ内で進める必要がある
        operation.view?.frame = webView.bounds
        operation.runModal(for: window, delegate: self, didRun: #selector(printDidRun(_:success:contextInfo:)), contextInfo: nil)
    }

    private func showPrintPanel() {
        let operation = webView.printOperation(with: printInfo())
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        operation.view?.frame = webView.bounds
        let parent = NSApp.mainWindow ?? window!
        operation.runModal(for: parent, delegate: self, didRun: #selector(printDidRun(_:success:contextInfo:)), contextInfo: nil)
    }

    @objc private func printDidRun(_ operation: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        finish(nil)
    }

    // MARK: - HTML

    /// 描画済みの本文を、スクリプトなしで読める 1 枚の HTML にする
    private func writeHTML(_ exported: [String: Any], to url: URL) {
        do {
            let page = try Self.composeHTML(exported, theme: settings["themeHref"] as? String, customHref: settings["customHref"] as? String)
            try page.write(to: url, atomically: true, encoding: .utf8)
            finish(nil)
        } catch {
            finish(error)
        }
    }

    private static func cssText(href: String?) -> String {
        guard let href, let url = URL(string: "shiori://app/" + href), let file = ShioriSchemeHandler.resolve(url),
              let text = try? String(contentsOf: file, encoding: .utf8) else { return "" }
        return text
    }

    /// shiori-file:// の画像を data URI に置き換えて 1 ファイルで完結させる
    private static func inlineImages(_ html: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"shiori-file://local[^"'\s>]+"#) else { return html }
        let ns = html as NSString
        var out = ""
        var last = 0
        for match in regex.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: match.range.location - last))
            let raw = ns.substring(with: match.range).replacingOccurrences(of: "&amp;", with: "&")
            if let url = URL(string: raw), let file = ShioriSchemeHandler.resolve(url), let data = try? Data(contentsOf: file) {
                let mime = imageMime(file.pathExtension)
                out += "data:\(mime);base64,\(data.base64EncodedString())"
            } else {
                out += ns.substring(with: match.range)
            }
            last = match.range.location + match.range.length
        }
        out += ns.substring(from: last)
        return out
    }

    private static func imageMime(_ ext: String) -> String {
        switch ext.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "svg": return "image/svg+xml"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "avif": return "image/avif"
        default: return "image/png"
        }
    }

    private static func composeHTML(_ e: [String: Any], theme: String?, customHref: String?) throws -> String {
        let base = cssText(href: "css/base.css")
        let themeCSS = cssText(href: theme)
        let custom = cssText(href: customHref)
        let body = inlineImages(e["html"] as? String ?? "")
        let katexLink = (e["hasMath"] as? Bool ?? false)
            ? #"<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.19.1/dist/katex.min.css">"#
            : ""
        let attrs = [
            "data-appearance=\"light\"",
            "data-writing=\"\(e["writing"] as? String ?? "horizontal")\"",
            "data-heading-numbers=\"\(e["headingNumbers"] as? String ?? "off")\"",
            "data-indent=\"\(e["indent"] as? String ?? "off")\"",
            "data-justify=\"\(e["justify"] as? String ?? "off")\"",
            "data-lang=\"\(e["lang"] as? String ?? "ja")\"",
        ].joined(separator: " ")
        let style = (e["style"] as? String ?? "").replacingOccurrences(of: "\"", with: "&quot;")
        // 書き出した HTML は普通のページとしてスクロールさせる
        let standalone = """
        html, body { overflow: auto; block-size: auto; }
        #scroller { position: static; overflow: visible; }
        :root[data-writing="vertical"] body { overflow: auto; block-size: 100%; }
        :root[data-writing="vertical"] #scroller { position: fixed; inset: 0; overflow: auto; }
        """
        return """
        <!doctype html>
        <html lang="\(e["lang"] as? String ?? "ja")" \(attrs) style="\(style)">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Shiori Export</title>
        \(katexLink)
        <style>\(base)</style>
        <style>\(themeCSS)</style>
        <style>\(custom)</style>
        <style>\(standalone)</style>
        </head>
        <body>
        <main id="scroller"><article id="content" class="shiori-doc" lang="\(e["lang"] as? String ?? "ja")">\(body)</article></main>
        </body>
        </html>
        """
    }
}
