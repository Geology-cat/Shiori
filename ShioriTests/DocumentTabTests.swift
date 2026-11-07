import XCTest
@testable import Shiori

/// 保存まわりはデータを失うと取り返しがつかないので、衝突の判定を確かめておく
final class DocumentTabTests: XCTestCase {
    private var directory: URL!
    private var file: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        file = directory.appendingPathComponent("doc.md")
        try Data("元の内容\n".utf8).write(to: file)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func edit(_ tab: DocumentTab, appending text: String) {
        tab.storage.mutableString.append(text)
        tab.textDidChange()
    }

    /// ファイルの更新時刻を確実に進めて、外部からの書き込みを再現する
    private func writeExternally(_ text: String) throws {
        try Data(text.utf8).write(to: file)
        let later = Date().addingTimeInterval(5)
        try FileManager.default.setAttributes([.modificationDate: later], ofItemAtPath: file.path)
    }

    func test編集と保存で未保存フラグが変わる() throws {
        let tab = DocumentTab(mode: .edit)
        try tab.load(file)
        XCTAssertFalse(tab.isDirty)
        edit(tab, appending: "追記\n")
        XCTAssertTrue(tab.isDirty)
        XCTAssertTrue(try tab.save())
        XCTAssertFalse(tab.isDirty)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "元の内容\n追記\n")
    }

    func test元に戻すと未保存でなくなる() throws {
        let tab = DocumentTab(mode: .edit)
        try tab.load(file)
        edit(tab, appending: "x")
        tab.storage.mutableString.deleteCharacters(in: NSRange(location: tab.storage.length - 1, length: 1))
        tab.textDidChange()
        XCTAssertFalse(tab.isDirty)
    }

    func test外部で変更されたファイルを黙って上書きしない() throws {
        let tab = DocumentTab(mode: .edit)
        try tab.load(file)
        edit(tab, appending: "自分の編集\n")
        try writeExternally("他のアプリの内容\n")

        XCTAssertFalse(try tab.save())
        XCTAssertTrue(tab.hasExternalChange)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "他のアプリの内容\n")

        // 明示的に上書きを選んだときだけ書き込む
        XCTAssertTrue(try tab.save(force: true))
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "元の内容\n自分の編集\n")
    }

    func test編集がなければ外部の変更を自動で読み込む() throws {
        let tab = DocumentTab(mode: .read)
        try tab.load(file)
        try writeExternally("更新された内容\n")
        XCTAssertEqual(tab.checkDisk(), .reloaded)
        XCTAssertEqual(tab.text, "更新された内容\n")
        XCTAssertFalse(tab.isDirty)
    }

    func test編集中に外部で変更されたら衝突として扱い編集を残す() throws {
        let tab = DocumentTab(mode: .edit)
        try tab.load(file)
        edit(tab, appending: "自分の編集\n")
        try writeExternally("他のアプリの内容\n")
        XCTAssertEqual(tab.checkDisk(), .conflict)
        XCTAssertTrue(tab.hasExternalChange)
        XCTAssertEqual(tab.text, "元の内容\n自分の編集\n")
    }

    func test削除されたファイルを検知する() throws {
        let tab = DocumentTab(mode: .read)
        try tab.load(file)
        try FileManager.default.removeItem(at: file)
        XCTAssertEqual(tab.checkDisk(), .missing)
        XCTAssertTrue(tab.isMissing)
    }

    func testチェックボックスの切替をソースへ反映する() throws {
        try Data("前書き\n\n- [ ] 未完了\n  - [x] 子\n".utf8).write(to: file)
        let tab = DocumentTab(mode: .read)
        try tab.load(file)
        tab.toggleTask(line: 2, checked: true)
        tab.toggleTask(line: 3, checked: false)
        XCTAssertEqual(tab.text, "前書き\n\n- [x] 未完了\n  - [ ] 子\n")
        XCTAssertTrue(tab.isDirty)
    }

    func test表のある行などタスクでない行は変更しない() throws {
        try Data("普通の [ ] 文章\n".utf8).write(to: file)
        let tab = DocumentTab(mode: .read)
        try tab.load(file)
        tab.toggleTask(line: 0, checked: true)
        XCTAssertEqual(tab.text, "普通の [ ] 文章\n")
    }
}
