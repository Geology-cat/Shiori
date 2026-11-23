import XCTest
@testable import Shiori

/// ファイラーの並び順
final class FileTreeSortTests: XCTestCase {
    private func entry(_ name: String, dir: Bool = false, modified: TimeInterval = 0, created: TimeInterval = 0) -> FileTreeModel.Entry {
        FileTreeModel.Entry(
            url: URL(fileURLWithPath: "/tmp/\(name)"),
            isDirectory: dir,
            modified: Date(timeIntervalSince1970: modified),
            created: Date(timeIntervalSince1970: created)
        )
    }

    private func names(_ entries: [FileTreeModel.Entry]) -> [String] {
        entries.map(\.url.lastPathComponent)
    }

    func test名前は自然順でフォルダが先() {
        let list = [entry("b10.md"), entry("b2.md"), entry("z", dir: true), entry("a.md")]
        let sorted = FileTreeModel.sorted(list, by: .name, ascending: true, foldersFirst: true)
        XCTAssertEqual(names(sorted), ["z", "a.md", "b2.md", "b10.md"])
    }

    func test降順とフォルダを混ぜる() {
        let list = [entry("a.md"), entry("m", dir: true), entry("z.md")]
        let sorted = FileTreeModel.sorted(list, by: .name, ascending: false, foldersFirst: false)
        XCTAssertEqual(names(sorted), ["z.md", "m", "a.md"])
    }

    func test更新日の新しい順() {
        let list = [entry("old.md", modified: 10), entry("new.md", modified: 30), entry("mid.md", modified: 20)]
        let sorted = FileTreeModel.sorted(list, by: .modified, ascending: false, foldersFirst: true)
        XCTAssertEqual(names(sorted), ["new.md", "mid.md", "old.md"])
    }

    func test作成日が同じなら名前順() {
        let list = [entry("b.md", created: 5), entry("a.md", created: 5), entry("c.md", created: 1)]
        let sorted = FileTreeModel.sorted(list, by: .created, ascending: true, foldersFirst: true)
        XCTAssertEqual(names(sorted), ["c.md", "a.md", "b.md"])
    }

    func test種類は拡張子でまとめる() {
        let list = [entry("b.png"), entry("a.md"), entry("c.md"), entry("a.jpg")]
        let sorted = FileTreeModel.sorted(list, by: .kind, ascending: true, foldersFirst: true)
        XCTAssertEqual(names(sorted), ["a.jpg", "a.md", "c.md", "b.png"])
    }
}
