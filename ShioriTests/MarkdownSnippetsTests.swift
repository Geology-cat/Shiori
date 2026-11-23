import XCTest
@testable import Shiori

final class MarkdownSnippetsTests: XCTestCase {
    private let context = MarkdownEditing.FrontMatterContext(title: "メモ", today: "2026-11-24")

    private func applying(_ result: MarkdownEditing.FrontMatterMergeResult, to text: String) throws -> (String, Int) {
        guard case .edit(let edit) = result else { throw XCTSkip("編集がない: \(result)") }
        let out = (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
        return (out, edit.cursor)
    }

    func testフロントマターがなければ先頭に作る() throws {
        let text = "# 見出し\n本文\n"
        let entries = MarkdownEditing.FrontMatterTemplate.basic.entries(context)
        let (out, cursor) = try applying(MarkdownEditing.mergeFrontMatter(entries, into: text), to: text)
        XCTAssertEqual(out, "---\ntitle: メモ\ndate: 2026-11-24\ntags:\n  - \n---\n\n# 見出し\n本文\n")
        // カーソルはタイトルの値の後ろ
        XCTAssertEqual((out as NSString).substring(to: cursor), "---\ntitle: メモ")
    }

    func test空の文書にも作れる() throws {
        let entries = [MarkdownEditing.FrontMatterField.tags.entry(context)]
        let (out, cursor) = try applying(MarkdownEditing.mergeFrontMatter(entries, into: ""), to: "")
        XCTAssertEqual(out, "---\ntags:\n  - \n---\n")
        XCTAssertEqual((out as NSString).substring(to: cursor), "---\ntags:\n  - ")
    }

    func testあるフロントマターには足りない項目だけ足す() throws {
        let text = "---\ntitle: 既存\ntags: [a]\n---\n本文"
        let entries = MarkdownEditing.FrontMatterTemplate.paper.entries(context)
        let (out, cursor) = try applying(MarkdownEditing.mergeFrontMatter(entries, into: text), to: text)
        XCTAssertEqual(out, "---\ntitle: 既存\ntags: [a]\nauthor: \ndate: 2026-11-24\nabstract: \n---\n本文")
        XCTAssertEqual((out as NSString).substring(to: cursor), "---\ntitle: 既存\ntags: [a]\nauthor: ")
    }

    func test全部あれば何もしない() {
        let text = "---\ntags:\n  - x\n...\n本文"
        XCTAssertEqual(MarkdownEditing.mergeFrontMatter([MarkdownEditing.FrontMatterField.tags.entry(context)], into: text), .nothingToAdd)
    }

    func testTOMLには触らない() {
        let text = "+++\ntitle = \"a\"\n+++\n本文"
        XCTAssertEqual(MarkdownEditing.mergeFrontMatter([MarkdownEditing.FrontMatterField.date.entry(context)], into: text), .unsupported)
    }

    func test閉じていないダッシュは本文として扱う() throws {
        let text = "---\n本文だけ"
        let (out, _) = try applying(MarkdownEditing.mergeFrontMatter([MarkdownEditing.FrontMatterField.date.entry(context)], into: text), to: text)
        XCTAssertEqual(out, "---\ndate: 2026-11-24\n---\n\n---\n本文だけ")
    }

    func test水平線で始まる本文をフロントマターと取り違えない() throws {
        let entry = [MarkdownEditing.FrontMatterField.date.entry(context)]
        for text in ["---\n\n本文\n\n---\n続き", "---\n本文の段落\n---\n続き"] {
            let (out, _) = try applying(MarkdownEditing.mergeFrontMatter(entry, into: text), to: text)
            XCTAssertEqual(out, "---\ndate: 2026-11-24\n---\n\n" + text)
        }
    }

    func test空のフロントマターには項目を足す() throws {
        let text = "---\n---\n本文"
        let (out, _) = try applying(MarkdownEditing.mergeFrontMatter([MarkdownEditing.FrontMatterField.date.entry(context)], into: text), to: text)
        XCTAssertEqual(out, "---\ndate: 2026-11-24\n---\n本文")
    }

    func test最上位のキーだけを数える() {
        XCTAssertEqual(MarkdownEditing.topLevelKey("title: a"), "title")
        XCTAssertEqual(MarkdownEditing.topLevelKey("\"my key\": a"), "my key")
        XCTAssertEqual(MarkdownEditing.topLevelKey("tags:"), "tags")
        XCTAssertNil(MarkdownEditing.topLevelKey("  - title: a"))
        XCTAssertNil(MarkdownEditing.topLevelKey("  nested: a"))
        XCTAssertNil(MarkdownEditing.topLevelKey("# title: a"))
        XCTAssertNil(MarkdownEditing.topLevelKey("url:https"))
    }

    func testYAMLの値を必要なときだけ引用符で囲む() {
        XCTAssertEqual(MarkdownEditing.yamlScalar("日記"), "日記")
        XCTAssertEqual(MarkdownEditing.yamlScalar("A: B"), "\"A: B\"")
        XCTAssertEqual(MarkdownEditing.yamlScalar("2026"), "\"2026\"")
        XCTAssertEqual(MarkdownEditing.yamlScalar("yes"), "\"yes\"")
        XCTAssertEqual(MarkdownEditing.yamlScalar("#memo"), "\"#memo\"")
        XCTAssertEqual(MarkdownEditing.yamlScalar("say \"hi\": x"), "\"say \\\"hi\\\": x\"")
    }

    func test脚注は次の番号で文末に定義を作る() {
        let text = "本文[^1]。\n\n[^1]: 一つ目"
        let edits = MarkdownEditing.insertFootnote(in: text, at: 2)
        var out = text as NSString
        for edit in edits { out = out.replacingCharacters(in: edit.range, with: edit.replacement) as NSString }
        XCTAssertEqual(out as String, "本文[^2][^1]。\n\n[^1]: 一つ目\n\n[^2]: ")
        XCTAssertEqual(edits.last?.cursor, out.length)
    }

    func test文末で脚注を入れる() {
        let text = "本文"
        let edits = MarkdownEditing.insertFootnote(in: text, at: 2)
        var out = text as NSString
        for edit in edits { out = out.replacingCharacters(in: edit.range, with: edit.replacement) as NSString }
        XCTAssertEqual(out as String, "本文[^1]\n\n[^1]: ")
        XCTAssertEqual(edits.last?.cursor, out.length)
    }

    func test注記で行を囲む() {
        XCTAssertEqual(MarkdownEditing.callout(kind: "NOTE", body: ""), "> [!NOTE]\n> ")
        XCTAssertEqual(MarkdownEditing.callout(kind: "tip", foldable: true, body: "一行目\n\n三行目"), "> [!tip]-\n> 一行目\n>\n> 三行目")
    }

    func testコードブロックで囲む() {
        let empty = MarkdownEditing.codeBlock(language: "swift", body: "")
        XCTAssertEqual(empty.text, "```swift\n\n```")
        XCTAssertEqual(empty.cursorOffset, 9)
        let wrapped = MarkdownEditing.codeBlock(language: "", body: "let a = 1")
        XCTAssertEqual(wrapped.text, "```\nlet a = 1\n```")
        XCTAssertEqual(wrapped.cursorOffset, (wrapped.text as NSString).length)
    }
}
