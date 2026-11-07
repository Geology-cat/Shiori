import XCTest
@testable import Shiori

final class TextFileTests: XCTestCase {
    func testUTF8() throws {
        let loaded = try TextFile.decode(Data("# 見出し\n本文".utf8))
        XCTAssertEqual(loaded.text, "# 見出し\n本文")
        XCTAssertEqual(loaded.encoding, .utf8)
        XCTAssertFalse(loaded.hasBOM)
        XCTAssertEqual(loaded.lineEnding, .lf)
    }

    func testBOMとCRLFを保持して書き戻せる() throws {
        let original = Data([0xEF, 0xBB, 0xBF]) + Data("一行目\r\n二行目\r\n".utf8)
        let loaded = try TextFile.decode(original)
        XCTAssertEqual(loaded.text, "一行目\n二行目\n")
        XCTAssertTrue(loaded.hasBOM)
        XCTAssertEqual(loaded.lineEnding, .crlf)
        let encoded = try TextFile.encode(loaded.text, encoding: loaded.encoding, hasBOM: loaded.hasBOM, lineEnding: loaded.lineEnding)
        XCTAssertEqual(encoded, original)
    }

    func testShiftJISを判定して同じバイト列へ戻せる() throws {
        let text = "日本語のメモ\n①丸数字も含む\n"
        let data = try XCTUnwrap(text.data(using: TextFile.cp932))
        let loaded = try TextFile.decode(data)
        XCTAssertEqual(loaded.text, text)
        XCTAssertEqual(TextFile.encodingName(loaded.encoding), "Shift_JIS")
        let encoded = try TextFile.encode(loaded.text, encoding: loaded.encoding, hasBOM: false, lineEnding: loaded.lineEnding)
        XCTAssertEqual(encoded, data)
    }

    func testEUCJP() throws {
        let text = "漢字とかなの文章です。\n"
        let data = try XCTUnwrap(text.data(using: .japaneseEUC))
        let loaded = try TextFile.decode(data)
        XCTAssertEqual(loaded.text, text)
        XCTAssertEqual(loaded.encoding, .japaneseEUC)
    }

    func testISO2022JP() throws {
        let text = "こんにちは世界\n"
        let data = try XCTUnwrap(text.data(using: .iso2022JP))
        let loaded = try TextFile.decode(data)
        XCTAssertEqual(loaded.text, text)
        XCTAssertEqual(loaded.encoding, .iso2022JP)
    }

    func test日本語を含まないASCIIはUTF8() throws {
        XCTAssertEqual(try TextFile.decode(Data("plain ascii\n".utf8)).encoding, .utf8)
    }

    func testUTF16BOM() throws {
        let data = Data([0xFF, 0xFE]) + (try XCTUnwrap("abc\n".data(using: .utf16LittleEndian)))
        let loaded = try TextFile.decode(data)
        XCTAssertEqual(loaded.text, "abc\n")
        XCTAssertEqual(loaded.encoding, .utf16LittleEndian)
    }

    func testバイナリは開かない() {
        XCTAssertThrowsError(try TextFile.decode(Data([0x89, 0x50, 0x4E, 0x47, 0x00, 0x01])))
    }

    func testShiftJISで表せない文字はエラー() {
        XCTAssertThrowsError(try TextFile.encode("😀", encoding: TextFile.cp932, hasBOM: false, lineEnding: .lf))
    }

    func test書き込みは既存のパーミッションとシンボリックリンクを保つ() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let real = dir.appendingPathComponent("real.md")
        try Data("old".utf8).write(to: real)
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: real.path)
        let link = dir.appendingPathComponent("link.md")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        try TextFile.write(Data("new".utf8), to: link)

        XCTAssertEqual(try String(contentsOf: real, encoding: .utf8), "new")
        let attributes = try FileManager.default.attributesOfItem(atPath: link.path)
        XCTAssertEqual(attributes[.type] as? FileAttributeType, .typeSymbolicLink)
        let realAttributes = try FileManager.default.attributesOfItem(atPath: real.path)
        XCTAssertEqual((realAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o640)
    }
}
