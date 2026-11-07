import AppKit
import Combine

/// タブ 1 つぶんの文書。テキストの正本は NSTextStorage が持つ。
final class DocumentTab: ObservableObject, Identifiable {
    enum Kind { case markdown, image }

    let id = UUID()

    @Published private(set) var url: URL?
    @Published private(set) var kind: Kind = .markdown
    @Published var mode: DocMode = .read
    @Published private(set) var isDirty = false
    /// 開いたあとにディスク上で変更された（未保存の編集があるので自動で読み込めない）
    @Published var hasExternalChange = false
    /// ディスク上から消えた
    @Published var isMissing = false
    @Published private(set) var encoding: String.Encoding = .utf8
    @Published private(set) var lineEnding: LineEnding = .lf
    /// 画像タブの大きさ
    @Published var imageSize: CGSize?

    let storage = NSTextStorage()
    let undoManager = UndoManager()
    lazy var highlighter = MarkdownHighlighter(storage: storage)

    private var hasBOM = false
    private var savedText = ""
    private var diskDate: Date?

    /// テキストが変わるたびに増える（ビューワーの再描画判定に使う）
    private(set) var version = 0

    // 閲覧・編集の位置
    var viewerLine = 0
    var editorSelection = NSRange(location: 0, length: 0)
    var editorScroll: CGFloat?
    var pendingFragment: String?

    // 戻る・進む
    var backStack: [URL] = []
    var forwardStack: [URL] = []

    /// 編集されたときの通知先（ワークスペースが自動保存を仕掛ける）
    var onEdited: (() -> Void)?

    var text: String { storage.string }

    var title: String { url?.lastPathComponent ?? "名称未設定" }

    init(url: URL? = nil, mode: DocMode) {
        self.mode = mode
        if let url { self.url = url }
    }

    // MARK: - 読み込み

    /// ファイルを読み込んでこのタブの内容を置き換える
    func load(_ newURL: URL) throws {
        if FileKinds.isImage(newURL) {
            kind = .image
            mode = .read
            url = newURL
            imageSize = nil
            replaceStorage(with: "")
            diskDate = TextFile.modificationDate(of: newURL)
        } else {
            let loaded = try TextFile.read(newURL)
            kind = .markdown
            url = newURL
            apply(loaded)
        }
        undoManager.removeAllActions()
        viewerLine = ReadingStore.shared.state(for: newURL).line
        editorSelection = NSRange(location: 0, length: 0)
        editorScroll = nil
        isDirty = false
        hasExternalChange = false
        isMissing = false
    }

    private func apply(_ loaded: LoadedText) {
        encoding = loaded.encoding
        hasBOM = loaded.hasBOM
        lineEnding = loaded.lineEnding
        savedText = loaded.text
        replaceStorage(with: loaded.text)
        if let url { diskDate = TextFile.modificationDate(of: url) }
    }

    private func replaceStorage(with text: String) {
        storage.beginEditing()
        storage.replaceCharacters(in: NSRange(location: 0, length: storage.length), with: text)
        storage.endEditing()
        highlighter.invalidate()
        version += 1
    }

    /// 新規ドキュメントとして中身を入れる
    func setUntitledText(_ text: String) {
        replaceStorage(with: text)
        savedText = text
        isDirty = false
    }

    // MARK: - 編集

    /// エディタやタスク切替でテキストが変わったときに呼ぶ
    func textDidChange() {
        version += 1
        let dirty = url == nil ? !storage.string.isEmpty : storage.string != savedText
        if dirty != isDirty { isDirty = dirty }
        onEdited?()
    }

