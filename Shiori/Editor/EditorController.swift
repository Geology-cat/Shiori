import AppKit
import Combine

/// ソースエディタ本体の NSTextView。入力支援と画像の貼り付け・ドロップを担当する。
final class ShioriTextView: NSTextView {
    weak var controller: EditorController?

    // 長い行が読みにくくならないよう、広い窓では左右に余白を取る
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateInsets(width: newSize.width)
    }

    func updateInsets(width: CGFloat? = nil) {
        let w = width ?? frame.width
        let settings = AppSettings.shared
        let side: CGFloat
        if settings.editorLimitWidth {
            let maxWidth = CGFloat(settings.editorFontSize) * 58
            side = max(28, (w - maxWidth) / 2)
        } else {
            side = 28
        }
        let inset = NSSize(width: side.rounded(), height: 24)
        if textContainerInset != inset { textContainerInset = inset }
    }

    // MARK: - 入力支援

    /// Enter: リストや引用を継続する。空の項目ならリストを終わらせる
    override func insertNewline(_ sender: Any?) {
        let ns = string as NSString
        let selection = selectedRange()
        let lineRange = ns.lineRange(for: NSRange(location: selection.location, length: 0))
        var line = ns.substring(with: lineRange)
        if line.hasSuffix("\n") { line.removeLast() }

        // カーソルが行の途中のときはリスト継続の対象を記号の後ろに限る
        if selection.length == 0, let prefix = MarkdownEditing.parseList(line) {
            if prefix.isEmpty {
                // 記号だけの行で Enter → 記号を消す
                replace(range: NSRange(location: lineRange.location, length: (line as NSString).length), with: "")
                return
            }
            super.insertNewline(sender)
            insertText(MarkdownEditing.continuation(of: prefix), replacementRange: selectedRange())
            return
        }
        super.insertNewline(sender)
    }

    /// Tab: リストの項目なら字下げする
    override func insertTab(_ sender: Any?) {
        if adjustListIndent(increase: true) { return }
        insertText("    ", replacementRange: selectedRange())
    }

    override func insertBacktab(_ sender: Any?) {
        _ = adjustListIndent(increase: false)
    }

    private func adjustListIndent(increase: Bool) -> Bool {
        let ns = string as NSString
        let selection = selectedRange()
        let lineRange = ns.lineRange(for: selection)
        let block = ns.substring(with: lineRange)
        let trailingNewline = block.hasSuffix("\n")
        var lines = block.components(separatedBy: "\n")
        if trailingNewline { lines.removeLast() }
        guard selection.length > 0 || lines.contains(where: { MarkdownEditing.parseList($0) != nil }) else { return false }

        let unit = "    "
        let changed = lines.map { line -> String in
            if increase { return line.isEmpty ? line : unit + line }
            if line.hasPrefix(unit) { return String(line.dropFirst(4)) }
            if line.hasPrefix("\t") { return String(line.dropFirst()) }
            return String(line.drop(while: { $0 == " " }))
        }
        let result = changed.joined(separator: "\n") + (trailingNewline ? "\n" : "")
        replace(range: lineRange, with: result)
        if selection.length > 0 {
            setSelectedRange(NSRange(location: lineRange.location, length: (result as NSString).length))
        } else {
            let delta = ((changed.first ?? "") as NSString).length - ((lines.first ?? "") as NSString).length
            setSelectedRange(NSRange(location: max(lineRange.location, selection.location + delta), length: 0))
        }
        return true
    }

    func replace(range: NSRange, with text: String) {
        guard shouldChangeText(in: range, replacementString: text) else { return }
        textStorage?.replaceCharacters(in: range, with: text)
        didChangeText()
    }

    // MARK: - 画像の貼り付け・ドロップ

    override func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        // テキストがあるなら通常の貼り付けを優先する（Office などは画像も同時に載せるため）
        if pasteboard.string(forType: .string) == nil,
           let controller, controller.pasteImage(from: pasteboard) {
            return
        }
        super.paste(sender)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL], !urls.isEmpty,
           let controller {
            let point = convert(sender.draggingLocation, from: nil)
            let index = characterIndexForInsertion(at: point)
            setSelectedRange(NSRange(location: index, length: 0))
            controller.insertLinks(to: urls)
            return true
        }
        return super.performDragOperation(sender)
    }
}

