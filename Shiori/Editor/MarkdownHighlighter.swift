import AppKit

/// エディタの表示スタイル（フォントなど）
struct EditorStyle: Equatable {
    var fontSize: CGFloat
    var fontName: String

    var font: NSFont {
        if !fontName.isEmpty, let named = NSFont(name: fontName, size: fontSize) { return named }
        return NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }

    var boldFont: NSFont {
        let converted = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        if converted.fontDescriptor.symbolicTraits.contains(.bold) { return converted }
        return NSFont.monospacedSystemFont(ofSize: fontSize, weight: .bold)
    }

    var italicFont: NSFont {
        let descriptor = font.fontDescriptor.withSymbolicTraits(.italic)
        return NSFont(descriptor: descriptor, size: fontSize) ?? font
    }

    var paragraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = (fontSize * 0.42).rounded()
        return style
    }

    static var current: EditorStyle {
        let s = AppSettings.shared
        return EditorStyle(fontSize: CGFloat(s.editorFontSize), fontName: s.editorFontName)
    }
}

/// ソースエディタの構文ハイライト。
/// 行ごとに内容のハッシュを取り、変わった行だけ属性を付け直すので、大きな文書でも打鍵を妨げない。
final class MarkdownHighlighter {
    private enum BlockState: Hashable {
        case normal
        case frontMatter(String)
        case fence(String)
        case math(String)
    }

    private struct LineInfo {
        let key: Int
        let range: NSRange
        let state: BlockState
        /// この行がブロックの区切り（``` や $$）かどうか
        let isDelimiter: Bool
    }

    private let storage: NSTextStorage
    private var previousKeys: [Int] = []
    private var appliedStyle: EditorStyle?
    /// これより大きい文書は色付けしない（編集を重くしないため）
    private static let maxLength = 3_000_000

    init(storage: NSTextStorage) {
        self.storage = storage
    }

    /// 全行を次回の更新で付け直す
    func invalidate() {
        previousKeys = []
    }

    /// 変更された行の属性を更新する
    func update(style: EditorStyle = .current) {
        if appliedStyle != style {
            appliedStyle = style
            previousKeys = []
        }
        let length = storage.length
        if length > Self.maxLength {
            if !previousKeys.isEmpty || appliedStyle == nil { return }
            storage.setAttributes(baseAttributes(style), range: NSRange(location: 0, length: length))
            previousKeys = [length]
            return
        }

        let ns = storage.string as NSString
        let lines = scanLines(ns)
        let keys = lines.map(\.key)

        // 前回と一致する先頭・末尾の行を飛ばす
        var prefix = 0
        let maxPrefix = min(keys.count, previousKeys.count)
        while prefix < maxPrefix, keys[prefix] == previousKeys[prefix] { prefix += 1 }
        var suffix = 0
        let maxSuffix = min(keys.count, previousKeys.count) - prefix
        while suffix < maxSuffix, keys[keys.count - 1 - suffix] == previousKeys[previousKeys.count - 1 - suffix] { suffix += 1 }
        previousKeys = keys
        guard prefix + suffix < lines.count else { return }

        let base = baseAttributes(style)
        storage.beginEditing()
        for line in lines[prefix..<(lines.count - suffix)] {
            guard line.range.length > 0 else { continue }
            storage.setAttributes(base, range: line.range)
            decorate(line: line, in: ns, style: style)
        }
        storage.endEditing()
    }

    func baseAttributes(_ style: EditorStyle) -> [NSAttributedString.Key: Any] {
        [.font: style.font, .foregroundColor: NSColor.textColor, .paragraphStyle: style.paragraphStyle]
    }

    // MARK: - 行の走査

