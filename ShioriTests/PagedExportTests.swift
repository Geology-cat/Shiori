import PDFKit
import XCTest
@testable import Shiori

/// ページめくりのテーマで PDF を書き出すと、画面と同じ割り付け（段組み）で A4 に並ぶ
final class PagedExportTests: XCTestCase {
    private func settings(writing: String, columns: Int) -> [String: Any] {
        [
            "theme": "book",
            "themeHref": "themes/reading.css",
            "writing": writing,
            "fontScale": 1.0,
            "lineHeight": 0.0,
            "measure": 0.0,
            "headingNumbers": false,
            "indent": false,
            "justify": false,
            "breaks": true,
            "showProperties": true,
            "clickToPage": false,
            "paged": true,
            "columns": columns,
        ]
    }

    private var longMarkdown: String {
        var lines = ["# 長文", ""]
        for i in 1...40 {
            lines.append("【段落\(i)】" + String(repeating: "吾輩は猫である。名前はまだ無い。どこで生れたかとんと見当がつかぬ。", count: 6))
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private func export(writing: String, columns: Int) throws -> PDFDocument {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ShioriPagedExport-\(writing)-\(columns).pdf")
        try? FileManager.default.removeItem(at: url)
        let done = expectation(description: "書き出し")
        var failure: Error?
        Exporter.run(.pdf(url), markdown: longMarkdown, path: nil, settings: settings(writing: writing, columns: columns),
                     resolver: { _, _ in nil }) { error in
            failure = error
            done.fulfill()
        }
        wait(for: [done], timeout: 60)
        if let failure { throw failure }
        return try XCTUnwrap(PDFDocument(url: url))
    }

    func test縦書き2段組みをA4に割り付ける() throws {
        let document = try export(writing: "vertical", columns: 2)
        XCTAssertGreaterThan(document.pageCount, 1)
        let bounds = try XCTUnwrap(document.page(at: 0)).bounds(for: .mediaBox)
        XCTAssertEqual(bounds.width, 595.28, accuracy: 1)
        XCTAssertEqual(bounds.height, 841.89, accuracy: 1)
        // 本文の文字が PDF に入っている（取り込みがベクターのまま）。縦書きは 1 字ごとに改行して取り出されるので詰めて比べる
        let text = (document.string ?? "").filter { !$0.isWhitespace }
        XCTAssertTrue(text.contains("段落1"))
        XCTAssertTrue(text.contains("段落40"))
    }

    func test横書き1段組みも書き出せる() throws {
        let one = try export(writing: "horizontal", columns: 1)
        let two = try export(writing: "horizontal", columns: 2)
        XCTAssertGreaterThan(one.pageCount, 1)
        XCTAssertGreaterThan(two.pageCount, 0)
        XCTAssertTrue(one.string?.contains("段落40") ?? false)
    }
}
