import Foundation
import Combine

/// ファイラーの 1 行
struct FileRow: Identifiable, Equatable {
    let url: URL
    let isDirectory: Bool
    let depth: Int
    let isExpanded: Bool
    var id: String { url.path }
    var name: String { url.lastPathComponent }
}

/// ファイラーのツリー。開いているフォルダだけを読み、行の配列へ平坦化して持つ。
/// 表示するのはフォルダと Markdown、画像のみ。
final class FileTreeModel: ObservableObject {
    @Published private(set) var rows: [FileRow] = []
    @Published private(set) var root: URL?

    private var expanded: Set<String> = []
    private static let skipNames: Set<String> = ["node_modules", "__pycache__", "DerivedData"]

    func setRoot(_ url: URL?) {
        root = url
        expanded = []
        if let url {
            let saved = UserDefaults.standard.stringArray(forKey: Self.expandedKey(url)) ?? []
            expanded = Set(saved)
        }
        reload()
    }

    private static func expandedKey(_ url: URL) -> String { "expanded:\(url.path)" }

    private func saveExpanded() {
        guard let root else { return }
        UserDefaults.standard.set(Array(expanded), forKey: Self.expandedKey(root))
    }

    func reload() {
        guard let root else {
            rows = []
            return
        }
        var result: [FileRow] = []
        append(contentsOf: root, depth: 0, into: &result)
        if result != rows { rows = result }
    }

    private func append(contentsOf directory: URL, depth: Int, into result: inout [FileRow]) {
        for (url, isDirectory) in Self.children(of: directory) {
            let isOpen = isDirectory && expanded.contains(url.path)
            result.append(FileRow(url: url, isDirectory: isDirectory, depth: depth, isExpanded: isOpen))
            if isOpen { append(contentsOf: url, depth: depth + 1, into: &result) }
        }
    }

    /// 並べ替えに使う 1 項目ぶんの情報
    struct Entry {
        let url: URL
        let isDirectory: Bool
        let modified: Date?
        let created: Date?
    }

    /// フォルダの中身をフィルタして、環境設定の並び順（既定はフォルダが先、名前の自然順）で並べる
    static func children(of directory: URL) -> [(URL, Bool)] {
        let settings = AppSettings.shared
        var options: FileManager.DirectoryEnumerationOptions = []
        if !settings.showHiddenFiles { options.insert(.skipsHiddenFiles) }
        // 日付は一覧を取るたびに読み直す（resourceValues はキャッシュするので古い値を掴まないように）
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .contentModificationDateKey, .creationDateKey]
        let items = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys,
            options: options
        )) ?? []

        var list: [Entry] = []
        for url in items {
            let values = try? url.resourceValues(forKeys: Set(keys))
            let isDir = values?.isDirectory ?? false
            if isDir {
                if values?.isPackage == true { continue } // .app などのパッケージは出さない
                if skipNames.contains(url.lastPathComponent) { continue }
            } else if !FileKinds.isShownInFiler(url) {
                continue
            }
            list.append(Entry(url: url, isDirectory: isDir, modified: values?.contentModificationDate, created: values?.creationDate))
        }
        return sorted(list, by: settings.filerSortKey, ascending: settings.filerSortAscending, foldersFirst: settings.filerFoldersFirst)
            .map { ($0.url, $0.isDirectory) }
    }

    /// 並べ替え。同じ値どうしは名前の自然順にする
    static func sorted(_ entries: [Entry], by key: FilerSortKey, ascending: Bool, foldersFirst: Bool) -> [Entry] {
        func byName(_ a: Entry, _ b: Entry) -> ComparisonResult {
            a.url.lastPathComponent.localizedStandardCompare(b.url.lastPathComponent)
        }
        func compare(_ a: Entry, _ b: Entry) -> ComparisonResult {
            switch key {
            case .name:
                return byName(a, b)
            case .modified, .created:
                let da = (key == .modified ? a.modified : a.created) ?? .distantPast
                let db = (key == .modified ? b.modified : b.created) ?? .distantPast
                if da != db { return da < db ? .orderedAscending : .orderedDescending }
                return byName(a, b)
            case .kind:
                // フォルダは拡張子がないので先頭にまとまる
                let ka = a.isDirectory ? "" : a.url.pathExtension.lowercased()
                let kb = b.isDirectory ? "" : b.url.pathExtension.lowercased()
                if ka != kb { return ka.localizedStandardCompare(kb) }
                return byName(a, b)
            }
        }
        return entries.sorted { a, b in
            if foldersFirst, a.isDirectory != b.isDirectory { return a.isDirectory }
            let result = compare(a, b)
            if result == .orderedSame { return false }
            return (result == .orderedAscending) == ascending
        }
    }

    func toggle(_ row: FileRow) {
        guard row.isDirectory else { return }
        if expanded.contains(row.url.path) { expanded.remove(row.url.path) } else { expanded.insert(row.url.path) }
        saveExpanded()
        reload()
    }

    func expand(_ url: URL) {
        guard !expanded.contains(url.path) else { return }
        expanded.insert(url.path)
        saveExpanded()
        reload()
    }

    /// 指定ファイルが見えるよう親フォルダを開く
    func reveal(_ url: URL) {
        guard let root = root?.standardizedFileURL else { return }
        let target = url.standardizedFileURL
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard target.path.hasPrefix(rootPath) else { return }
        var changed = false
        var dir = target.deletingLastPathComponent()
        while dir.path.count > root.path.count {
            if expanded.insert(dir.path).inserted { changed = true }
            dir = dir.deletingLastPathComponent()
        }
        if changed {
            saveExpanded()
            reload()
        }
    }
}

