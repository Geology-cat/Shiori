import SwiftUI
import WebKit

/// PDF 書き出し時にプレビューで使われている WKWebView を流用するためのレジストリ。
final class PreviewRegistry {
    static let shared = PreviewRegistry()
    weak var activeWebView: WKWebView?
}

/// Markdown を HTML に変換して WKWebView で表示するプレビュー。
/// KaTeX・mermaid はバンドル同梱のアセットでオフライン描画する。
struct PreviewView: View {
    let text: String

    var body: some View {
        // 冒頭の YAML フロントマターはプレビューでは描画しない
        MarkdownWebView(markdown: FrontMatter.strip(text))
            .background(Color(nsColor: .textBackgroundColor))
    }
}

struct MarkdownWebView: NSViewRepresentable {
    let markdown: String
    /// 打鍵中の連続再ロードを抑制するデバウンス遅延 (秒)
    private static let debounceInterval: TimeInterval = 0.2

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        PreviewRegistry.shared.activeWebView = webView
        // バンドル内のリソースディレクトリを baseURL にしてローカルアセットを参照
        let baseURL = Bundle.main.resourceURL
        // 初回ロード時点で必要なスクリプト (KaTeX / mermaid) だけを骨組みに含める。
        // 数式も mermaid も含まない文書では 3.2MB の mermaid.min.js を読み込まない。
        let features = MarkdownHTML.Features(of: markdown)
        webView.loadHTMLString(
            MarkdownHTML.renderShell(markdown: markdown, features: features),
            baseURL: baseURL
        )
        context.coordinator.lastMarkdown = markdown
        context.coordinator.loadedFeatures = features
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        PreviewRegistry.shared.activeWebView = webView
        let coordinator = context.coordinator
        if coordinator.lastMarkdown == markdown { return }
        coordinator.lastMarkdown = markdown

        // ページ全体のリロード (= 3.2MB の mermaid 等を毎回 parse し直す) は高コストなので、
        // 原則として本文 DOM だけを JS で差し替える。連続打鍵はデバウンスで間引く。
        coordinator.pendingWork?.cancel()
        let baseURL = Bundle.main.resourceURL
        let work = DispatchWorkItem {
            let newFeatures = MarkdownHTML.Features(of: markdown)
            // 既にロード済みのスクリプトで描画可能なら差分更新で済ませる。
            // 新たに数式 / mermaid が必要になった場合だけ一度だけ全リロードする。
            if coordinator.loadedFeatures.covers(newFeatures) {
                let body = HTMLRenderer.renderBody(markdown: FrontMatter.strip(markdown))
                guard let json = MarkdownHTML.jsStringLiteral(body) else { return }
                webView.evaluateJavaScript("applyMarkdown(\(json));") { _, error in
                    // ページ未ロード等で applyMarkdown が未定義なら全リロードにフォールバック
                    guard error != nil else { return }
                    webView.loadHTMLString(
                        MarkdownHTML.renderShell(markdown: markdown, features: coordinator.loadedFeatures),
                        baseURL: baseURL
                    )
                }
            } else {
                coordinator.loadedFeatures.formUnion(newFeatures)
                webView.evaluateJavaScript("window.scrollY") { result, _ in
                    coordinator.lastScrollY = result as? CGFloat ?? 0
                    webView.loadHTMLString(
                        MarkdownHTML.renderShell(markdown: markdown, features: coordinator.loadedFeatures),
                        baseURL: baseURL
                    )
                }
            }
        }
        coordinator.pendingWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.debounceInterval, execute: work)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastMarkdown: String?
        var pendingWork: DispatchWorkItem?
        var lastScrollY: CGFloat = 0
        var loadedFeatures = MarkdownHTML.Features()

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // 全リロード経由のときだけスクロール位置を復元する
            // (差分更新では DOM が保持されるため復元不要)。
            if lastScrollY > 0 {
                webView.evaluateJavaScript("window.scrollTo(0, \(lastScrollY));")
                lastScrollY = 0
            }
        }
    }
}

// MARK: - HTML 生成 (プレビュー / エクスポート共通)

enum MarkdownHTML {

    // MARK: - プレビューに必要な機能 (重いスクリプトの条件付き読み込み用)

    /// 文書が KaTeX (数式) / mermaid を必要とするかを表す。
    /// 必要なときだけ対応スクリプトを骨組みに含め、不要な文書では
    /// 3.2MB の mermaid.min.js 等をそもそもロードしない。
    struct Features {
        var math = false
        var mermaid = false

        init() {}

        init(of markdown: String) {
            // `$` を含めば数式の可能性あり (誤検出しても KaTeX が何もしないだけで無害)
            math = markdown.contains("$")
            mermaid = markdown.contains("```mermaid")
        }

        /// self が other の必要機能をすべて満たしているか
        func covers(_ other: Features) -> Bool {
            (math || !other.math) && (mermaid || !other.mermaid)
        }

        mutating func formUnion(_ other: Features) {
            math = math || other.math
            mermaid = mermaid || other.mermaid
        }
    }

