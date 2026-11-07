import XCTest
@testable import Shiori

/// 表示設定は「テーマの既定（環境設定）」に「ファイルごとの調整」を重ねて決まる
final class ViewStyleTests: XCTestCase {
    func test調整がなければ既定のまま() {
        let base = ViewStyle(fontScale: 1.2, lineHeight: 1.9, indent: true)
        XCTAssertTrue(ViewOverrides().isEmpty)
        XCTAssertEqual(ViewOverrides().applied(to: base), base)
    }

    func test調整した項目だけが既定を上書きする() {
        let base = ViewStyle(fontScale: 1.2, lineHeight: 1.9, fontChoice: .mincho, indent: true)
        var overrides = ViewOverrides()
        overrides.fontScale = 1.5
        overrides.indent = false
        let style = overrides.applied(to: base)
        XCTAssertEqual(style.fontScale, 1.5)
        XCTAssertEqual(style.indent, false)
        XCTAssertEqual(style.lineHeight, 1.9)
        XCTAssertEqual(style.fontChoice, .mincho)
        XCTAssertFalse(overrides.isEmpty)
    }

    func test組方向もテーマの既定と調整で決まる() {
        let vertical = ViewStyle(writing: .vertical)
        XCTAssertEqual(ViewOverrides().applied(to: vertical).writing, .vertical)
        var overrides = ViewOverrides()
        overrides.writing = .horizontal
        XCTAssertEqual(overrides.applied(to: vertical).writing, .horizontal)
    }

    func test組方向がない古い保存データも読める() throws {
        let old = #"{"fontScale":1.3,"lineHeight":0,"measure":0,"fontChoice":"mincho","customFontName":"","indent":true,"justify":false,"headingNumbers":false}"#
        let style = try JSONDecoder().decode(ViewStyle.self, from: Data(old.utf8))
        XCTAssertEqual(style.writing, .horizontal)
        XCTAssertEqual(style.fontScale, 1.3)
        XCTAssertEqual(style.fontChoice, .mincho)
        XCTAssertTrue(style.indent)
    }

    func test読書位置を保存して読み戻せる() throws {
        let data = try JSONEncoder().encode(FileViewState(line: 12.5))
        XCTAssertEqual(try JSONDecoder().decode(FileViewState.self, from: data).line, 12.5)
        // 以前の形式（表示の調整を含む）も読める
        let old = #"{"line":3.5,"updatedAt":815738221,"overrides":{"writing":"vertical"}}"#
        XCTAssertEqual(try JSONDecoder().decode(FileViewState.self, from: Data(old.utf8)).line, 3.5)
    }

    func test文字の倍率は範囲内に収まる() {
        XCTAssertEqual(ViewStyle.scaledUp(3.0), 3.0)
        XCTAssertEqual(ViewStyle.scaledDown(0.5), 0.5)
        XCTAssertEqual(ViewStyle.scaledUp(1.0), 1.1, accuracy: 0.0001)
    }
}
