import Foundation

extension Notification.Name {
    static let exportHTML = Notification.Name("MarkdownEditor.exportHTML")
}

/// Markdown → 完全な HTML ファイルを生成する。
/// KaTeX / mermaid のスクリプトを含む自己完結した HTML を出力する。
enum HTMLExporter {
    /// HTML エクスポート。インライン埋め込み版 (CDN 不要) の HTML を生成して保存する。
    static func export(markdown: String, to url: URL) -> Error? {
        let html = MarkdownHTML.renderStandalone(markdown: FrontMatter.strip(markdown))
        do {
            try html.write(to: url, atomically: true, encoding: .utf8)
            return nil
        } catch {
            return error
        }
    }
}
