import Foundation

/// 改行コード
enum LineEnding: String {
    case lf = "LF", crlf = "CRLF", cr = "CR"

    var sequence: String {
        switch self {
        case .lf: return "\n"
        case .crlf: return "\r\n"
        case .cr: return "\r"
        }
    }
}

enum TextFileError: LocalizedError {
    case notText
    case unknownEncoding
    case cannotEncode(String)

    var errorDescription: String? {
        switch self {
        case .notText: return "テキストファイルではないようです。"
        case .unknownEncoding: return "文字コードを判定できませんでした。"
        case .cannotEncode(let name): return "\(name) で保存できない文字が含まれています。"
        }
    }
}

/// 読み込んだテキストと、保存時に元の形へ戻すための情報
struct LoadedText: Equatable {
    /// 改行は LF に正規化済み
    var text: String
    var encoding: String.Encoding
    var hasBOM: Bool
    var lineEnding: LineEnding
}

/// テキストファイルの読み書き。文字コードと改行コードを保持し、Finder にある任意の md を壊さない。
enum TextFile {
    /// Windows の Shift_JIS（CP932）
    static let cp932 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.dosJapanese.rawValue)))

    static func read(_ url: URL) throws -> LoadedText {
        let data = try Data(contentsOf: url)
        return try decode(data)
    }

    static func decode(_ data: Data) throws -> LoadedText {
        let (text, encoding, bom) = try decodeText(data)
        let ending = detectLineEnding(text)
        let normalized = ending == .lf ? text : normalizeLineEndings(text)
        return LoadedText(text: normalized, encoding: encoding, hasBOM: bom, lineEnding: ending)
    }

    private static func decodeText(_ data: Data) throws -> (String, String.Encoding, Bool) {
        // BOM 付きを先に判定する
        if data.starts(with: [0xEF, 0xBB, 0xBF]) {
            if let s = String(data: data.dropFirst(3), encoding: .utf8) { return (s, .utf8, true) }
        }
        if data.starts(with: [0xFF, 0xFE]) {
            if let s = String(data: data.dropFirst(2), encoding: .utf16LittleEndian) { return (s, .utf16LittleEndian, true) }
        }
        if data.starts(with: [0xFE, 0xFF]) {
            if let s = String(data: data.dropFirst(2), encoding: .utf16BigEndian) { return (s, .utf16BigEndian, true) }
        }
        // NUL を含むならバイナリとみなす
        if data.prefix(8192).contains(0) { throw TextFileError.notText }

        // ISO-2022-JP は 7 ビットなので UTF-8 としても読めてしまう。エスケープ列で先に見分ける
        if data.contains(0x1B), hasISO2022Escape(data), let s = String(data: data, encoding: .iso2022JP) {
            return (s, .iso2022JP, false)
        }
        if let s = String(data: data, encoding: .utf8) { return (s, .utf8, false) }

        // Shift_JIS と EUC-JP は互いの文字列としても読めることが多いので、日本語らしいほうを選ぶ
        let candidates = [cp932, String.Encoding.japaneseEUC].compactMap { encoding in
            String(data: data, encoding: encoding).map { (text: $0, encoding: encoding) }
        }
        if let best = candidates.max(by: { japaneseScore($0.text) < japaneseScore($1.text) }) {
            return (best.text, best.encoding, false)
        }
        throw TextFileError.unknownEncoding
    }

    private static func hasISO2022Escape(_ data: Data) -> Bool {
        let bytes = [UInt8](data.prefix(65536))
        for i in 0..<max(0, bytes.count - 2) where bytes[i] == 0x1B {
            if bytes[i + 1] == 0x24, bytes[i + 2] == 0x42 || bytes[i + 2] == 0x40 { return true }
        }
        return false
    }

    /// かなや常用の漢字が多いほど高く、半角カナや記号の連続が多いほど低くなる
    private static func japaneseScore(_ text: String) -> Int {
        var score = 0
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x3041...0x3096, 0x30A1...0x30FA, 0x3001, 0x3002, 0x30FC: score += 3
            case 0x4E00...0x9FFF: score += 1
            case 0xFF61...0xFF9F: score -= 3 // 半角カナは誤判定の典型
            case 0xE000...0xF8FF, 0xFFFD: score -= 5
            default: break
            }
        }
        return score
    }

    /// 最初に現れた改行を、そのファイルの改行コードとして扱う
    static func detectLineEnding(_ text: String) -> LineEnding {
        for scalar in text.unicodeScalars.lazy {
            if scalar == "\n" { return .lf }
            if scalar == "\r" {
                return text.contains("\r\n") ? .crlf : .cr
            }
        }
        return .lf
    }

    static func normalizeLineEndings(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }

    static func encode(_ text: String, encoding: String.Encoding, hasBOM: Bool, lineEnding: LineEnding) throws -> Data {
        let restored = lineEnding == .lf ? text : text.replacingOccurrences(of: "\n", with: lineEnding.sequence)
        guard var data = restored.data(using: encoding, allowLossyConversion: false) else {
            throw TextFileError.cannotEncode(encodingName(encoding))
        }
        if hasBOM {
            switch encoding {
            case .utf8: data.insert(contentsOf: [0xEF, 0xBB, 0xBF], at: 0)
            case .utf16LittleEndian: data.insert(contentsOf: [0xFF, 0xFE], at: 0)
            case .utf16BigEndian: data.insert(contentsOf: [0xFE, 0xFF], at: 0)
            default: break
            }
        }
        return data
    }

    /// 書き込み途中で壊れないよう atomic に保存する。
    /// シンボリックリンクは実体へ書き込み、パーミッションは元のものを保つ。
    static func write(_ data: Data, to url: URL) throws {
        let target = url.resolvingSymlinksInPath()
        let permissions = (try? FileManager.default.attributesOfItem(atPath: target.path))?[.posixPermissions]
        try data.write(to: target, options: .atomic)
        if let permissions {
            try? FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: target.path)
        }
    }

    static func modificationDate(of url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    static func encodingName(_ encoding: String.Encoding) -> String {
        switch encoding {
        case .utf8: return "UTF-8"
        case .utf16LittleEndian: return "UTF-16 LE"
        case .utf16BigEndian: return "UTF-16 BE"
        case .japaneseEUC: return "EUC-JP"
        case .iso2022JP: return "ISO-2022-JP"
        case cp932, .shiftJIS: return "Shift_JIS"
        default: return String.localizedName(of: encoding)
        }
    }
}

/// ファイルの種類
enum FileKinds {
    static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd", "mdx", "qmd", "rmd"]
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "svg", "webp", "heic", "heif", "tif", "tiff", "bmp", "avif", "ico"]
    static let textExtensions: Set<String> = ["txt", "text"]

    static func isMarkdown(_ url: URL) -> Bool { markdownExtensions.contains(url.pathExtension.lowercased()) }
    static func isImage(_ url: URL) -> Bool { imageExtensions.contains(url.pathExtension.lowercased()) }
    /// ファイラーに表示するファイル
    static func isShownInFiler(_ url: URL) -> Bool { isMarkdown(url) || isImage(url) }
    /// アプリ内のタブで開けるファイル
    static func isOpenable(_ url: URL) -> Bool { isShownInFiler(url) || textExtensions.contains(url.pathExtension.lowercased()) }
}
