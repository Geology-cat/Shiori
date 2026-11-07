import XCTest
@testable import Shiori

final class MarkdownEditingTests: XCTestCase {
    func testリストの継続() throws {
        let bullet = try XCTUnwrap(MarkdownEditing.parseList("  - 項目"))
        XCTAssertEqual(MarkdownEditing.continuation(of: bullet), "  - ")
        XCTAssertFalse(bullet.isEmpty)

        let number = try XCTUnwrap(MarkdownEditing.parseList("9. 項目"))
        XCTAssertEqual(MarkdownEditing.continuation(of: number), "10. ")

        let task = try XCTUnwrap(MarkdownEditing.parseList("- [x] 完了"))
        XCTAssertEqual(MarkdownEditing.continuation(of: task), "- [ ] ")

        let quote = try XCTUnwrap(MarkdownEditing.parseList("> 引用"))
        XCTAssertEqual(MarkdownEditing.continuation(of: quote), "> ")
    }

    func test空の項目を判定する() throws {
        XCTAssertTrue(try XCTUnwrap(MarkdownEditing.parseList("- ")).isEmpty)
        XCTAssertTrue(try XCTUnwrap(MarkdownEditing.parseList("- [ ] ")).isEmpty)
        XCTAssertNil(MarkdownEditing.parseList("普通の文"))
    }

    func test相対パス() {
        let base = URL(fileURLWithPath: "/a/b/c")
        XCTAssertEqual(MarkdownEditing.relativePath(from: base, to: URL(fileURLWithPath: "/a/b/c/assets/x.png")), "assets/x.png")
        XCTAssertEqual(MarkdownEditing.relativePath(from: base, to: URL(fileURLWithPath: "/a/d/x.png")), "../../d/x.png")
    }

    func testリンク先のエスケープ() {
        XCTAssertEqual(MarkdownEditing.linkDestination("a b.png"), "<a b.png>")
        XCTAssertEqual(MarkdownEditing.linkDestination("ab.png"), "ab.png")
    }
}
