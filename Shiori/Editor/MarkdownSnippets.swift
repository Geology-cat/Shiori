import Foundation

/// 書式バーから挿入する定型文（テキストだけで判断できるので単体テストの対象）
extension MarkdownEditing {
    // MARK: - フロントマター

    /// フロントマターの 1 項目。text は YAML の断片（複数行でもよい）
    struct FrontMatterEntry: Equatable {
        let key: String
        let text: String
    }

    /// 項目の値を埋めるための情報
    struct FrontMatterContext {
        /// 文書名（拡張子なし）。未保存の新規文書では空
        var title: String
        /// 今日の日付（yyyy-MM-dd）
        var today: String

        static func current(title: String) -> FrontMatterContext {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.dateFormat = "yyyy-MM-dd"
            return FrontMatterContext(title: title, today: formatter.string(from: Date()))
        }
    }

    /// 単独で足せる項目
    enum FrontMatterField: String, CaseIterable, Identifiable {
        case title, author, date, updated, tags, aliases, description, abstract, draft

        var id: String { rawValue }

        var label: String {
            switch self {
            case .title: return "タイトル (title)"
            case .author: return "著者 (author)"
            case .date: return "日付 (date)"
            case .updated: return "更新日 (updated)"
            case .tags: return "タグ (tags)"
            case .aliases: return "別名 (aliases)"
            case .description: return "説明 (description)"
            case .abstract: return "概要 (abstract)"
            case .draft: return "下書き (draft)"
            }
        }

        func entry(_ context: FrontMatterContext) -> FrontMatterEntry {
            switch self {
            case .title: return FrontMatterEntry(key: "title", text: "title: " + yamlScalar(context.title))
            case .author: return FrontMatterEntry(key: "author", text: "author: ")
            case .date: return FrontMatterEntry(key: "date", text: "date: " + context.today)
            case .updated: return FrontMatterEntry(key: "updated", text: "updated: " + context.today)
            case .tags: return FrontMatterEntry(key: "tags", text: "tags:\n  - ")
            case .aliases: return FrontMatterEntry(key: "aliases", text: "aliases:\n  - ")
            case .description: return FrontMatterEntry(key: "description", text: "description: ")
            case .abstract: return FrontMatterEntry(key: "abstract", text: "abstract: ")
            case .draft: return FrontMatterEntry(key: "draft", text: "draft: true")
            }
        }
    }

    /// 文書の種類ごとのひな形
    enum FrontMatterTemplate: String, CaseIterable, Identifiable {
        case basic, blog, paper, diary, reading, obsidian

        var id: String { rawValue }

        var label: String {
            switch self {
            case .basic: return "基本（タイトル・日付・タグ）"
            case .blog: return "ブログ記事"
            case .paper: return "論文・レポート"
            case .diary: return "日記"
            case .reading: return "読書メモ"
            case .obsidian: return "Obsidian のプロパティ"
            }
        }

        func entries(_ context: FrontMatterContext) -> [FrontMatterEntry] {
            let title = FrontMatterField.title.entry(context)
            let date = FrontMatterField.date.entry(context)
            let tags = FrontMatterField.tags.entry(context)
            switch self {
            case .basic:
                return [title, date, tags]
            case .blog:
                return [title, date, FrontMatterField.updated.entry(context), FrontMatterField.description.entry(context),
                        tags, FrontMatterEntry(key: "categories", text: "categories:\n  - "),
                        FrontMatterEntry(key: "draft", text: "draft: false")]
            case .paper:
                return [title, FrontMatterField.author.entry(context), date, FrontMatterField.abstract.entry(context), tags]
            case .diary:
                return [FrontMatterEntry(key: "title", text: "title: " + context.today), date,
                        FrontMatterEntry(key: "weather", text: "weather: "),
                        FrontMatterEntry(key: "tags", text: "tags:\n  - 日記")]
            case .reading:
                return [FrontMatterEntry(key: "title", text: "title: "), FrontMatterField.author.entry(context),
                        FrontMatterEntry(key: "publisher", text: "publisher: "), date,
                        FrontMatterEntry(key: "rating", text: "rating: "),
                        FrontMatterEntry(key: "tags", text: "tags:\n  - 読書")]
            case .obsidian:
                return [tags, FrontMatterField.aliases.entry(context), FrontMatterEntry(key: "cssclasses", text: "cssclasses:\n  - ")]
            }
        }
    }

