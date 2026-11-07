import AppKit
import Combine

/// ビューワーのテーマ
struct ViewerTheme: Identifiable, Hashable {
    let id: String
    let name: String
    let summary: String
    /// ビューワーのページから見た CSS の場所
    let href: String
    let isUser: Bool
}

/// 同梱テーマとユーザーの CSS テーマを管理する。
/// ユーザーのテーマは ~/Library/Application Support/Shiori/themes/*.css に置く。
final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    static let builtin: [ViewerTheme] = [
        ViewerTheme(id: "default", name: "標準", summary: "普段のノートや技術文書に", href: "themes/default.css", isUser: false),
        ViewerTheme(id: "scientific", name: "科学文書", summary: "数式・図表が読みやすい論文調", href: "themes/scientific.css", isUser: false),
        ViewerTheme(id: "reading", name: "読書", summary: "紙の色と明朝で長文をじっくり", href: "themes/reading.css", isUser: false),
        ViewerTheme(id: "github", name: "GitHub", summary: "README の確認に", href: "themes/github.css", isUser: false),
    ]

    /// ファイルが変わるたびに増やし、CSS のキャッシュを避ける
    @Published private(set) var userThemes: [ViewerTheme] = []
    @Published private(set) var revision = 0

    let supportURL: URL
    let themesURL: URL
    var customCSSURL: URL { supportURL.appendingPathComponent("custom.css") }

    private var watcher: FSWatcher?

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        supportURL = base.appendingPathComponent("Shiori", isDirectory: true)
        themesURL = supportURL.appendingPathComponent("themes", isDirectory: true)
        try? FileManager.default.createDirectory(at: themesURL, withIntermediateDirectories: true)
        scan()
        // テーマの CSS を編集すると即座にビューワーへ反映する
        let w = FSWatcher { [weak self] _ in self?.scan() }
        w.watch(paths: [supportURL.path])
        watcher = w
    }

    var allThemes: [ViewerTheme] { Self.builtin + userThemes }

    func theme(id: String) -> ViewerTheme {
        allThemes.first { $0.id == id } ?? Self.builtin[0]
    }

    /// custom.css の href（存在しないときは nil）
    var customCSSHref: String? {
        guard FileManager.default.fileExists(atPath: customCSSURL.path) else { return nil }
        return "user-css/custom.css?v=\(revision)"
    }

    private func scan() {
        let files = (try? FileManager.default.contentsOfDirectory(at: themesURL, includingPropertiesForKeys: nil)) ?? []
        let cssFiles = files
            .filter { $0.pathExtension.lowercased() == "css" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        let nextRevision = revision + 1
        userThemes = cssFiles.map { url in
            let encoded = url.lastPathComponent.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? url.lastPathComponent
            return ViewerTheme(
                id: "user:\(url.lastPathComponent)",
                name: url.deletingPathExtension().lastPathComponent,
                summary: "自前の CSS",
                href: "user-themes/\(encoded)?v=\(nextRevision)",
                isUser: true
            )
        }
        revision = nextRevision
    }

    // MARK: - 操作

    /// 選んだ CSS ファイルをテーマフォルダへ取り込み、そのテーマの ID を返す
    @discardableResult
    func importCSS(from source: URL) throws -> String {
        let destination = themesURL.appendingPathComponent(source.lastPathComponent)
        if source.standardizedFileURL != destination.standardizedFileURL {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: source, to: destination)
        }
        scan()
        return "user:\(source.lastPathComponent)"
    }

    /// 変数の説明付きのテーマ雛形を作り、その URL を返す
    func createTemplate() throws -> URL {
        var url = themesURL.appendingPathComponent("my-theme.css")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = themesURL.appendingPathComponent("my-theme-\(n).css")
            n += 1
        }
        try Self.template.write(to: url, atomically: true, encoding: .utf8)
        scan()
        return url
    }

    /// custom.css（どのテーマの上にも重ねる追加 CSS）を用意して URL を返す
    func ensureCustomCSS() throws -> URL {
        if !FileManager.default.fileExists(atPath: customCSSURL.path) {
            let text = """
            /* どのテーマにも重ねて適用する追加 CSS です。保存すると即座に反映されます。 */

            """
            try text.write(to: customCSSURL, atomically: true, encoding: .utf8)
            scan()
        }
        return customCSSURL
    }

    func revealThemesFolder() {
        NSWorkspace.shared.open(themesURL)
    }

    private static let template = """
    /*
      Shiori のカスタムテーマ
      このファイルを保存すると開いている文書へ即座に反映されます。

      縦書きでも崩れないよう、余白は margin-block / padding-inline などの
      論理プロパティで書くのがおすすめです。本文の要素は通常どおり
      h1, p, table, blockquote などのセレクタで指定できます。
    */

    :root {
      /* 色 */
      --bg: #ffffff;              /* 背景 */
      --fg: #24292f;              /* 文字 */
      --muted: #667085;           /* 補助の文字 */
      --faint: #98a2b3;           /* さらに淡い文字 */
      --accent: #4f5bd5;          /* リンクなど */
      --rule: #e4e7ec;            /* 罫線 */
      --surface: #f6f7f9;         /* 表の見出しなどの面 */
      --code-bg: #f4f5f7;         /* コードの背景 */
      --mark-bg: #fff1a8;         /* ==マーカー== の背景 */

      /* 文字 */
      --font-body: "Hiragino Sans", sans-serif;
      --font-heading: var(--font-body);
      --font-mono: ui-monospace, Menlo, monospace;
      --theme-font-size: 16px;    /* 基準の文字サイズ */
      --theme-line-height: 1.8;   /* 行間 */
      --theme-measure: 44em;      /* 本文の幅（縦書きでは 1 行の長さ） */
      --block-gap: 1em;           /* 段落の間隔 */
      --heading-weight: 650;      /* 見出しの太さ */
    }

    /* ダークモード */
    :root[data-appearance="dark"] {
      --bg: #1b1d21;
      --fg: #d8dade;
      --muted: #9aa0a9;
      --faint: #6c727c;
      --accent: #a3acf5;
      --rule: #33363c;
      --surface: #24272c;
      --code-bg: #24272c;
    }

    /* 例: 見出しに下線を引く */
    /* h2 { border-block-end: 1px solid var(--rule); padding-block-end: 0.2em; } */

    """
}
