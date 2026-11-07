import Foundation

/// テーマごとの既定の詳細設定（環境設定で決める）
struct ViewStyle: Codable, Equatable {
    /// 組方向
    var writing: WritingMode = .horizontal
    /// 文字の大きさ（テーマの基準に対する倍率）
    var fontScale: Double = 1
    /// 行間。0 のときはテーマの値を使う
    var lineHeight: Double = 0
    /// 本文の幅（縦書きでは 1 行の字数, em）。0 のときはテーマの値を使う
    var measure: Double = 0
    var fontChoice: FontChoice = .theme
    var customFontName: String = ""
    var indent = false
    var justify = false
    var headingNumbers = false

    /// CSS の font-family 値。テーマの既定を使うときは nil
    var fontFamilyCSS: String? {
        switch fontChoice {
        case .theme: return nil
        case .mincho: return "\"Hiragino Mincho ProN\", \"YuMincho\", serif"
        case .gothic: return "-apple-system, \"Hiragino Sans\", \"Hiragino Kaku Gothic ProN\", sans-serif"
        case .custom:
            let name = customFontName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            return "\"\(name.replacingOccurrences(of: "\"", with: ""))\", \"Hiragino Sans\", sans-serif"
        }
    }

    init(writing: WritingMode = .horizontal, fontScale: Double = 1, lineHeight: Double = 0, measure: Double = 0,
         fontChoice: FontChoice = .theme, customFontName: String = "", indent: Bool = false, justify: Bool = false,
         headingNumbers: Bool = false) {
        self.writing = writing
        self.fontScale = fontScale
        self.lineHeight = lineHeight
        self.measure = measure
        self.fontChoice = fontChoice
        self.customFontName = customFontName
        self.indent = indent
        self.justify = justify
        self.headingNumbers = headingNumbers
    }

    /// 項目が足りない古い保存データも、足りない項目を初期値にして読む
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let base = ViewStyle()
        writing = try c.decodeIfPresent(WritingMode.self, forKey: .writing) ?? base.writing
        fontScale = try c.decodeIfPresent(Double.self, forKey: .fontScale) ?? base.fontScale
        lineHeight = try c.decodeIfPresent(Double.self, forKey: .lineHeight) ?? base.lineHeight
        measure = try c.decodeIfPresent(Double.self, forKey: .measure) ?? base.measure
        fontChoice = try c.decodeIfPresent(FontChoice.self, forKey: .fontChoice) ?? base.fontChoice
        customFontName = try c.decodeIfPresent(String.self, forKey: .customFontName) ?? base.customFontName
        indent = try c.decodeIfPresent(Bool.self, forKey: .indent) ?? base.indent
        justify = try c.decodeIfPresent(Bool.self, forKey: .justify) ?? base.justify
        headingNumbers = try c.decodeIfPresent(Bool.self, forKey: .headingNumbers) ?? base.headingNumbers
    }

    static func scaledUp(_ value: Double) -> Double { min(3.0, (value * 10 + 1).rounded() / 10) }
    static func scaledDown(_ value: Double) -> Double { max(0.5, (value * 10 - 1).rounded() / 10) }
}

/// ウインドウごとの表示の調整（表示パネルやメニューで変えたもの）。nil の項目は既定に従う。
/// 同じウインドウで開くファイルには引き継ぎ、新しいウインドウや起動時は空（＝既定）から始まる。
struct ViewOverrides: Codable, Equatable {
    var themeID: String?
    var writing: WritingMode?
    var fontScale: Double?
    var lineHeight: Double?
    var measure: Double?
    var fontChoice: FontChoice?
    var customFontName: String?
    var indent: Bool?
    var justify: Bool?
    var headingNumbers: Bool?

    var isEmpty: Bool { self == ViewOverrides() }

    /// 既定のスタイルにこの調整を重ねる
    func applied(to base: ViewStyle) -> ViewStyle {
        var style = base
        if let writing { style.writing = writing }
        if let fontScale { style.fontScale = fontScale }
        if let lineHeight { style.lineHeight = lineHeight }
        if let measure { style.measure = measure }
        if let fontChoice { style.fontChoice = fontChoice }
        if let customFontName { style.customFontName = customFontName }
        if let indent { style.indent = indent }
        if let justify { style.justify = justify }
        if let headingNumbers { style.headingNumbers = headingNumbers }
        return style
    }
}
