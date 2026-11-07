import Foundation

/// 目次の 1 項目
struct OutlineItem: Identifiable, Equatable {
    let id: Int
    let level: Int
    let title: String
    /// 0 始まりのソース行
    let line: Int
}

/// 見出しを軽量に抜き出す。閲覧でも編集でも同じ目次を出すために Swift 側で持つ。
enum OutlineParser {
    static func parse(_ text: String) -> [OutlineItem] {
        var items: [OutlineItem] = []
        var fence: Substring?
        var inFrontMatter = false
        var previous: (text: String, index: Int)?
        var index = 0

        text.enumerateLines { rawLine, _ in
            defer { index += 1 }
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            // フロントマター
            if index == 0, line == "---" || line == "+++" {
                inFrontMatter = true
                return
            }
            if inFrontMatter {
                if line == "---" || line == "+++" || line == "..." { inFrontMatter = false }
                return
            }

            // コードブロックの中の # は見出しではない
            if let current = fence {
                if line.hasPrefix(current), line.drop(while: { $0 == current.first }).isEmpty { fence = nil }
                previous = nil
                return
            }
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                let marker = line.first!
                fence = Substring(String(line.prefix(while: { $0 == marker })))
                previous = nil
                return
            }

            // ATX 見出し
            if line.hasPrefix("#") {
                let hashes = line.prefix(while: { $0 == "#" }).count
                let rest = line.dropFirst(hashes)
                if hashes <= 6, rest.isEmpty || rest.first == " " || rest.first == "\t" {
                    let title = cleanTitle(String(rest))
                    if !title.isEmpty {
                        items.append(OutlineItem(id: items.count, level: hashes, title: title, line: index))
                    }
                    previous = nil
                    return
                }
            }

            // Setext 見出し（直前の行を下線で見出しにする）
            if let prev = previous, !line.isEmpty {
                if line.allSatisfy({ $0 == "=" }) || (line.count >= 2 && line.allSatisfy({ $0 == "-" })) {
                    let level = line.first == "=" ? 1 : 2
                    items.append(OutlineItem(id: items.count, level: level, title: cleanTitle(prev.text), line: prev.index))
                    previous = nil
                    return
                }
            }
            previous = line.isEmpty ? nil : (line, index)
        }
        return items
    }

    private static let inlinePatterns: [(NSRegularExpression, String)] = {
        let table: [(String, String)] = [
            (#"!\[([^\]]*)\]\([^)]*\)"#, "$1"),
            (#"\[([^\]]*)\]\([^)]*\)"#, "$1"),
            (#"\[\[(?:[^\]|]*\|)?([^\]]*)\]\]"#, "$1"),
            (#"(\*\*|__)(.+?)\1"#, "$2"),
            (#"(?<![\w*])\*([^*]+)\*"#, "$1"),
            (#"~~(.+?)~~"#, "$1"),
            (#"==(.+?)=="#, "$1"),
            (#"`([^`]*)`"#, "$1"),
            (#"\s*\{[#.][^}]*\}\s*$"#, ""),
            (#"\s+#+\s*$"#, ""),
        ]
        return table.compactMap { pattern, template in
            (try? NSRegularExpression(pattern: pattern)).map { ($0, template) }
        }
    }()

    /// 見出しの Markdown 記号を取り除く
    static func cleanTitle(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespaces)
        for (regex, template) in inlinePatterns {
            let range = NSRange(s.startIndex..., in: s)
            s = regex.stringByReplacingMatches(in: s, range: range, withTemplate: template)
        }
        return s.trimmingCharacters(in: .whitespaces)
    }
}
