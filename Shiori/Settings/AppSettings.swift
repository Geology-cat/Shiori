import AppKit
import Combine

/// 閲覧 / 編集モード
enum DocMode: String, CaseIterable, Identifiable, Codable {
    case read, edit
    var id: String { rawValue }
    var label: String { self == .read ? "閲覧" : "編集" }
}

/// 組方向
enum WritingMode: String, CaseIterable, Identifiable, Codable {
    case horizontal, vertical
    var id: String { rawValue }
    var label: String { self == .horizontal ? "横書き" : "縦書き" }
}

/// ファイラーで別のファイルを選んだときの開き方
enum FilerOpenMode: String, CaseIterable, Identifiable {
    case replace, newTab
    var id: String { rawValue }
    var label: String { self == .replace ? "今のタブで開く（置き換える）" : "新しいタブで開く" }
}

/// Finder や Dock のアイコンから開いたときの開き方
enum ExternalOpenMode: String, CaseIterable, Identifiable {
    case existingWindow, newWindow
    var id: String { rawValue }
    var label: String { self == .existingWindow ? "開いているウインドウのタブで開く" : "新しいウインドウで開く" }
}

/// 外観
enum AppearanceChoice: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "システムに合わせる"
        case .light: return "ライト"
        case .dark: return "ダーク"
        }
    }
}

/// 本文フォントの選択
enum FontChoice: String, CaseIterable, Identifiable, Codable {
    case theme, mincho, gothic, custom
    var id: String { rawValue }
    var label: String {
        switch self {
        case .theme: return "テーマの既定"
        case .mincho: return "明朝"
        case .gothic: return "ゴシック"
        case .custom: return "指定したフォント"
        }
    }
}

/// アプリ全体の設定。UserDefaults に保存する。
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    // 一般
    @Published var defaultOpenMode: DocMode { didSet { defaults.set(defaultOpenMode.rawValue, forKey: Keys.defaultOpenMode) } }
    @Published var appearance: AppearanceChoice { didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance); applyAppearance() } }
    @Published var autosave: Bool { didSet { defaults.set(autosave, forKey: Keys.autosave) } }
    @Published var restoreSession: Bool { didSet { defaults.set(restoreSession, forKey: Keys.restoreSession) } }
    @Published var showHiddenFiles: Bool { didSet { defaults.set(showHiddenFiles, forKey: Keys.showHiddenFiles) } }
    @Published var filerOpenMode: FilerOpenMode { didSet { defaults.set(filerOpenMode.rawValue, forKey: Keys.filerOpenMode) } }
    @Published var externalOpenMode: ExternalOpenMode { didSet { defaults.set(externalOpenMode.rawValue, forKey: Keys.externalOpenMode) } }

    // ビューワー
    @Published var themeID: String { didSet { defaults.set(themeID, forKey: Keys.themeID) } }
    /// テーマごとの既定の詳細設定。キーはテーマの ID
    @Published var themeStyles: [String: ViewStyle] {
        didSet {
            if let data = try? JSONEncoder().encode(themeStyles) { defaults.set(data, forKey: Keys.themeStyles) }
        }
    }
    @Published var breaks: Bool { didSet { defaults.set(breaks, forKey: Keys.breaks) } }
    @Published var showProperties: Bool { didSet { defaults.set(showProperties, forKey: Keys.showProperties) } }
    @Published var clickToPage: Bool { didSet { defaults.set(clickToPage, forKey: Keys.clickToPage) } }
    @Published var useCustomCSS: Bool { didSet { defaults.set(useCustomCSS, forKey: Keys.useCustomCSS) } }

    // エディタ
    @Published var editorFontSize: Double { didSet { defaults.set(editorFontSize, forKey: Keys.editorFontSize) } }
    @Published var editorFontName: String { didSet { defaults.set(editorFontName, forKey: Keys.editorFontName) } }
    @Published var editorLimitWidth: Bool { didSet { defaults.set(editorLimitWidth, forKey: Keys.editorLimitWidth) } }

    private enum Keys {
        static let defaultOpenMode = "defaultOpenMode"
        static let appearance = "appearance"
        static let autosave = "autosave"
        static let restoreSession = "restoreSession"
        static let showHiddenFiles = "showHiddenFiles"
        static let themeID = "themeID"
        static let filerOpenMode = "filerOpenMode"
        static let externalOpenMode = "externalOpenMode"
        static let themeStyles = "themeStyles"
        static let breaks = "breaks"
        static let showProperties = "showProperties"
        static let clickToPage = "clickToPage"
        static let useCustomCSS = "useCustomCSS"
        static let editorFontSize = "editorFontSize"
        static let editorFontName = "editorFontName"
        static let editorLimitWidth = "editorLimitWidth"
    }

    private init() {
        let d = defaults
        d.register(defaults: [
            Keys.autosave: true,
            Keys.restoreSession: true,
            Keys.breaks: true,
            Keys.showProperties: true,
            Keys.editorFontSize: 14.0,
            Keys.editorLimitWidth: true,
        ])
        defaultOpenMode = DocMode(rawValue: d.string(forKey: Keys.defaultOpenMode) ?? "") ?? .read
        appearance = AppearanceChoice(rawValue: d.string(forKey: Keys.appearance) ?? "") ?? .system
        autosave = d.bool(forKey: Keys.autosave)
        restoreSession = d.bool(forKey: Keys.restoreSession)
        showHiddenFiles = d.bool(forKey: Keys.showHiddenFiles)
        themeID = d.string(forKey: Keys.themeID) ?? "default"
        filerOpenMode = FilerOpenMode(rawValue: d.string(forKey: Keys.filerOpenMode) ?? "") ?? .replace
        externalOpenMode = ExternalOpenMode(rawValue: d.string(forKey: Keys.externalOpenMode) ?? "") ?? .existingWindow
        themeStyles = d.data(forKey: Keys.themeStyles).flatMap { try? JSONDecoder().decode([String: ViewStyle].self, from: $0) } ?? [:]
        breaks = d.bool(forKey: Keys.breaks)
        showProperties = d.bool(forKey: Keys.showProperties)
        clickToPage = d.bool(forKey: Keys.clickToPage)
        useCustomCSS = d.bool(forKey: Keys.useCustomCSS)
        editorFontSize = d.double(forKey: Keys.editorFontSize)
        editorFontName = d.string(forKey: Keys.editorFontName) ?? ""
        editorLimitWidth = d.bool(forKey: Keys.editorLimitWidth)
    }

    /// 外観の設定をアプリ全体へ反映する（ビューワーは prefers-color-scheme で追従する）
    func applyAppearance() {
        switch appearance {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    /// テーマの既定の詳細設定
    func style(for themeID: String) -> ViewStyle {
        themeStyles[themeID] ?? ViewStyle()
    }

    func setStyle(_ style: ViewStyle, for themeID: String) {
        if style == ViewStyle() { themeStyles.removeValue(forKey: themeID) } else { themeStyles[themeID] = style }
    }
}