    private func scanLines(_ ns: NSString) -> [LineInfo] {
        var result: [LineInfo] = []
        result.reserveCapacity(ns.length / 40)
        var state: BlockState = .normal
        var location = 0
        var index = 0
        let total = ns.length

        while location < total {
            var lineEnd = 0
            var contentsEnd = 0
            ns.getLineStart(nil, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
            let contentRange = NSRange(location: location, length: contentsEnd - location)
            let text = ns.substring(with: contentRange)
            let trimmed = text.trimmingCharacters(in: .whitespaces)

            var isDelimiter = false
            var lineState = state
            switch state {
            case .normal:
                if index == 0, trimmed == "---" || trimmed == "+++" {
                    state = .frontMatter(trimmed)
                    lineState = state
                    isDelimiter = true
                } else if let fence = Self.fenceMarker(trimmed) {
                    state = .fence(fence)
                    lineState = state
                    isDelimiter = true
                } else if trimmed.hasPrefix("$$"), !(trimmed.count > 2 && trimmed.hasSuffix("$$")) {
                    state = .math("$$")
                    lineState = state
                    isDelimiter = true
                } else if trimmed.hasPrefix("$$") {
                    lineState = .math("$$")
                    isDelimiter = true
                }
            case .frontMatter(let marker):
                if trimmed == marker || trimmed == "..." {
                    state = .normal
                    isDelimiter = true
                }
            case .fence(let marker):
                if trimmed.hasPrefix(marker), trimmed.drop(while: { $0 == marker.first }).isEmpty {
                    state = .normal
                    isDelimiter = true
                }
            case .math(let marker):
                if trimmed.hasSuffix(marker) {
                    state = .normal
                    isDelimiter = true
                }
            }

            var hasher = Hasher()
            hasher.combine(text)
            hasher.combine(lineState)
            hasher.combine(isDelimiter)
            // 行末の改行まで含めて属性を付ける
            result.append(LineInfo(
                key: hasher.finalize(),
                range: NSRange(location: location, length: lineEnd - location),
                state: lineState,
                isDelimiter: isDelimiter
            ))
            location = lineEnd
            index += 1
        }
        return result
    }

    private static func fenceMarker(_ trimmed: String) -> String? {
        for ch: Character in ["`", "~"] {
            let run = trimmed.prefix(while: { $0 == ch })
            if run.count >= 3 { return String(run) }
        }
        return nil
    }

    // MARK: - 色付け

    private func decorate(line: LineInfo, in ns: NSString, style: EditorStyle) {
        switch line.state {
        case .frontMatter:
            storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: line.range)
            return
        case .fence:
            let color = line.isDelimiter ? NSColor.tertiaryLabelColor : Palette.code
            storage.addAttribute(.foregroundColor, value: color, range: line.range)
            return
        case .math:
            storage.addAttribute(.foregroundColor, value: Palette.math, range: line.range)
            return
        case .normal:
            break
        }

        let text = ns.substring(with: line.range)
        let local = NSRange(location: 0, length: (text as NSString).length)
        let offset = line.range.location

        func apply(_ range: NSRange, _ attrs: [NSAttributedString.Key: Any]) {
            storage.addAttributes(attrs, range: NSRange(location: range.location + offset, length: range.length))
        }

        // 行全体に効く記法
        if let m = Rx.heading.firstMatch(in: text, range: local) {
            apply(local, [.font: style.boldFont, .foregroundColor: Palette.heading])
            apply(m.range(at: 1), [.foregroundColor: NSColor.tertiaryLabelColor])
        } else if Rx.thematicBreak.firstMatch(in: text, range: local) != nil {
            apply(local, [.foregroundColor: NSColor.tertiaryLabelColor])
            return
        } else if let m = Rx.quote.firstMatch(in: text, range: local) {
            apply(local, [.foregroundColor: NSColor.secondaryLabelColor])
            apply(m.range(at: 1), [.foregroundColor: Palette.accent])
        } else if let m = Rx.listMarker.firstMatch(in: text, range: local) {
            apply(m.range(at: 1), [.foregroundColor: Palette.accent])
        } else if Rx.tableRow.firstMatch(in: text, range: local) != nil {
            for match in Rx.tablePipe.matches(in: text, range: local) {
                apply(match.range, [.foregroundColor: NSColor.tertiaryLabelColor])
            }
        }

        // 行内の記法（後のものが優先されるので、コードと数式を最後に塗る）
        for m in Rx.link.matches(in: text, range: local) {
            apply(m.range, [.foregroundColor: Palette.link])
            apply(m.range(at: 1), [.foregroundColor: NSColor.tertiaryLabelColor])
        }
        for m in Rx.wikilink.matches(in: text, range: local) { apply(m.range, [.foregroundColor: Palette.link]) }
        for m in Rx.autolink.matches(in: text, range: local) { apply(m.range, [.foregroundColor: Palette.link]) }
        for m in Rx.bold.matches(in: text, range: local) { apply(m.range, [.font: style.boldFont]) }
        for m in Rx.italic.matches(in: text, range: local) { apply(m.range, [.font: style.italicFont]) }
        for m in Rx.strike.matches(in: text, range: local) {
            apply(m.range, [.strikethroughStyle: NSUnderlineStyle.single.rawValue, .foregroundColor: NSColor.secondaryLabelColor])
        }
        for m in Rx.mark.matches(in: text, range: local) { apply(m.range, [.backgroundColor: Palette.markBackground]) }
        for m in Rx.tag.matches(in: text, range: local) { apply(m.range(at: 1), [.foregroundColor: Palette.tag]) }
        for m in Rx.footnote.matches(in: text, range: local) { apply(m.range, [.foregroundColor: Palette.tag]) }
        for m in Rx.comment.matches(in: text, range: local) { apply(m.range, [.foregroundColor: NSColor.tertiaryLabelColor]) }
        for m in Rx.html.matches(in: text, range: local) { apply(m.range, [.foregroundColor: Palette.html]) }
        for m in Rx.math.matches(in: text, range: local) { apply(m.range, [.foregroundColor: Palette.math]) }
        for m in Rx.code.matches(in: text, range: local) {
            apply(m.range, [.foregroundColor: Palette.code, .font: style.font])
        }
    }