    /// 文書に加える変更。replacement を range に入れ、cursor にカーソルを置く
    struct TextEdit: Equatable {
        let range: NSRange
        let replacement: String
        let cursor: Int
    }

    enum FrontMatterMergeResult: Equatable {
        case edit(TextEdit)
        /// すべての項目がすでにある
        case nothingToAdd
        /// TOML (+++) のフロントマターなので触らない
        case unsupported
    }

    /// 先頭の YAML フロントマターの位置（--- の行から閉じの行まで）
    struct FrontMatterBlock {
        /// 閉じの行（--- / ...）の先頭
        let closingLineStart: Int
        /// すでにある最上位のキー
        let keys: Set<String>
    }

    /// 先頭のフロントマターを探す。TOML なら .unsupported 相当として isTOML を返す
    static func findFrontMatter(in text: String) -> (block: FrontMatterBlock?, isTOML: Bool) {
        let ns = text as NSString
        let lines = text.components(separatedBy: "\n")
        guard let first = lines.first else { return (nil, false) }
        let opening = first.trimmingCharacters(in: CharacterSet(charactersIn: " \t"))
        if opening == "+++" {
            // 閉じがあるときだけ TOML とみなす
            return (nil, lines.dropFirst().contains { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \t")) == "+++" })
        }
        guard opening == "---" else { return (nil, false) }
        // 「---」のすぐ後が空行なら、本文の水平線とみなす（Pandoc / Jekyll と同じ扱い）
        if lines.count > 1, lines[1].trimmingCharacters(in: .whitespaces).isEmpty { return (nil, false) }
        var offset = (first as NSString).length + 1
        var keys = Set<String>()
        var hasContent = false
        for line in lines.dropFirst() {
            let trimmed = line.trimmingCharacters(in: CharacterSet(charactersIn: " \t"))
            if trimmed == "---" || trimmed == "..." {
                guard offset <= ns.length else { break }
                // 中身があるのにキーが 1 つもなければ YAML の対応表ではない（水平線に挟まれた本文など）
                if hasContent && keys.isEmpty { return (nil, false) }
                return (FrontMatterBlock(closingLineStart: offset, keys: keys), false)
            }
            if !trimmed.isEmpty && !trimmed.hasPrefix("#") { hasContent = true }
            if let key = topLevelKey(line) { keys.insert(key) }
            offset += (line as NSString).length + 1
        }
        return (nil, false)
    }

    private static let keyRegex = try! NSRegularExpression(pattern: #"^(?:"([^"]+)"|'([^']+)'|([^\s#:\-'"][^:]*?))\s*:(?:\s|$)"#)

    /// インデントのない「key:」の行ならキー名を返す
    static func topLevelKey(_ line: String) -> String? {
        let ns = line as NSString
        guard let m = keyRegex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return nil }
        for group in 1...3 where m.range(at: group).location != NSNotFound {
            return ns.substring(with: m.range(at: group))
        }
        return nil
    }

    /// フロントマターに項目を足す。なければ文書の先頭に作り、あれば足りない項目だけ閉じの行の前に加える
    static func mergeFrontMatter(_ entries: [FrontMatterEntry], into text: String) -> FrontMatterMergeResult {
        let found = findFrontMatter(in: text)
        if found.isTOML { return .unsupported }

        if let block = found.block {
            let missing = entries.filter { !block.keys.contains($0.key) }
            guard let first = missing.first else { return .nothingToAdd }
            let insertion = missing.map(\.text).joined(separator: "\n") + "\n"
            let cursor = block.closingLineStart + (first.text as NSString).length
            return .edit(TextEdit(range: NSRange(location: block.closingLineStart, length: 0), replacement: insertion, cursor: cursor))
        }

        guard let first = entries.first else { return .nothingToAdd }
        var insertion = "---\n" + entries.map(\.text).joined(separator: "\n") + "\n---\n"
        // 本文とのあいだに空行を 1 つ置く
        if !text.isEmpty && !text.hasPrefix("\n") { insertion += "\n" }
        let cursor = ("---\n" as NSString).length + (first.text as NSString).length
        return .edit(TextEdit(range: NSRange(location: 0, length: 0), replacement: insertion, cursor: cursor))
    }

    /// YAML の値として安全に書けなければ二重引用符で囲む
    static func yamlScalar(_ value: String) -> String {
        if value.isEmpty { return "" }
        let reserved: Set<String> = ["true", "false", "yes", "no", "on", "off", "null", "~"]
        let special = CharacterSet(charactersIn: "-?:,[]{}#&*!|>'\"%@`")
        let needsQuote = value.contains(": ") || value.contains(" #") || value.hasSuffix(":")
            || value.unicodeScalars.first.map(special.contains) == true
            || value.first?.isWhitespace == true || value.last?.isWhitespace == true
            || reserved.contains(value.lowercased()) || Double(value) != nil
            || value.contains("\n")
        guard needsQuote else { return value }
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }

    // MARK: - 脚注

    private static let footnoteRegex = try! NSRegularExpression(pattern: #"\[\^(\d+)\]"#)

    /// まだ使われていない脚注番号
    static func nextFootnoteNumber(in text: String) -> Int {
        let ns = text as NSString
        let used = footnoteRegex.matches(in: text, range: NSRange(location: 0, length: ns.length))
            .compactMap { Int(ns.substring(with: $0.range(at: 1))) }
        return (used.max() ?? 0) + 1
    }

    /// 脚注の参照をカーソル位置に入れ、定義を文末に足す。カーソルは定義の本文へ
    static func insertFootnote(in text: String, at location: Int) -> [TextEdit] {
        let n = nextFootnoteNumber(in: text)
        let ns = text as NSString
        let reference = "[^\(n)]"
        // 文末の改行の数に合わせて、定義の前に空行を 1 つ置く
        var definition = "[^\(n)]: "
        if text.hasSuffix("\n\n") {
            // そのまま
        } else if text.hasSuffix("\n") {
            definition = "\n" + definition
        } else if !text.isEmpty {
            definition = "\n\n" + definition
        }
        let refLength = (reference as NSString).length
        let cursor = ns.length + refLength + (definition as NSString).length
        // 後ろから適用する前提で、文末の追加を先に並べる
        return [
            TextEdit(range: NSRange(location: ns.length, length: 0), replacement: definition, cursor: cursor),
            TextEdit(range: NSRange(location: location, length: 0), replacement: reference, cursor: cursor),
        ]
    }

    // MARK: - ブロック

    /// 選択した行を注記（> [!KIND]）で囲む。選択がなければ空の注記を作る
    static func callout(kind: String, title: String = "", foldable: Bool = false, body: String) -> String {
        var head = "> [!\(kind)]" + (foldable ? "-" : "")
        if !title.isEmpty { head += " " + title }
        if body.isEmpty { return head + "\n> " }
        let lines = body.components(separatedBy: "\n").map { $0.isEmpty ? ">" : "> " + $0 }
        return ([head] + lines).joined(separator: "\n")
    }

    /// 選択をコードブロックで囲む
    static func codeBlock(language: String, body: String) -> (text: String, cursorOffset: Int) {
        let open = "```" + language + "\n"
        let text = open + body + "\n```"
        // 本文が空ならその中へ、あれば囲みの後ろへ
        let cursor = body.isEmpty ? (open as NSString).length : (text as NSString).length
        return (text, cursor)
    }
}
