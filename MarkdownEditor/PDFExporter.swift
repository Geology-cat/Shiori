import AppKit
import WebKit

extension Notification.Name {
    static let exportPDF = Notification.Name("MarkdownEditor.exportPDF")
}

/// WKWebView で Markdown → HTML → PDF を生成する。
/// pandoc / xelatex は不要。KaTeX・mermaid はバンドル同梱アセットでオフラインレンダリング。
enum PDFExporter {

    // 進行中の WKWebView を保持する配列。完了するまで強参照を維持する。
    private static var activeWebViews: [WKWebView] = []

    /// PDF エクスポートのメインエントリ。
    /// 非同期で呼ばれ、完了後にコールバックを返す。
    static func export(markdown: String, to url: URL, completion: @escaping (Error?) -> Void) {
        DispatchQueue.main.async {
            let html = MarkdownHTML.renderForExport(markdown: FrontMatter.strip(markdown))
            // A4 サイズ相当のフレーム (72dpi ポイント)
            let frame = NSRect(x: 0, y: 0, width: 595.28, height: 841.89)
            let config = WKWebViewConfiguration()
            let webView = WKWebView(frame: frame, configuration: config)
            webView.setValue(false, forKey: "drawsBackground")

            // レンダリング（JS/CSS/フォントの読み込み）を保証するため、非表示のダミーウィンドウに webView を配置する
            let dummyWindow = NSWindow(
                contentRect: frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            dummyWindow.contentView?.addSubview(webView)
            dummyWindow.orderBack(nil) // ウィンドウサーバに登録し、バックグラウンドでのロード・描画を活性化する

            // メモリから解放されないように配列に保持する
            activeWebViews.append(webView)
            
            // dummyWindow の参照を webView に保持させて解放を防ぐ
            objc_setAssociatedObject(webView, "pdfDummyWindow", dummyWindow, .OBJC_ASSOCIATION_RETAIN)

            let delegate = PDFNavigationDelegate(url: url) { error in
                // 処理完了後にビュー階層から取り除き、メモリを解放する
                DispatchQueue.main.async {
                    webView.removeFromSuperview()
                    activeWebViews.removeAll(where: { $0 === webView })
                    completion(error)
                }
            }
            // delegate を強参照で保持 (完了まで解放されないように)
            objc_setAssociatedObject(webView, "pdfDelegate", delegate, .OBJC_ASSOCIATION_RETAIN)
            webView.navigationDelegate = delegate

            // バンドル内の Resources ディレクトリを baseURL にして
            // ローカルの KaTeX/mermaid アセットを読み込めるようにする
            if let resourceURL = Bundle.main.resourceURL {
                webView.loadHTMLString(html, baseURL: resourceURL)
            } else {
                webView.loadHTMLString(html, baseURL: nil)
            }
        }
    }
}

// MARK: - Navigation Delegate (PDF 生成コールバック)

private final class PDFNavigationDelegate: NSObject, WKNavigationDelegate {
    let targetURL: URL
    let completion: (Error?) -> Void

    init(url: URL, completion: @escaping (Error?) -> Void) {
        self.targetURL = url
        self.completion = completion
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // KaTeX auto-render と mermaid の描画が完了するまで少し長めに待つ (1.5秒)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [self] in
            // JavaScript で描画完了を確認
            webView.evaluateJavaScript("document.readyState") { [self] _, _ in
                let printInfo = NSPrintInfo.shared.copy() as! NSPrintInfo
                printInfo.jobDisposition = .save
                printInfo.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = targetURL
                printInfo.paperSize = NSSize(width: 595.28, height: 841.89) // A4
                printInfo.topMargin = 50
                printInfo.bottomMargin = 50
                printInfo.leftMargin = 50
                printInfo.rightMargin = 50
                printInfo.isHorizontallyCentered = true
                printInfo.isVerticallyCentered = false
                
                let printOp = webView.printOperation(with: printInfo)
                printOp.showsPrintPanel = false
                printOp.showsProgressPanel = false
                
                // モーダルシートとして実行することで、内部のイベントループが回りデッドロックを回避する
                if let window = webView.window {
                    printOp.runModal(
                        for: window,
                        delegate: self,
                        didRun: #selector(self.printOperationDidRun(_:success:contextInfo:)),
                        contextInfo: nil
                    )
                } else {
                    let success = printOp.run()
                    if success {
                        completion(nil)
                    } else {
                        let error = NSError(domain: "PDFExporterError", code: 1, userInfo: [NSLocalizedDescriptionKey: "PDFのエクスポート（印刷処理）に失敗しました"])
                        completion(error)
                    }
                }
            }
        }
    }

    @objc func printOperationDidRun(_ printOperation: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        if success {
            self.completion(nil)
        } else {
            let error = NSError(domain: "PDFExporterError", code: 1, userInfo: [NSLocalizedDescriptionKey: "PDFのエクスポートに失敗しました"])
            self.completion(error)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        completion(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        completion(error)
    }
}
