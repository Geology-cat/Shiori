import Foundation

/// .md 冒頭の YAML フロントマター (`---` で囲まれたブロック) を除去する。
/// プレビュー側でのみ呼び出され、ソースには手を入れない。
enum FrontMatter {
    /// 先頭の YAML ブロックを取り除いた markdown を返す。
    /// 仕様:
    /// - 最初の非空白行が `---` のみで構成されているときだけ対象
    /// - その次に現れる `---` または `...` のみで構成される行までを除去
    /// - 終端が見つからなければ元の文字列をそのまま返す (= 壊れた入力を全消ししない)
    /// - 改行は LF / CRLF どちらでも可
    static func strip(_ markdown: String) -> String {
        // 改行で分割 (区切り文字は失わずに行情報だけ見る)
        let lines = markdown.components(separatedBy: "\n")

        // 最初の非空白行のインデックスを探す
        var firstNonEmpty = -1
        for (i, line) in lines.enumerated() {
            if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                firstNonEmpty = i
                break
            }
        }
        guard firstNonEmpty >= 0 else { return markdown }

        // その行が `---` のみ (前後空白許容、CR 残りも許容) でなければ対象外
        let openLine = lines[firstNonEmpty]
            .trimmingCharacters(in: CharacterSet(charactersIn: " \t\r"))
        guard openLine == "---" else { return markdown }

        // 終端 `---` または `...` を探す
        var endIndex = -1
        for i in (firstNonEmpty + 1)..<lines.count {
            let trimmed = lines[i]
                .trimmingCharacters(in: CharacterSet(charactersIn: " \t\r"))
            if trimmed == "---" || trimmed == "..." {
                endIndex = i
                break
            }
        }
        guard endIndex > firstNonEmpty else { return markdown }

        // フロントマター以降の行を返す
        let remaining = lines[(endIndex + 1)...]
        return remaining.joined(separator: "\n")
    }
}
