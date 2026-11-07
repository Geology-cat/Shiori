import XCTest
@testable import Shiori

final class OutlineParserTests: XCTestCase {
    func testATXとSetext() {
        let items = OutlineParser.parse("# 一\n\n## 二 ##\n\n三\n===\n\n四\n---\n")
        XCTAssertEqual(items.map(\.title), ["一", "二", "三", "四"])
        XCTAssertEqual(items.map(\.level), [1, 2, 1, 2])
        XCTAssertEqual(items.map(\.line), [0, 2, 4, 7])
    }

    func testコードとフロントマターの中は無視() {
        let text = """
        ---
        # これはYAMLのコメント
        title: x
        ---
        # 本物

        ```bash
        # コメント
        ```

        ~~~
        ## これも違う
        ~~~
        ## 二つ目
        """
        let items = OutlineParser.parse(text)
        XCTAssertEqual(items.map(\.title), ["本物", "二つ目"])
        XCTAssertEqual(items.first?.line, 4)
    }

    func testインライン記法を取り除く() {
        XCTAssertEqual(OutlineParser.cleanTitle("**太字** と `code` と [リンク](a.md) {#id}"), "太字 と code と リンク")
        XCTAssertEqual(OutlineParser.cleanTitle("[[ノート|表示名]] ==印=="), "表示名 印")
    }

    func testハッシュの後に空白がないものは見出しでない() {
        XCTAssertTrue(OutlineParser.parse("#タグ\n#1").isEmpty)
    }
}
