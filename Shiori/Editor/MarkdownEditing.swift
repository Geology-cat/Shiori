import Foundation

/// エディタの編集ロジックのうち、テキストだけで判断できるもの（単体テストの対象）
enum MarkdownEditing {
    /// 行頭のリスト記号の解析結果
    struct ListPrefix: Equatable {
        /// 字下げ
        let indent: String
        /// 「- 」「1. 」「> 」などの記号部分
        let marker: String
        /// チェックボックス付きか
        let isTask: Bool
        /// 記号のあとに本文がない
        let isEmpty: Bool
    }

    private static let listRegex = try! NSRegularExpression(
        pattern: #"^(\s*)((?:[-*+]|(\d+)([.)]))\s+)(\[[ xX/\-]\]\s+)?(.*)$"#
    )
    private static let quoteRegex = try! NSRegularExpression(pattern: #"^(\s*(?:>\s?)+)(.*)$"#)

    static func parseList(_ line: String) -> ListPrefix? {
        let ns = line as NSString
        let range = NSRange(location: 0, length: ns.length)
        if let m = listRegex.firstMatch(in: line, range: range) {
            let indent = ns.substring(with: m.range(at: 1))
            let marker = ns.substring(with: m.range(at: 2))
            let isTask = m.range(at: 5).location != NSNotFound
            let rest = ns.substring(with: m.range(at: 6))
            return ListPrefix(indent: indent, marker: marker, isTask: isTask, isEmpty: rest.isEmpty)
        }
        if let m = quoteRegex.firstMatch(in: line, range: range) {
            let marker = ns.substring(with: m.range(at: 1))
            let rest = ns.substring(with: m.range(at: 2))
            return ListPrefix(indent: "", marker: marker, isTask: false, isEmpty: rest.isEmpty)
        }
        return nil
    }

    /// Enter を押したときに次の行へ入れる文字列。リストでなければ nil
    static func continuation(of prefix: ListPrefix) -> String {
        var marker = prefix.marker
        // 番号付きリストは番号を進める
        if let m = try? NSRegularExpression(pattern: #"^(\d+)([.)])(\s+)$"#).firstMatch(
            in: marker, range: NSRange(location: 0, length: (marker as NSString).length)
        ) {
            let ns = marker as NSString
            let number = (Int(ns.substring(with: m.range(at: 1))) ?? 0) + 1
            marker = "\(number)\(ns.substring(with: m.range(at: 2)))\(ns.substring(with: m.range(at: 3)))"
        }
        return prefix.indent + marker + (prefix.isTask ? "[ ] " : "")
    }

    /// 選択範囲に使う表を組み立てる
    static func tableTemplate(rows: Int, columns: Int) -> String {
        let header = (1...columns).map { "列\($0)" }
        let separator = Array(repeating: "---", count: columns)
        let empty = Array(repeating: "    ", count: columns)
        var lines = ["| " + header.joined(separator: " | ") + " |", "| " + separator.joined(separator: " | ") + " |"]
        for _ in 0..<rows { lines.append("| " + empty.joined(separator: " | ") + " |") }
        return lines.joined(separator: "\n")
    }

    /// base から target への相対パス（Markdown のリンク用に / 区切り）
    static func relativePath(from base: URL, to target: URL) -> String {
        let baseParts = base.standardizedFileURL.pathComponents
        let targetParts = target.standardizedFileURL.pathComponents
        var common = 0
        while common < baseParts.count, common < targetParts.count, baseParts[common] == targetParts[common] { common += 1 }
        let ups = Array(repeating: "..", count: baseParts.count - common)
        return (ups + targetParts[common...]).joined(separator: "/")
    }

    /// Markdown のリンク先として書けるよう、空白を含むパスは <> で囲む
    static func linkDestination(_ path: String) -> String {
        path.contains(" ") || path.contains("(") || path.contains(")") ? "<\(path)>" : path
    }
}