    private enum Palette {
        static let heading = NSColor.controlAccentColor
        static let accent = NSColor.systemOrange
        static let link = NSColor.linkColor
        static let code = NSColor.systemPink
        static let math = NSColor.systemTeal
        static let tag = NSColor.systemPurple
        static let html = NSColor.systemGray
        static let markBackground = NSColor.systemYellow.withAlphaComponent(0.3)
    }

    private enum Rx {
        static func make(_ pattern: String) -> NSRegularExpression {
            try! NSRegularExpression(pattern: pattern)
        }
        static let heading = make(#"^\s{0,3}(#{1,6}\s)"#)
        static let thematicBreak = make(#"^\s{0,3}([-*_])(\s*\1){2,}\s*$"#)
        static let quote = make(#"^\s{0,3}(>+\s?)"#)
        static let listMarker = make(#"^\s*((?:[-*+]|\d+[.)])\s(?:\[[ xX/\-]\]\s)?)"#)
        static let tableRow = make(#"^\s*\|.*\|\s*$"#)
        static let tablePipe = make(#"\|"#)
        static let link = make(#"!?\[[^\]\n]*\](\([^)\n]*\))"#)
        static let wikilink = make(#"!?\[\[[^\]\n]+\]\]"#)
        static let autolink = make(#"https?://[^\s)>\]]+"#)
        static let bold = make(#"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#)
        static let italic = make(#"(?<![*\w])\*(?=[^\s*])([^*\n]+?)(?<=\S)\*(?!\*)"#)
        static let strike = make(#"~~(?=\S)(.+?)(?<=\S)~~"#)
        static let mark = make(#"==(?=\S)(.+?)(?<=\S)=="#)
        static let tag = make(#"(?:^|\s)(#[\p{L}\p{N}_/-]*[\p{L}_/-][\p{L}\p{N}_/-]*)"#)
        static let footnote = make(#"\[\^[^\]\n]+\]"#)
        static let comment = make(#"%%.*?%%|<!--.*?-->"#)
        static let html = make(#"</?[a-zA-Z][^>\n]*>"#)
        static let math = make(#"(?<![\\$\d])\$(?=[^\s$])[^$\n]*?(?<=[^\s\\])\$(?![\d$])"#)
        static let code = make(#"(`+)(?!`)[^\n]*?(?<!`)\1(?!`)"#)
    }
}