/// フォルダ以下のファイル名の索引。クイックオープン、ファイラーの絞り込み、Wiki リンクの解決に使う。
final class FileIndex {
    private(set) var files: [URL] = []
    private var root: URL?
    private var generation = 0
    private static let limit = 50_000

    func setRoot(_ url: URL?) {
        root = url
        rebuild()
    }

    /// バックグラウンドで作り直す
    func rebuild() {
        generation += 1
        let current = generation
        guard let root else {
            files = []
            return
        }
        let showHidden = AppSettings.shared.showHiddenFiles
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let found = Self.scan(root, showHidden: showHidden)
            DispatchQueue.main.async {
                guard let self, self.generation == current else { return }
                self.files = found
            }
        }
    }

    private static func scan(_ root: URL, showHidden: Bool) -> [URL] {
        var options: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
        if !showHidden { options.insert(.skipsHiddenFiles) }
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isDirectoryKey], options: options
        ) else { return [] }
        var result: [URL] = []
        for case let url as URL in enumerator {
            if result.count >= limit { break }
            if ["node_modules", "__pycache__", "DerivedData"].contains(url.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }
            if FileKinds.isShownInFiler(url) { result.append(url) }
        }
        return result.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    /// あいまい検索（入力した文字を順番に含むものを、近い順に返す）
    func search(_ query: String, limit: Int = 60) -> [URL] {
        let q = query.lowercased()
        guard !q.isEmpty else { return Array(files.prefix(limit)) }
        var scored: [(URL, Int)] = []
        for url in files {
            let name = url.lastPathComponent.lowercased()
            let relative = root.map { MarkdownEditing.relativePath(from: $0, to: url) }?.lowercased() ?? url.path.lowercased()
            if let score = Self.score(query: q, target: name) {
                scored.append((url, score))
            } else if let score = Self.score(query: q, target: relative) {
                scored.append((url, score + 1000))
            }
        }
        scored.sort { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0.path.count < $1.0.path.count }
        return scored.prefix(limit).map(\.0)
    }

    /// 小さいほど良い一致。一致しなければ nil
    static func score(query: String, target: String) -> Int? {
        if target == query { return 0 }
        if target.hasPrefix(query) { return 1 }
        if target.contains(query) { return 2 }
        var score = 3
        var index = target.startIndex
        for ch in query {
            guard let found = target[index...].firstIndex(of: ch) else { return nil }
            score += target.distance(from: index, to: found)
            index = target.index(after: found)
        }
        return score
    }

    /// [[名前]] を実際のファイルへ解決する
    func resolveWikilink(_ rawTarget: String, from document: URL?) -> URL? {
        var name = rawTarget
        if let hash = name.firstIndex(of: "#") { name = String(name[..<hash]) }
        name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return document }

        let hasExtension = FileKinds.isOpenable(URL(fileURLWithPath: name))
        let candidates = hasExtension ? [name] : FileKinds.markdownExtensions.sorted().map { "\(name).\($0)" }

        // 1. 開いている文書と同じフォルダからの相対パス、2. ルートからの相対パス
        let bases = [document?.deletingLastPathComponent(), root].compactMap { $0 }
        for base in bases {
            for candidate in candidates {
                let url = base.appendingPathComponent(candidate).standardizedFileURL
                if FileManager.default.fileExists(atPath: url.path) { return url }
            }
        }
        // 3. 索引からファイル名で探す
        let lowered = candidates.map { ($0 as NSString).lastPathComponent.lowercased() }
        return files.first { lowered.contains($0.lastPathComponent.lowercased()) }
    }
}