    /// 閲覧モードのチェックボックスをソースへ反映する
    func toggleTask(line: Int, checked: Bool) {
        let ns = storage.string as NSString
        var current = 0
        var range = NSRange(location: 0, length: 0)
        var found = false
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byLines, .substringNotRequired]) { _, lineRange, _, stop in
            if current == line {
                range = lineRange
                found = true
                stop.pointee = true
            }
            current += 1
        }
        guard found else { return }
        let lineText = ns.substring(with: range)
        guard let regex = try? NSRegularExpression(pattern: #"^(\s*(?:[-*+]|\d+[.)])\s+(?:>\s*)?)\[[ xX/\-]\]"#),
              let match = regex.firstMatch(in: lineText, range: NSRange(location: 0, length: (lineText as NSString).length)) else { return }
        let prefix = (lineText as NSString).substring(with: match.range(at: 1))
        let replacement = "\(prefix)[\(checked ? "x" : " ")]"
        let target = NSRange(location: range.location + match.range.location, length: match.range.length)
        storage.replaceCharacters(in: target, with: replacement)
        textDidChange()
    }

    // MARK: - 保存

    /// 保存する。ディスクが外部で変更されていて、上書きしてよいと言われていない場合は失敗扱いで false を返す。
    @discardableResult
    func save(force: Bool = false) throws -> Bool {
        guard let url, kind == .markdown else { return false }
        if !force, let date = TextFile.modificationDate(of: url), let known = diskDate, date > known {
            // 開いたあとに他のアプリが書き換えた。黙って上書きしない
            if (try? TextFile.read(url))?.text != savedText {
                hasExternalChange = true
                return false
            }
        }
        let text = storage.string
        let data = try TextFile.encode(text, encoding: encoding, hasBOM: hasBOM, lineEnding: lineEnding)
        try TextFile.write(data, to: url)
        savedText = text
        diskDate = TextFile.modificationDate(of: url)
        isDirty = false
        hasExternalChange = false
        isMissing = false
        return true
    }

    /// 別名で保存する
    func save(as newURL: URL) throws {
        let data = try TextFile.encode(storage.string, encoding: encoding, hasBOM: hasBOM, lineEnding: lineEnding)
        try TextFile.write(data, to: newURL)
        url = newURL
        savedText = storage.string
        diskDate = TextFile.modificationDate(of: newURL)
        isDirty = false
        hasExternalChange = false
        isMissing = false
    }

    /// 保存時の文字コードを UTF-8 に切り替える（元の文字コードで表せない文字が入ったとき用）
    func convertToUTF8() {
        encoding = .utf8
        hasBOM = false
    }

    // MARK: - 外部変更

    enum DiskCheck { case unchanged, reloaded, conflict, missing }

    /// ディスクの状態を確認する。編集がなければ自動で読み込み直す。
    func checkDisk() -> DiskCheck {
        guard let url else { return .unchanged }
        guard FileManager.default.fileExists(atPath: url.path) else {
            isMissing = true
            return .missing
        }
        if isMissing { isMissing = false }
        guard let date = TextFile.modificationDate(of: url), date != diskDate else { return .unchanged }

        if kind == .image {
            diskDate = date
            version += 1
            return .reloaded
        }
        guard let loaded = try? TextFile.read(url) else { return .unchanged }
        if loaded.text == savedText {
            diskDate = date
            return .unchanged
        }
        if isDirty {
            hasExternalChange = true
            return .conflict
        }
        apply(loaded)
        undoManager.removeAllActions()
        hasExternalChange = false
        return .reloaded
    }

    /// ディスクの内容で編集を破棄する
    func reloadFromDisk() throws {
        guard let url else { return }
        let loaded = try TextFile.read(url)
        apply(loaded)
        undoManager.removeAllActions()
        isDirty = false
        hasExternalChange = false
    }

    /// ファイルの移動・改名をタブへ反映する
    func relocate(to newURL: URL) {
        url = newURL
        diskDate = TextFile.modificationDate(of: newURL)
    }

    /// ファイルをゴミ箱に入れたあと、確認なしで閉じられるようにする
    func setUntrackedClean() {
        isDirty = false
    }

    // MARK: - 統計

    /// 文字数（空白を除く）
    var characterCount: Int {
        storage.string.unicodeScalars.reduce(0) { $0 + (CharacterSet.whitespacesAndNewlines.contains($1) ? 0 : 1) }
    }

    /// 読了の目安（分）。和文は 600 字/分、欧文は 220 語/分で見積もる
    var readingMinutes: Int {
        let text = storage.string
        var cjk = 0
        var words = 0
        var inWord = false
        for scalar in text.unicodeScalars {
            let v = scalar.value
            if (0x3040...0x30FF).contains(v) || (0x3400...0x9FFF).contains(v) || (0xF900...0xFAFF).contains(v) {
                cjk += 1
                inWord = false
            } else if CharacterSet.alphanumerics.contains(scalar) {
                if !inWord { words += 1 }
                inWord = true
            } else {
                inWord = false
            }
        }
        let minutes = Double(cjk) / 600 + Double(words) / 220
        return max(1, Int(minutes.rounded(.up)))
    }
}
