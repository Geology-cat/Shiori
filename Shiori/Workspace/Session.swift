import AppKit

/// 前回の状態（ウィンドウごとのルートフォルダと開いていたタブ）
struct SessionWindow: Codable {
    var root: String?
    var tabs: [String]
    var active: String?
    var sidebarVisible: Bool
    var sidebarWidth: Double
}

enum SessionStore {
    private static let key = "session.windows"

    static func save(_ windows: [SessionWindow]) {
        guard let data = try? JSONEncoder().encode(windows) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func load() -> [SessionWindow] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let windows = try? JSONDecoder().decode([SessionWindow].self, from: data) else { return [] }
        return windows
    }
}

/// 最近開いたフォルダとファイル
enum RecentItems {
    private static let foldersKey = "recent.folders"
    private static let limit = 12

    static var folders: [URL] {
        (UserDefaults.standard.stringArray(forKey: foldersKey) ?? [])
            .filter { FileManager.default.fileExists(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    static func addFolder(_ url: URL) {
        var list = UserDefaults.standard.stringArray(forKey: foldersKey) ?? []
        list.removeAll { $0 == url.path }
        list.insert(url.path, at: 0)
        UserDefaults.standard.set(Array(list.prefix(limit)), forKey: foldersKey)
    }

    static var files: [URL] {
        NSDocumentController.shared.recentDocumentURLs.filter { !isDirectory($0) }
    }

    static func addFile(_ url: URL) {
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
    }

    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
    }
}
