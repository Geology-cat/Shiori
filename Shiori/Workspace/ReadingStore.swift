import Foundation

/// ファイルごとの読書位置と表示の調整
struct FileViewState: Codable {
    /// 読んでいた位置（整数部が行、小数部が行の中のどのあたりか）
    var line: Double = 0
    var overrides = ViewOverrides()
    var updatedAt: Date = Date()

    var hasOverrides: Bool { !overrides.isEmpty }
}

/// 読書位置などを JSON に保存する。Vault を作らないのでアプリ側で覚えておく。
final class ReadingStore {
    static let shared = ReadingStore()

    private var entries: [String: FileViewState] = [:]
    private let fileURL: URL
    private var saveWork: DispatchWorkItem?
    private static let maxEntries = 3000

    private init() {
        fileURL = ThemeManager.shared.supportURL.appendingPathComponent("reading-state.json")
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([String: FileViewState].self, from: data) {
            entries = decoded
        }
    }

    func state(for url: URL) -> FileViewState {
        entries[url.path] ?? FileViewState()
    }

    func update(_ url: URL, _ change: (inout FileViewState) -> Void) {
        var value = entries[url.path] ?? FileViewState()
        change(&value)
        value.updatedAt = Date()
        entries[url.path] = value
        scheduleSave()
    }

    /// ファイルの移動・改名に追従する
    func move(from: URL, to: URL) {
        guard let value = entries.removeValue(forKey: from.path) else { return }
        entries[to.path] = value
        scheduleSave()
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    func saveNow() {
        saveWork?.cancel()
        saveWork = nil
        if entries.count > Self.maxEntries {
            // 古いものから捨てる（表示を調整したファイルは残す）
            let removable = entries.filter { !$0.value.hasOverrides }.sorted { $0.value.updatedAt < $1.value.updatedAt }
            for (key, _) in removable.prefix(entries.count - Self.maxEntries) { entries.removeValue(forKey: key) }
        }
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