    /// 文字列を JS の文字列リテラル (JSON 表記) に変換する。evaluateJavaScript への安全な受け渡し用。
    static func jsStringLiteral(_ s: String) -> String? {
        guard let data = try? JSONEncoder().encode(s) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - プレビュー用骨組み (バンドルアセット参照)

    /// 初回ロード用の HTML 骨組み。本文は #content に埋め込み、以後の更新は
    /// applyMarkdown(html) で #content の innerHTML だけを差し替えて再描画する
    /// (ページ全体・スクリプトの再ロードを避けてメモリ消費とピークを抑える)。
    static func renderShell(markdown: String, features: Features) -> String {
        let body = HTMLRenderer.renderBody(markdown: FrontMatter.strip(markdown))
        let mathHead = features.math ? """
        <link rel="stylesheet" href="katex/katex.min.css">
        <script defer src="katex/katex.min.js"></script>
        <script defer src="katex/mhchem.min.js"></script>
        <script defer src="katex/auto-render.min.js"></script>
        """ : ""
        let mermaidHead = features.mermaid ? """
        <script defer src="mermaid/mermaid.min.js"></script>
        """ : ""

        return """
        <!DOCTYPE html>
        <html lang="ja">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        \(mathHead)
        \(mermaidHead)
        <style>\(css)</style>
        <script>
          var MATH_OPTS = {
            delimiters: [
              {left: '$$', right: '$$', display: true},
              {left: '$', right: '$', display: false},
              {left: '\\\\(', right: '\\\\)', display: false},
              {left: '\\\\[', right: '\\\\]', display: true}
            ],
            ignoredTags: ['script', 'noscript', 'style', 'textarea', 'pre', 'code'],
            throwOnError: false
          };
          // #content の現在の内容に対して数式・mermaid を描画する
          function renderContent() {
            var root = document.getElementById('content');
            if (!root) return;
            if (typeof renderMathInElement !== 'undefined') {
              renderMathInElement(root, MATH_OPTS);
            }
            root.querySelectorAll('pre > code.language-mermaid').forEach(function(code) {
              var pre = code.parentNode;
              var replacement = document.createElement('pre');
              replacement.className = 'mermaid';
              replacement.textContent = code.textContent;
              pre.replaceWith(replacement);
            });
            if (typeof mermaid !== 'undefined') {
              mermaid.run({ querySelector: '#content pre.mermaid' }).catch(function(e) { console.warn('mermaid:', e); });
            }
          }
          // 本文だけを差し替えて再描画 (差分更新の入口)
          function applyMarkdown(html) {
            var root = document.getElementById('content');
            if (!root) return;
            root.innerHTML = html;
            renderContent();
          }
          document.addEventListener('DOMContentLoaded', function() {
            if (typeof mermaid !== 'undefined') {
              mermaid.initialize({ startOnLoad: false, theme: 'default', securityLevel: 'loose' });
            }
            renderContent();
          });
        </script>
        </head>
        <body>
        <div id="content">\(body)</div>
        </body>
        </html>
        """
    }

    // MARK: - PDF エクスポート用 (バンドルアセット参照 + 印刷最適化)

    static func renderForExport(markdown: String) -> String {
        let body = HTMLRenderer.renderBody(markdown: markdown)
        return """
        <!DOCTYPE html>
        <html lang="ja">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <link rel="stylesheet" href="katex/katex.min.css">
        <script src="katex/katex.min.js"></script>
        <script src="katex/mhchem.min.js"></script>
        <script src="katex/auto-render.min.js"></script>
        <script src="mermaid/mermaid.min.js"></script>
        <style>\(css)</style>
        <style>\(printCss)</style>
        </head>
        <body>
        \(body)
        <script>
          // KaTeX レンダリング
          renderMathInElement(document.body, {
            delimiters: [
              {left: '$$', right: '$$', display: true},
              {left: '$', right: '$', display: false},
              {left: '\\\\\\\\(', right: '\\\\\\\\)', display: false},
              {left: '\\\\\\\\[', right: '\\\\\\\\]', display: true}
            ],
            ignoredTags: ['script', 'noscript', 'style', 'textarea', 'pre', 'code'],
            throwOnError: false
          });
          // mermaid ブロック変換
          document.querySelectorAll('pre > code.language-mermaid').forEach(function(code) {
            var pre = code.parentNode;
            var replacement = document.createElement('pre');
            replacement.className = 'mermaid';
            replacement.textContent = code.textContent;
            pre.replaceWith(replacement);
          });
          if (typeof mermaid !== 'undefined') {
            mermaid.initialize({ startOnLoad: false, theme: 'default', securityLevel: 'loose' });
            mermaid.run({ querySelector: 'pre.mermaid' }).catch(function(e) { console.warn('mermaid:', e); });
          }
        </script>
        </body>
        </html>
        """
    }

    // MARK: - HTML エクスポート用 (CDN 参照のスタンドアロン HTML)

    static func renderStandalone(markdown: String) -> String {
        let body = HTMLRenderer.renderBody(markdown: markdown)
        return """
        <!DOCTYPE html>
        <html lang="ja">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Markdown Export</title>
        <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/katex.min.css">
        <script defer src="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/katex.min.js"></script>
        <script defer src="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/contrib/mhchem.min.js"></script>
        <script defer src="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/contrib/auto-render.min.js"
                onload="renderMathInElement(document.body, {
                  delimiters: [
                    {left: '$$', right: '$$', display: true},
                    {left: '$', right: '$', display: false},
                    {left: '\\\\\\\\(', right: '\\\\\\\\)', display: false},
                    {left: '\\\\\\\\[', right: '\\\\\\\\]', display: true}
                  ],
                  ignoredTags: ['script', 'noscript', 'style', 'textarea', 'pre', 'code'],
                  throwOnError: false
                });"></script>
        <script type="module">
          import mermaid from 'https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs';
          document.querySelectorAll('pre > code.language-mermaid').forEach((code) => {
            const pre = code.parentNode;
            const replacement = document.createElement('pre');
            replacement.className = 'mermaid';
            replacement.textContent = code.textContent;
            pre.replaceWith(replacement);
          });
          mermaid.initialize({ startOnLoad: false, theme: 'default', securityLevel: 'loose' });
          mermaid.run({ querySelector: 'pre.mermaid' }).catch((e) => console.warn('mermaid:', e));
        </script>
        <style>\(css)</style>
        <style>\(printCss)</style>
        </head>
        <body>
        \(body)
        </body>
        </html>
        """
    }

    // MARK: - CSS

    private static let css = """
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue",
                   "Hiragino Sans", "Hiragino Kaku Gothic ProN", "Yu Gothic",
                   "Meiryo", sans-serif;
      font-size: 14px;
      line-height: 1.65;
      color: #1f2328;
      padding: 18px 22px;
      margin: 0;
      word-wrap: break-word;
      background: transparent;
    }
    @media (prefers-color-scheme: dark) {
      body { color: #e6edf3; }
      h1, h2 { border-bottom-color: #30363d; }
      code { background-color: rgba(110,118,129,0.4); }
      pre { background-color: #161b22; }
      blockquote { color: #8b949e; border-left-color: #30363d; }
      th, td { border-color: #30363d; }
      th { background: #161b22; }
      tr:nth-child(2n) { background: #161b22; }
      hr { background-color: #30363d; }
    }
    h1, h2, h3, h4, h5, h6 {
      margin-top: 1.4em; margin-bottom: 0.5em;
      font-weight: 600; line-height: 1.25;
    }
    h1 { font-size: 1.9em; border-bottom: 1px solid #d1d9e0; padding-bottom: 0.3em; }
    h2 { font-size: 1.5em; border-bottom: 1px solid #d1d9e0; padding-bottom: 0.3em; }
    h3 { font-size: 1.25em; }
    p { margin: 0 0 0.8em 0; }
    a { color: #0969da; text-decoration: none; }
    code {
      padding: 0.18em 0.35em; font-size: 88%;
      background-color: rgba(175,184,193,0.2); border-radius: 4px;
      font-family: ui-monospace, SFMono-Regular, "SF Mono", Menlo, monospace;
    }
    pre { padding: 12px; overflow: auto; font-size: 88%; line-height: 1.45;
          background-color: #f6f8fa; border-radius: 6px; }
    pre code { padding: 0; background: transparent; border-radius: 0; font-size: 100%; }
    blockquote { padding: 0 1em; color: #59636e;
                 border-left: 0.25em solid #d1d9e0; margin: 0 0 0.8em 0; }
    ul, ol { padding-left: 1.8em; margin: 0 0 0.8em 0; }
    li { margin-top: 0.2em; }
    table { border-collapse: collapse; margin: 0 0 0.8em 0; }
    th, td { padding: 6px 12px; border: 1px solid #d1d9e0; vertical-align: top; }
    th { font-weight: 600; background: #f6f8fa; }
    tr:nth-child(2n) { background: #f8fafb; }
    hr { height: 2px; border: 0; background: #d1d9e0; margin: 1.5em 0; }
    img { max-width: 100%; height: auto; }
    input[type="checkbox"] { margin-right: 0.4em; }
    del { text-decoration: line-through; color: #59636e; }
    .katex-display { margin: 0.6em 0; }
    .katex { font-family: "KaTeX_Math", "Latin Modern Math", "Computer Modern", serif !important; }
    """

    /// 印刷・PDF 書き出し用の追加 CSS
    private static let printCss = """
    @media print {
      @page { size: A4; margin: 16mm 16mm; }
      body { padding: 0; font-size: 11pt; color: #000; background: #fff; }
      a { color: #0969da; text-decoration: none; }
      h1, h2, h3, h4, h5, h6 { page-break-after: avoid; }
      pre, blockquote, table, .katex-display { page-break-inside: avoid; }
      img { page-break-inside: avoid; }
    }
    /* PDF 書き出し時は常にライトモード */
    body { color: #1f2328; background: #fff; }
    """
}
