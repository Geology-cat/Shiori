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
enum FontChoice: String, CaseIterable, Identifiable {
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

    // ビューワー
    @Published var themeID: String { didSet { defaults.set(themeID, forKey: Keys.themeID) } }
    @Published var writing: WritingMode { didSet { defaults.set(writing.rawValue, forKey: Keys.writing) } }
    @Published var fontScale: Double { didSet { defaults.set(fontScale, forKey: Keys.fontScale) } }
    /// 0 のときはテーマの既定値を使う
    @Published var lineHeight: Double { didSet { defaults.set(lineHeight, forKey: Keys.lineHeight) } }
    /// 本文の幅 (em)。0 のときはテーマの既定値を使う
    @Published var measure: Double { didSet { defaults.set(measure, forKey: Keys.measure) } }
    @Published var fontChoice: FontChoice { didSet { defaults.set(fontChoice.rawValue, forKey: Keys.fontChoice) } }
    @Published var customFontName: String { didSet { defaults.set(customFontName, forKey: Keys.customFontName) } }
    @Published var headingNumbers: Bool { didSet { defaults.set(headingNumbers, forKey: Keys.headingNumbers) } }
    @Published var indent: Bool { didSet { defaults.set(indent, forKey: Keys.indent) } }
    @Published var justify: Bool { didSet { defaults.set(justify, forKey: Keys.justify) } }
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
        static let writing = "writing"
        static let fontScale = "fontScale"
        static let lineHeight = "lineHeight"
        static let measure = "measure"
        static let fontChoice = "fontChoice"
        static let customFontName = "customFontName"
        static let headingNumbers = "headingNumbers"
        static let indent = "indent"
        static let justify = "justify"
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
            Keys.fontScale: 1.0,
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
        writing = WritingMode(rawValue: d.string(forKey: Keys.writing) ?? "") ?? .horizontal
        fontScale = d.double(forKey: Keys.fontScale)
        lineHeight = d.double(forKey: Keys.lineHeight)
        measure = d.double(forKey: Keys.measure)
        fontChoice = FontChoice(rawValue: d.string(forKey: Keys.fontChoice) ?? "") ?? .theme
        customFontName = d.string(forKey: Keys.customFontName) ?? ""
        headingNumbers = d.bool(forKey: Keys.headingNumbers)
        indent = d.bool(forKey: Keys.indent)
        justify = d.bool(forKey: Keys.justify)
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

    /// CSS の font-family 値。テーマの既定を使うときは nil
    var fontFamilyCSS: String? {
        switch fontChoice {
        case .theme: return nil
        case .mincho: return "\"Hiragino Mincho ProN\", \"YuMincho\", serif"
        case .gothic: return "-apple-system, \"Hiragino Sans\", \"Hiragino Kaku Gothic ProN\", sans-serif"
        case .custom:
            let name = customFontName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            let safe = name.replacingOccurrences(of: "\"", with: "")
            return "\"\(safe)\", \"Hiragino Sans\", sans-serif"
        }
    }

    func increaseFontScale() { fontScale = min(3.0, (fontScale * 10 + 1).rounded() / 10) }
    func decreaseFontScale() { fontScale = max(0.5, (fontScale * 10 - 1).rounded() / 10) }
}