/// ソースエディタの制御。タブごとの NSTextStorage を差し替えて 1 つのビューを使い回す。
final class EditorController: NSObject, NSTextViewDelegate {
    let scrollView: NSScrollView
    let textView: ShioriTextView
    private let layoutManager = NSLayoutManager()

    private(set) var currentTab: DocumentTab?
    private var highlightWork: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()

    /// カーソル位置が変わったときの通知（ステータスバー用）
    var onSelectionChange: ((Int, Int) -> Void)?

    override init() {
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)
        // 表示前（幅 0）に文書を差し込むと、非連続レイアウトでは改行が崩れたまま残る
        layoutManager.allowsNonContiguousLayout = false
        NSTextStorage().addLayoutManager(layoutManager)

        textView = ShioriTextView(frame: .zero, textContainer: container)
        scrollView = NSScrollView()
        super.init()

        textView.controller = self
        textView.delegate = self
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.registerForDraggedTypes([.fileURL])

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true

        // フォント設定の変更を反映する
        AppSettings.shared.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.applyStyle() }
            .store(in: &cancellables)
        applyStyle()
    }

    private func applyStyle() {
        let style = EditorStyle.current
        textView.font = style.font
        textView.defaultParagraphStyle = style.paragraphStyle
        textView.typingAttributes = currentTab?.highlighter.baseAttributes(style) ?? [:]
        textView.updateInsets()
        currentTab?.highlighter.update(style: style)
    }

    // MARK: - タブの切替

    func attach(_ tab: DocumentTab) {
        if currentTab !== tab {
            captureState()
            currentTab = tab
            layoutManager.replaceTextStorage(tab.storage)
        }
        tab.highlighter.update()
        textView.typingAttributes = tab.highlighter.baseAttributes(.current)
        let length = tab.storage.length
        let location = min(tab.editorSelection.location, length)
        let selection = NSRange(location: location, length: min(tab.editorSelection.length, length - location))
        textView.setSelectedRange(selection)
        if let scroll = tab.editorScroll {
            setScroll(scroll)
        }
    }

    /// 現在のカーソルとスクロール位置をタブへ書き戻す
    func captureState() {
        guard let tab = currentTab else { return }
        tab.editorSelection = textView.selectedRange()
        tab.editorScroll = scrollView.contentView.bounds.origin.y
    }

    /// タブが閉じられたときに参照を外す
    func detach(_ tab: DocumentTab) {
        guard currentTab === tab else { return }
        currentTab = nil
        layoutManager.replaceTextStorage(NSTextStorage())
    }

    private func setScroll(_ y: CGFloat) {
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: y))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    // MARK: - 行番号との変換

    /// 画面の先頭に見えている行（0 始まり）
    func topVisibleLine() -> Int {
        guard let container = textView.textContainer else { return 0 }
        let origin = scrollView.contentView.bounds.origin
        let point = NSPoint(x: 0, y: origin.y - textView.textContainerOrigin.y + 2)
        let glyph = layoutManager.glyphIndex(for: point, in: container)
        let character = layoutManager.characterIndexForGlyph(at: glyph)
        return lineNumber(at: character)
    }

    func lineNumber(at character: Int) -> Int {
        let ns = textView.string as NSString
        var line = 0
        var location = 0
        let target = min(character, ns.length)
        while location < target {
            let range = ns.lineRange(for: NSRange(location: location, length: 0))
            let next = NSMaxRange(range)
            if next > target || next == location { break }
            location = next
            line += 1
        }
        return line
    }

    private func characterIndex(ofLine line: Int) -> Int {
        let ns = textView.string as NSString
        var location = 0
        var current = 0
        while current < line, location < ns.length {
            location = NSMaxRange(ns.lineRange(for: NSRange(location: location, length: 0)))
            current += 1
        }
        return min(location, ns.length)
    }

    /// 閲覧から切り替えたとき: カーソルが見えていなければ、見ている行へ移す（入力して飛ばないように）
    func moveCursorIntoView(line: Int) {
        guard let container = textView.textContainer else { return }
        let selection = textView.selectedRange()
        let glyphs = layoutManager.glyphRange(forCharacterRange: NSRange(location: selection.location, length: 0), actualCharacterRange: nil)
        let rect = layoutManager.boundingRect(forGlyphRange: glyphs, in: container)
            .offsetBy(dx: textView.textContainerOrigin.x, dy: textView.textContainerOrigin.y)
        if !scrollView.contentView.bounds.intersects(rect) {
            textView.setSelectedRange(NSRange(location: characterIndex(ofLine: line), length: 0))
        }
    }

    /// 指定行が画面の先頭に来るようにスクロールする
    func scrollToLine(_ line: Int, moveCursor: Bool = false) {
        guard let container = textView.textContainer else { return }
        let index = characterIndex(ofLine: line)
        layoutManager.ensureLayout(for: container)
        if moveCursor { textView.setSelectedRange(NSRange(location: index, length: 0)) }
        let glyph = layoutManager.glyphIndexForCharacter(at: index)
        let rect = layoutManager.lineFragmentRect(forGlyphAt: min(glyph, max(0, layoutManager.numberOfGlyphs - 1)), effectiveRange: nil)
        let y = max(0, rect.minY + textView.textContainerOrigin.y - 12)
        setScroll(line == 0 ? 0 : y)
    }

    // MARK: - NSTextViewDelegate

    func undoManager(for view: NSTextView) -> UndoManager? {
        currentTab?.undoManager
    }

    func textDidChange(_ notification: Notification) {
        guard let tab = currentTab else { return }
        tab.textDidChange()
        scheduleHighlight()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard let onSelectionChange else { return }
        let ns = textView.string as NSString
        let location = min(textView.selectedRange().location, ns.length)
        let lineRange = ns.lineRange(for: NSRange(location: location, length: 0))
        onSelectionChange(lineNumber(at: location) + 1, location - lineRange.location + 1)
    }

    private func scheduleHighlight() {
        highlightWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let tab = self.currentTab else { return }
            // 変換中に属性を変えると IME の表示が乱れるので確定まで待つ
            if self.textView.hasMarkedText() {
                self.scheduleHighlight()
                return
            }
            let selection = self.textView.selectedRange()
            tab.highlighter.update()
            self.textView.typingAttributes = tab.highlighter.baseAttributes(.current)
            if self.textView.selectedRange() != selection { self.textView.setSelectedRange(selection) }
        }
        highlightWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
    }

    // MARK: - 書式コマンド

    /// 選択範囲を prefix / suffix で囲む（既に囲まれていれば外す）
    func toggleWrap(prefix: String, suffix: String, placeholder: String = "") {
        focus()
        let ns = textView.string as NSString
        let selection = textView.selectedRange()
        let p = (prefix as NSString).length
        let s = (suffix as NSString).length

        if selection.location >= p, NSMaxRange(selection) + s <= ns.length,
           ns.substring(with: NSRange(location: selection.location - p, length: p)) == prefix,
           ns.substring(with: NSRange(location: NSMaxRange(selection), length: s)) == suffix {
            let outer = NSRange(location: selection.location - p, length: selection.length + p + s)
            textView.replace(range: outer, with: ns.substring(with: selection))
            textView.setSelectedRange(NSRange(location: outer.location, length: selection.length))
            return
        }
        let inner = selection.length > 0 ? ns.substring(with: selection) : placeholder
        textView.replace(range: selection, with: prefix + inner + suffix)
        textView.setSelectedRange(NSRange(location: selection.location + p, length: (inner as NSString).length))
    }

    /// 行頭に記号を付ける（同じ記号があれば外す）
    func toggleLinePrefix(_ prefix: String) {
        focus()
        let ns = textView.string as NSString
        let selection = textView.selectedRange()
        let lineRange = ns.lineRange(for: selection)
        var body = ns.substring(with: lineRange)
        let trailing = body.hasSuffix("\n")
        if trailing { body.removeLast() }
        let lines = body.components(separatedBy: "\n")
        let allPrefixed = lines.allSatisfy { $0.hasPrefix(prefix) }
        let changed = lines.map { allPrefixed ? String($0.dropFirst(prefix.count)) : prefix + $0 }
        let result = changed.joined(separator: "\n") + (trailing ? "\n" : "")
        textView.replace(range: lineRange, with: result)
        textView.setSelectedRange(NSRange(location: lineRange.location, length: (result as NSString).length - (trailing ? 1 : 0)))
    }

    /// 見出しレベルを設定する（0 で見出しを外す）
    func setHeading(level: Int) {
        focus()
        let ns = textView.string as NSString
        let lineRange = ns.lineRange(for: textView.selectedRange())
        var line = ns.substring(with: lineRange)
        let trailing = line.hasSuffix("\n")
        if trailing { line.removeLast() }
        let stripped = line.replacingOccurrences(of: #"^\s{0,3}#{1,6}\s+"#, with: "", options: .regularExpression)
        let result = (level > 0 ? String(repeating: "#", count: level) + " " : "") + stripped + (trailing ? "\n" : "")
        textView.replace(range: lineRange, with: result)
        textView.setSelectedRange(NSRange(location: lineRange.location + (result as NSString).length - (trailing ? 1 : 0), length: 0))
    }

    /// カーソルの位置に文字列のブロックを前後を空けて挿入する
    func insertBlock(_ block: String, cursorOffset: Int? = nil) {
        focus()
        let ns = textView.string as NSString
        let selection = textView.selectedRange()
        var insertion = block
        var leading = 0
        if selection.location > 0, ns.substring(with: NSRange(location: selection.location - 1, length: 1)) != "\n" {
            insertion = "\n" + insertion
            leading = 1
        }
        if NSMaxRange(selection) < ns.length, ns.substring(with: NSRange(location: NSMaxRange(selection), length: 1)) != "\n" {
            insertion += "\n"
        }
        textView.replace(range: selection, with: insertion)
        let position = selection.location + leading + (cursorOffset ?? (block as NSString).length)
        textView.setSelectedRange(NSRange(location: position, length: 0))
        textView.scrollRangeToVisible(NSRange(location: position, length: 0))
    }

    func focus() {
        textView.window?.makeFirstResponder(textView)
    }

    // MARK: - 画像

    /// 貼り付けられた画像を文書のそばに保存してリンクを挿入する
    func pasteImage(from pasteboard: NSPasteboard) -> Bool {
        guard let image = NSImage(pasteboard: pasteboard),
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return false }
        guard let documentURL = currentTab?.url else {
            let alert = NSAlert()
            alert.messageText = "画像を貼り付ける前に文書を保存してください"
            alert.informativeText = "画像は文書と同じ場所の assets フォルダに保存します。"
            alert.runModal()
            return true
        }
        let folder = documentURL.deletingLastPathComponent().appendingPathComponent("assets", isDirectory: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        var file = folder.appendingPathComponent("pasted-\(formatter.string(from: Date())).png")
        var n = 2
        while FileManager.default.fileExists(atPath: file.path) {
            file = folder.appendingPathComponent("pasted-\(formatter.string(from: Date()))-\(n).png")
            n += 1
        }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try png.write(to: file, options: .atomic)
        } catch {
            NSAlert(error: error).runModal()
            return true
        }
        insertLinks(to: [file])
        return true
    }

    /// ファイルへのリンクを挿入する（画像は ![]()、それ以外は []()）
    func insertLinks(to urls: [URL]) {
        let base = currentTab?.url?.deletingLastPathComponent()
        let text = urls.map { url -> String in
            let path = base.map { MarkdownEditing.relativePath(from: $0, to: url) } ?? url.path
            let destination = MarkdownEditing.linkDestination(path)
            if FileKinds.isImage(url) {
                return "![\(url.deletingPathExtension().lastPathComponent)](\(destination))"
            }
            return "[\(url.deletingPathExtension().lastPathComponent)](\(destination))"
        }.joined(separator: "\n")
        textView.window?.makeFirstResponder(textView)
        textView.insertText(text, replacementRange: textView.selectedRange())
    }
}
