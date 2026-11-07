import Foundation
import Markdown

/// Markdown を HTML 本文に変換する (CSS や <html> 等は含まない、body 内に入れる断片)。
/// プレビュー用の WKWebView から呼ばれる。
enum HTMLRenderer {
    static func renderBody(markdown: String) -> String {
        let document = Document(parsing: markdown)
        let visitor = HTMLVisitor()
        return visitor.visit(document)
    }
}

// MARK: - Visitor

private final class HTMLVisitor: MarkupVisitor {
    typealias Result = String

    func visit(_ markup: any Markup) -> String {
        switch markup {
        case let m as Document:       return visitDocument(m)
        case let m as Heading:        return visitHeading(m)
        case let m as Paragraph:      return visitParagraph(m)
        case let m as BlockQuote:     return visitBlockQuote(m)
        case let m as CodeBlock:      return visitCodeBlock(m)
        case let m as HTMLBlock:      return visitHTMLBlock(m)
        case let m as ThematicBreak:  return visitThematicBreak(m)
        case let m as UnorderedList:  return visitUnorderedList(m)
        case let m as OrderedList:    return visitOrderedList(m)
        case let m as ListItem:       return visitListItem(m)
        case let m as Markdown.Table: return visitTable(m)
        case let m as Text:           return visitText(m)
        case let m as Emphasis:       return visitEmphasis(m)
        case let m as Strong:         return visitStrong(m)
        case let m as Strikethrough:  return visitStrikethrough(m)
        case let m as InlineCode:     return visitInlineCode(m)
        case let m as Link:           return visitLink(m)
        case let m as Image:          return visitImage(m)
        case let m as LineBreak:      return visitLineBreak(m)
        case let m as SoftBreak:      return visitSoftBreak(m)
        case let m as InlineHTML:     return visitInlineHTML(m)
        default:                      return defaultVisit(markup)
        }
    }

    func defaultVisit(_ markup: any Markup) -> String {
        var out = ""
        for child in markup.children { out += visit(child) }
        return out
    }

    func visitDocument(_ document: Document) -> String {
        var out = ""
        for child in document.children { out += visit(child) }
        return out
    }

    func visitHeading(_ heading: Heading) -> String {
        let level = max(1, min(6, heading.level))
        var inner = ""
        for child in heading.children { inner += visit(child) }
        return "<h\(level)>\(inner)</h\(level)>\n"
    }

    func visitParagraph(_ paragraph: Paragraph) -> String {
        var inner = ""
        for child in paragraph.children { inner += visit(child) }
        return "<p>\(inner)</p>\n"
    }

    func visitText(_ text: Text) -> String { escapeText(text.string) }

    func visitEmphasis(_ emphasis: Emphasis) -> String {
        var inner = ""
        for child in emphasis.children { inner += visit(child) }
        return "<em>\(inner)</em>"
    }

    func visitStrong(_ strong: Strong) -> String {
        var inner = ""
        for child in strong.children { inner += visit(child) }
        return "<strong>\(inner)</strong>"
    }

    func visitStrikethrough(_ s: Strikethrough) -> String {
        var inner = ""
        for child in s.children { inner += visit(child) }
        return "<del>\(inner)</del>"
    }

    func visitInlineCode(_ code: InlineCode) -> String {
        "<code>\(escapeText(code.code))</code>"
    }

    func visitCodeBlock(_ block: CodeBlock) -> String {
        let lang = block.language?.trimmingCharacters(in: .whitespaces) ?? ""
        let cls = lang.isEmpty ? "" : " class=\"language-\(escapeAttr(lang))\""
        return "<pre><code\(cls)>\(escapeText(block.code))</code></pre>\n"
    }

    func visitLink(_ link: Link) -> String {
        var inner = ""
        for child in link.children { inner += visit(child) }
        let href = link.destination.map(escapeAttr) ?? ""
        return "<a href=\"\(href)\">\(inner)</a>"
    }

    func visitImage(_ image: Image) -> String {
        let src = image.source.map(escapeAttr) ?? ""
        let alt = image.plainText
        return "<img src=\"\(src)\" alt=\"\(escapeAttr(alt))\">"
    }

    func visitBlockQuote(_ blockQuote: BlockQuote) -> String {
        var inner = ""
        for child in blockQuote.children { inner += visit(child) }
        return "<blockquote>\n\(inner)</blockquote>\n"
    }

    func visitUnorderedList(_ list: UnorderedList) -> String {
        var items = ""
        for child in list.children { items += visit(child) }
        return "<ul>\n\(items)</ul>\n"
    }

    func visitOrderedList(_ list: OrderedList) -> String {
        var items = ""
        for child in list.children { items += visit(child) }
        let start = Int(list.startIndex)
        let startAttr = (start == 1) ? "" : " start=\"\(start)\""
        return "<ol\(startAttr)>\n\(items)</ol>\n"
    }

    func visitListItem(_ listItem: ListItem) -> String {
        var inner = ""
        for child in listItem.children { inner += visit(child) }
        if let checkbox = listItem.checkbox {
            let checked = (checkbox == .checked) ? " checked" : ""
            return "<li><input type=\"checkbox\" disabled\(checked)>\(inner)</li>\n"
        }
        return "<li>\(inner)</li>\n"
    }

    func visitTable(_ table: Markdown.Table) -> String {
        var html = "<table>\n<thead>\n<tr>"
        for cell in table.head.cells {
            var inner = ""
            for child in cell.children { inner += visit(child) }
            html += "<th>\(inner)</th>"
        }
        html += "</tr>\n</thead>\n<tbody>\n"
        for row in table.body.rows {
            html += "<tr>"
            for cell in row.cells {
                var inner = ""
                for child in cell.children { inner += visit(child) }
                html += "<td>\(inner)</td>"
            }
            html += "</tr>\n"
        }
        html += "</tbody>\n</table>\n"
        return html
    }

    func visitThematicBreak(_ thematicBreak: ThematicBreak) -> String { "<hr>\n" }
    func visitLineBreak(_ lineBreak: LineBreak) -> String { "<br>\n" }
    func visitSoftBreak(_ softBreak: SoftBreak) -> String { "\n" }
    func visitInlineHTML(_ inlineHTML: InlineHTML) -> String { inlineHTML.rawHTML }
    func visitHTMLBlock(_ htmlBlock: HTMLBlock) -> String { htmlBlock.rawHTML }

    private func escapeText(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for ch in s {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            default:  out.append(ch)
            }
        }
        return out
    }

    private func escapeAttr(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for ch in s {
            switch ch {
            case "&":  out += "&amp;"
            case "<":  out += "&lt;"
            case ">":  out += "&gt;"
            case "\"": out += "&quot;"
            case "'":  out += "&#39;"
            default:   out.append(ch)
            }
        }
        return out
    }
}
