import AppKit
import Combine
import SwiftUI

/// スクロールに合わせて頻繁に変わる値。再描画を最小限にするため分けて持つ。
final class ReadingStatus: ObservableObject {
    @Published var topLine = 0
    @Published var progress = 0.0
    @Published var cursorLine = 1
    @Published var cursorColumn = 1
}

/// 検索バーの状態
final class FindState: ObservableObject {
    @Published var isVisible = false
    @Published var query = ""
    @Published var count = 0
    @Published var index = -1
    @Published var focusRequest = 0
}

enum SidebarPanel: String, CaseIterable, Identifiable {
    case files, outline
    var id: String { rawValue }
}

/// ウィンドウ 1 枚ぶんの状態（ルートフォルダとタブ）
final class WorkspaceModel: ObservableObject {
    @Published private(set) var tabs: [DocumentTab] = []
    @Published private(set) var activeTabID: UUID?
    @Published private(set) var rootURL: URL?

    @Published var sidebarVisible = true
    @Published var sidebarPanel: SidebarPanel = .files
    @Published var sidebarWidth: CGFloat = 250
    @Published var focusMode = false
    @Published var quickOpenVisible = false
    @Published var filterText = ""
    /// アクティブなタブの目次
    @Published private(set) var outline: [OutlineItem] = []

    let tree = FileTreeModel()
    let index = FileIndex()
    let status = ReadingStatus()
    let find = FindState()
    let viewer = ViewerController()
    let editor = EditorController()

    weak var windowController: MainWindowController?

    private var watcher: FSWatcher?
    private var autosaveWork: DispatchWorkItem?
    private var outlineWork: DispatchWorkItem?
    private var fsWork: DispatchWorkItem?
    private var pendingPaths = Set<String>()
    private var cancellables = Set<AnyCancellable>()
    private var appliedSettings: [String: AnyHashable] = [:]

    var activeTab: DocumentTab? { tabs.first { $0.id == activeTabID } }

    init() {
        viewer.delegate = self
        watcher = FSWatcher { [weak self] paths in self?.handleFileEvents(paths) }

        editor.onSelectionChange = { [weak self] line, column in
            self?.status.cursorLine = line
            self?.status.cursorColumn = column
        }

        // 設定が変わったらビューワーへ反映する（ページの再読み込みはしない）
        Publishers.Merge(
            AppSettings.shared.objectWillChange.map { _ in () },
            ThemeManager.shared.objectWillChange.map { _ in () }
        )
        .debounce(for: .milliseconds(30), scheduler: RunLoop.main)
        .sink { [weak self] in self?.settingsDidChange() }
        .store(in: &cancellables)

        pushViewerSettings()
    }

    // MARK: - ルートフォルダ

    func setRoot(_ url: URL?) {
        guard url?.standardizedFileURL != rootURL?.standardizedFileURL else { return }
        rootURL = url?.standardizedFileURL
        tree.setRoot(rootURL)
        index.setRoot(rootURL)
        filterText = ""
        updateWatcher()
        if let url { RecentItems.addFolder(url) }
        persistSession()
    }

    func goToParentFolder() {
        guard let rootURL else { return }
        setRoot(rootURL.deletingLastPathComponent())
    }

    private func updateWatcher() {
        var paths = tabs.compactMap { $0.url?.deletingLastPathComponent().path }
        if let rootURL { paths.append(rootURL.path) }
        watcher?.watch(paths: paths)
    }

    // MARK: - 開く

    /// フォルダならルートにし、ファイルならタブで開く
    func open(_ url: URL, newTab: Bool = false, fragment: String? = nil, recordHistory: Bool = true) {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else {
            showError("ファイルが見つかりません", detail: url.path)
            return
        }
        if isDir.boolValue {
            setRoot(url)
            sidebarVisible = true
            sidebarPanel = .files
            return
        }
        guard FileKinds.isOpenable(url) else {
            NSWorkspace.shared.open(url)
            return
        }
        let target = url.standardizedFileURL

        // すでに開いているならそのタブへ移動する
        if let existing = tabs.first(where: { $0.url?.standardizedFileURL == target }) {
            existing.pendingFragment = fragment
            if existing.id == activeTabID {
                presentActive()
            } else {
                activate(existing)
            }
            return
        }

        if rootURL == nil { setRoot(target.deletingLastPathComponent()) }

        // 今のタブを置き換えられるか（編集中で保存できないものは残す）
        let current = activeTab
        let canReplace = !newTab && current != nil && flush(current!)
        do {
            if canReplace, let tab = current {
                captureCurrentPositions()
                let previous = tab.url
                try tab.load(target)
                tab.mode = tab.kind == .image ? .read : AppSettings.shared.defaultOpenMode
                if recordHistory, let previous {
                    tab.backStack.append(previous)
                    tab.forwardStack.removeAll()
                }
                tab.pendingFragment = fragment
                didLoad(tab)
            } else {
                let tab = DocumentTab(mode: AppSettings.shared.defaultOpenMode)
                try tab.load(target)
                if tab.kind == .image { tab.mode = .read }
                tab.pendingFragment = fragment
                add(tab)
            }
            tree.reveal(target)
            RecentItems.addFile(target)
            updateWatcher()
            persistSession()
        } catch {
            showError("「\(target.lastPathComponent)」を開けませんでした", detail: error.localizedDescription)
        }
    }

    private func didLoad(_ tab: DocumentTab) {
        presentActive()
    }

    /// ファイラーやクイックオープンから開く。開き方は環境設定に従い、alternate（⌘ を押しながら）なら逆にする
    func openFromFiler(_ url: URL, alternate: Bool = false) {
        let newTab = (AppSettings.shared.filerOpenMode == .newTab) != alternate
        open(url, newTab: newTab)
    }

    /// 新しい空のタブを作る
    func newUntitledTab() {
        add(DocumentTab(mode: .edit))
    }

    private func add(_ tab: DocumentTab) {
        tab.onEdited = { [weak self, weak tab] in
            guard let self, let tab else { return }
            self.documentEdited(tab)
        }
        captureCurrentPositions()
        if let current = activeTab { _ = flush(current) }
        tabs.append(tab)
        activeTabID = tab.id
        presentActive()
    }

    // MARK: - タブ

    func activate(_ tab: DocumentTab) {
        guard tab.id != activeTabID else { return }
        captureCurrentPositions()
        if let current = activeTab { _ = flush(current) }
        activeTabID = tab.id
        presentActive()
        persistSession()
    }

    func activateTab(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        activate(tabs[index])
    }

    func activateAdjacentTab(_ offset: Int) {
        guard let current = tabs.firstIndex(where: { $0.id == activeTabID }), !tabs.isEmpty else { return }
        activate(tabs[(current + offset + tabs.count) % tabs.count])
    }

    func moveTab(from source: Int, to destination: Int) {
        guard tabs.indices.contains(source), destination >= 0, destination <= tabs.count else { return }
        let tab = tabs.remove(at: source)
        tabs.insert(tab, at: destination > source ? destination - 1 : destination)
    }

    /// タブを閉じる。未保存なら確認する。閉じられなかったら false
    @discardableResult
    func close(_ tab: DocumentTab) -> Bool {
        guard confirmClose(tab) else { return false }
        if let url = tab.url, tab.id == activeTabID {
            captureCurrentPositions()
            ReadingStore.shared.update(url) { $0.line = tab.viewerLine }
        }
        editor.detach(tab)
        let wasActive = tab.id == activeTabID
        let position = tabs.firstIndex { $0.id == tab.id } ?? 0
        tabs.removeAll { $0.id == tab.id }
        if wasActive {
            activeTabID = tabs.isEmpty ? nil : tabs[min(position, tabs.count - 1)].id
            presentActive()
        }
        updateWatcher()
        persistSession()
        return true
    }

    func closeActiveTab() {
        if let tab = activeTab {
            close(tab)
        } else {
            windowController?.window?.performClose(nil)
        }
    }

    /// すべて閉じてよいか確認する（ウィンドウを閉じるとき・終了するとき）
    func prepareToCloseAll() -> Bool {
        captureCurrentPositions()
        for tab in tabs where tab.isDirty {
            if !confirmClose(tab) { return false }
        }
        for tab in tabs {
            if let url = tab.url { ReadingStore.shared.update(url) { $0.line = tab.viewerLine } }
        }
        ReadingStore.shared.saveNow()
        return true
    }

    private func confirmClose(_ tab: DocumentTab) -> Bool {
        guard tab.isDirty else { return true }
        // 自動保存が有効で保存先があるなら、まず保存を試みる
        if AppSettings.shared.autosave, tab.url != nil, !tab.hasExternalChange, flush(tab) { return true }

        let alert = NSAlert()
        alert.messageText = "「\(tab.title)」の変更を保存しますか？"
        alert.informativeText = tab.hasExternalChange
            ? "このファイルは他のアプリでも変更されています。保存すると相手の変更を上書きします。"
            : "保存しないと変更は失われます。"
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "キャンセル")
        alert.addButton(withTitle: "保存しない")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return save(tab, force: true)
        case .alertThirdButtonReturn:
            return true
        default:
            return false
        }
    }

    // MARK: - 戻る・進む

    func goBack() {
        guard let tab = activeTab, let previous = tab.backStack.popLast() else { return }
        if let current = tab.url { tab.forwardStack.append(current) }
        open(previous, recordHistory: false)
    }

    func goForward() {
        guard let tab = activeTab, let next = tab.forwardStack.popLast() else { return }
        if let current = tab.url { tab.backStack.append(current) }
        open(next, recordHistory: false)
    }

    // MARK: - 閲覧 / 編集の切替

    private func captureCurrentPositions() {
        guard let tab = activeTab else { return }
        if tab.mode == .read {
            // 閲覧中の位置はスクロールのたびに viewerDidScroll で更新されている
        } else {
            editor.captureState()
            tab.viewerLine = editor.topVisiblePosition()
        }
    }

    func toggleMode() {
        guard let tab = activeTab else { return }
        setMode(tab.mode == .read ? .edit : .read)
    }

    func setMode(_ mode: DocMode) {
        guard let tab = activeTab, tab.kind == .markdown, tab.mode != mode else { return }
        // 閲覧と編集で同じ箇所を見続けられるよう、ソース上の位置（行と行内の割合）を受け渡す
        captureCurrentPositions()
        let position = tab.viewerLine
        if mode == .read { _ = flush(tab) }
        tab.mode = mode
        presentActive()
        if mode == .edit {
            editor.scrollToPosition(position)
            editor.moveCursorIntoView(position: position)
        }
    }

    /// アクティブなタブを画面へ出す
    private func presentActive() {
        guard let tab = activeTab else {
            viewer.clear()
            outline = []
            updateWindowState()
            return
        }
        if find.isVisible {
            find.isVisible = false
            viewer.clearFind()
        }
        refreshOutline(tab)
        pushViewerSettings()
        status.topLine = Int(tab.viewerLine)
        status.progress = 0
        switch tab.mode {
        case .read:
            viewer.show(tab)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.windowController?.window?.makeFirstResponder(self.viewer.webView)
            }
        case .edit:
            editor.attach(tab)
            DispatchQueue.main.async { [weak self] in self?.editor.focus() }
        }
        updateWindowState()
    }

    private func updateWindowState() {
        guard let window = windowController?.window else { return }
        let tab = activeTab
        window.title = tab?.title ?? rootURL?.lastPathComponent ?? "Shiori"
        window.representedURL = tab?.url
        window.isDocumentEdited = tab?.isDirty ?? false
    }

    // MARK: - 編集と保存

    private func documentEdited(_ tab: DocumentTab) {
        updateWindowState()
        scheduleOutlineRefresh(tab)
        autosaveWork?.cancel()
        guard AppSettings.shared.autosave, tab.url != nil else { return }
        let work = DispatchWorkItem { [weak self, weak tab] in
            guard let self, let tab else { return }
            _ = self.flush(tab)
        }
        autosaveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }

    /// 自動保存が有効なら保存する。未保存のまま残るなら false
    @discardableResult
    private func flush(_ tab: DocumentTab) -> Bool {
        guard tab.isDirty else { return true }
        guard AppSettings.shared.autosave, tab.url != nil else { return false }
        do {
            let saved = try tab.save()
            updateWindowState()
            return saved
        } catch {
            showError("「\(tab.title)」を保存できませんでした", detail: error.localizedDescription)
            return false
        }
    }

    func saveActive() {
        guard let tab = activeTab else { return }
        if tab.url == nil {
            saveActiveAs()
            return
        }
        _ = save(tab, force: tab.hasExternalChange ? confirmOverwrite(tab) : false)
    }

    private func confirmOverwrite(_ tab: DocumentTab) -> Bool {
        let alert = NSAlert()
        alert.messageText = "他のアプリの変更を上書きしますか？"
        alert.informativeText = "「\(tab.title)」は開いたあとに他のアプリで変更されています。"
        alert.addButton(withTitle: "上書き")
        alert.addButton(withTitle: "キャンセル")
        return alert.runModal() == .alertFirstButtonReturn
    }

    @discardableResult
    private func save(_ tab: DocumentTab, force: Bool) -> Bool {
        do {
            let saved = try tab.save(force: force)
            updateWindowState()
            return saved
        } catch TextFileError.cannotEncode(let name) {
            // 元の文字コードで表せない文字が入ったら UTF-8 へ変えるか聞く
            let alert = NSAlert()
            alert.messageText = "\(name) で保存できない文字が含まれています"
            alert.informativeText = "UTF-8 に変更して保存しますか？"
            alert.addButton(withTitle: "UTF-8 で保存")
            alert.addButton(withTitle: "キャンセル")
            guard alert.runModal() == .alertFirstButtonReturn else { return false }
            tab.convertToUTF8()
            return save(tab, force: force)
        } catch {
            showError("「\(tab.title)」を保存できませんでした", detail: error.localizedDescription)
            return false
        }
    }

    func saveActiveAs() {
        guard let tab = activeTab, tab.kind == .markdown else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "md") ?? .plainText]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = tab.url?.lastPathComponent ?? "名称未設定.md"
        panel.directoryURL = tab.url?.deletingLastPathComponent() ?? rootURL
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try tab.save(as: url)
            if rootURL == nil { setRoot(url.deletingLastPathComponent()) }
            tree.reload()
            index.rebuild()
            updateWatcher()
            updateWindowState()
            persistSession()
        } catch {
            showError("保存できませんでした", detail: error.localizedDescription)
        }
    }

    /// 外部変更のバナーから: ディスクの内容を読み込み直す
    func reloadFromDisk(_ tab: DocumentTab) {
        do {
            try tab.reloadFromDisk()
            if tab.id == activeTabID { contentReloaded(tab) }
        } catch {
            showError("読み込み直せませんでした", detail: error.localizedDescription)
        }
    }

    /// 外部変更のバナーから: 自分の編集で上書きする
    func keepMyVersion(_ tab: DocumentTab) {
        save(tab, force: true)
    }

    private func contentReloaded(_ tab: DocumentTab) {
        refreshOutline(tab)
        if tab.mode == .read {
            viewer.render(tab, keepPosition: true)
        } else {
            tab.highlighter.update()
        }
        updateWindowState()
    }

    // MARK: - ファイルの変更監視

    private func handleFileEvents(_ paths: [String]) {
        pendingPaths.formUnion(paths)
        fsWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.processFileEvents() }
        fsWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    private func processFileEvents() {
        let paths = pendingPaths
        pendingPaths.removeAll()
        tree.reload()
        // md・画像以外の変更なら索引は作り直さない
        if paths.contains(where: { FileKinds.isShownInFiler(URL(fileURLWithPath: $0)) || !$0.contains(".") }) {
            index.rebuild()
        }
        for tab in tabs {
            let isActiveEditor = tab.id == activeTabID && tab.mode == .edit
            // 読み込み直しでカーソルが飛ばないよう、位置を控えておく
            if isActiveEditor { editor.captureState() }
            let result = tab.checkDisk()
            guard result == .reloaded, tab.id == activeTabID else { continue }
            contentReloaded(tab)
            if isActiveEditor { editor.attach(tab) }
        }
    }

    // MARK: - 目次

    private func scheduleOutlineRefresh(_ tab: DocumentTab) {
        outlineWork?.cancel()
        let work = DispatchWorkItem { [weak self, weak tab] in
            guard let self, let tab, tab.id == self.activeTabID else { return }
            self.refreshOutline(tab)
        }
        outlineWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    private func refreshOutline(_ tab: DocumentTab) {
        let items = tab.kind == .markdown ? OutlineParser.parse(tab.text) : []
        if items != outline { outline = items }
    }

    func scrollToOutlineItem(_ item: OutlineItem) {
        guard let tab = activeTab else { return }
        if tab.mode == .read {
            viewer.scrollToLine(item.line)
        } else {
            editor.scrollToLine(item.line, moveCursor: true)
            editor.focus()
        }
    }

    /// 今読んでいる見出し
    func currentOutlineItem(topLine: Int) -> OutlineItem? {
        outline.last { $0.line <= topLine }
    }

    // MARK: - 表示設定

    private func settingsDidChange() {
        tree.reload()
        pushViewerSettings()
    }

    /// このウインドウの表示の調整。同じウインドウで開くファイルには引き継ぐ
    @Published private(set) var viewOverrides = ViewOverrides()

    /// 効いているテーマ（ウインドウの調整 → 環境設定の既定 の順に見る）。
    /// 表示設定はウインドウ単位なので tab は使わないが、呼び出し側の意図が分かるよう引数に残す
    func effectiveThemeID(for tab: DocumentTab? = nil) -> String {
        viewOverrides.themeID ?? AppSettings.shared.themeID
    }

    /// テーマの既定（組方向を含む）にウインドウの調整を重ねた表示設定
    func effectiveStyle(for tab: DocumentTab? = nil) -> ViewStyle {
        viewOverrides.applied(to: AppSettings.shared.style(for: effectiveThemeID()))
    }

    func effectiveWriting(for tab: DocumentTab? = nil) -> WritingMode {
        effectiveStyle().writing
    }

    /// 表示パネルやメニューで変えた設定は、このウインドウだけに効く。既定は環境設定でしか変えない
    func updateOverrides(_ change: (inout ViewOverrides) -> Void) {
        var next = viewOverrides
        change(&next)
        guard next != viewOverrides else { return }
        viewOverrides = next
        pushViewerSettings()
    }

    /// このウインドウの調整をやめて既定の表示に戻す
    func resetOverrides() {
        updateOverrides { $0 = ViewOverrides() }
    }

    var hasOverrides: Bool { !viewOverrides.isEmpty }

    func setTheme(_ id: String) {
        updateOverrides { $0.themeID = id }
    }

    func setWriting(_ mode: WritingMode) {
        updateOverrides { $0.writing = mode }
    }

    func toggleWriting() {
        setWriting(effectiveWriting(for: activeTab) == .horizontal ? .vertical : .horizontal)
    }

    /// 閲覧中の文字サイズを変える（このファイルだけ）。0 で既定に戻す
    func changeViewerFontScale(_ direction: Int) {
        let current = effectiveStyle(for: activeTab).fontScale
        updateOverrides {
            switch direction {
            case 1: $0.fontScale = ViewStyle.scaledUp(current)
            case -1: $0.fontScale = ViewStyle.scaledDown(current)
            default: $0.fontScale = nil
            }
        }
    }

    func viewerSettingsPayload(for tab: DocumentTab?) -> [String: Any] {
        let s = AppSettings.shared
        let manager = ThemeManager.shared
        let theme = manager.theme(id: effectiveThemeID(for: tab))
        let style = effectiveStyle(for: tab)
        var payload: [String: Any] = [
            "theme": theme.isUser ? "user" : theme.id,
            "themeHref": theme.href,
            "writing": effectiveWriting(for: tab).rawValue,
            "fontScale": style.fontScale,
            "lineHeight": style.lineHeight,
            "measure": style.measure,
            "headingNumbers": style.headingNumbers,
            "indent": style.indent,
            "justify": style.justify,
            "breaks": s.breaks,
            "showProperties": s.showProperties,
            "clickToPage": s.clickToPage,
        ]
        if let font = style.fontFamilyCSS { payload["fontFamily"] = font }
        if s.useCustomCSS, let href = manager.customCSSHref { payload["customHref"] = href }
        return payload
    }

    private func pushViewerSettings() {
        let payload = viewerSettingsPayload(for: activeTab)
        let comparable = payload.compactMapValues { $0 as? AnyHashable }
        guard comparable != appliedSettings else { return }
        appliedSettings = comparable
        viewer.applySettings(payload)
    }

    // MARK: - 検索

    func showFind() {
        guard let tab = activeTab else { return }
        if tab.mode == .edit {
            let item = NSMenuItem()
            item.tag = NSTextFinder.Action.showFindInterface.rawValue
            editor.textView.performTextFinderAction(item)
            return
        }
        find.isVisible = true
        find.focusRequest += 1
        if !find.query.isEmpty { runFind() }
    }

    func runFind() {
        viewer.find(find.query) { [weak self] count, index in
            self?.find.count = count
            self?.find.index = index
        }
    }

    func findNext(_ direction: Int) {
        guard let tab = activeTab else { return }
        if tab.mode == .edit {
            let item = NSMenuItem()
            item.tag = (direction > 0 ? NSTextFinder.Action.nextMatch : NSTextFinder.Action.previousMatch).rawValue
            editor.textView.performTextFinderAction(item)
            return
        }
        viewer.findNext(direction) { [weak self] count, index in
            self?.find.count = count
            self?.find.index = index
        }
    }

    func hideFind() {
        find.isVisible = false
        viewer.clearFind()
        windowController?.window?.makeFirstResponder(viewer.webView)
    }

    // MARK: - ファイル操作（ファイラーの右クリック）

    func createFile(in directory: URL) {
        guard let name = promptForName(title: "新規ファイル", message: "ファイル名を入力してください", defaultValue: "名称未設定.md") else { return }
        let fileName = name.contains(".") ? name : name + ".md"
        let url = directory.appendingPathComponent(fileName)
        guard !FileManager.default.fileExists(atPath: url.path) else {
            showError("同じ名前のファイルがあります", detail: fileName)
            return
        }
        do {
            try Data().write(to: url)
            tree.expand(directory)
            tree.reload()
            index.rebuild()
            open(url, newTab: true)
            if activeTab?.url == url { setMode(.edit) }
        } catch {
            showError("作成できませんでした", detail: error.localizedDescription)
        }
    }

    func createFolder(in directory: URL) {
        guard let name = promptForName(title: "新規フォルダ", message: "フォルダ名を入力してください", defaultValue: "名称未設定フォルダ") else { return }
        do {
            try FileManager.default.createDirectory(at: directory.appendingPathComponent(name), withIntermediateDirectories: false)
            tree.expand(directory)
            tree.reload()
        } catch {
            showError("作成できませんでした", detail: error.localizedDescription)
        }
    }

    func rename(_ url: URL) {
        guard let name = promptForName(title: "名前を変更", message: "新しい名前を入力してください", defaultValue: url.lastPathComponent),
              name != url.lastPathComponent else { return }
        move(url, to: url.deletingLastPathComponent().appendingPathComponent(name))
    }

    /// ファイルやフォルダを移動する（改名を含む）。開いているタブも追従させる
    func move(_ url: URL, to destination: URL) {
        guard url.standardizedFileURL != destination.standardizedFileURL else { return }
        do {
            try FileManager.default.moveItem(at: url, to: destination)
        } catch {
            showError("移動できませんでした", detail: error.localizedDescription)
            return
        }
        let oldPrefix = url.standardizedFileURL.path
        for tab in tabs {
            guard let current = tab.url?.standardizedFileURL else { continue }
            if current.path == oldPrefix || current.path.hasPrefix(oldPrefix + "/") {
                let suffix = String(current.path.dropFirst(oldPrefix.count))
                let moved = URL(fileURLWithPath: destination.standardizedFileURL.path + suffix)
                ReadingStore.shared.move(from: current, to: moved)
                tab.relocate(to: moved)
            }
        }
        tree.reload()
        index.rebuild()
        updateWatcher()
        updateWindowState()
        persistSession()
    }

    func moveToTrash(_ url: URL) {
        let isOpenAndDirty = tabs.contains { $0.isDirty && $0.url?.standardizedFileURL == url.standardizedFileURL }
        let alert = NSAlert()
        alert.messageText = "「\(url.lastPathComponent)」をゴミ箱に入れますか？"
        if isOpenAndDirty { alert.informativeText = "未保存の変更は失われます。" }
        alert.addButton(withTitle: "ゴミ箱に入れる")
        alert.addButton(withTitle: "キャンセル")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        } catch {
            showError("ゴミ箱に入れられませんでした", detail: error.localizedDescription)
            return
        }
        let prefix = url.standardizedFileURL.path
        for tab in tabs {
            guard let path = tab.url?.standardizedFileURL.path else { continue }
            if path == prefix || path.hasPrefix(prefix + "/") {
                tab.setUntrackedClean()
                close(tab)
            }
        }
        tree.reload()
        index.rebuild()
    }

    private func promptForName(title: String, message: String, defaultValue: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "キャンセル")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = defaultValue
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        // 拡張子を除いた部分を選択しておく
        alert.layout()
        DispatchQueue.main.async {
            field.selectText(nil)
            if let editor = field.currentEditor() {
                let base = (defaultValue as NSString).deletingPathExtension
                editor.selectedRange = NSRange(location: 0, length: (base as NSString).length)
            }
        }
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.contains("/") else { return nil }
        return value
    }

    func showError(_ message: String, detail: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.informativeText = detail
        alert.runModal()
    }

    // MARK: - セッション

    func sessionState() -> SessionWindow {
        SessionWindow(
            root: rootURL?.path,
            tabs: tabs.compactMap { $0.url?.path },
            active: activeTab?.url?.path,
            sidebarVisible: sidebarVisible,
            sidebarWidth: Double(sidebarWidth)
        )
    }

    func restore(_ state: SessionWindow) {
        sidebarVisible = state.sidebarVisible
        sidebarWidth = CGFloat(state.sidebarWidth)
        if let root = state.root, FileManager.default.fileExists(atPath: root) {
            setRoot(URL(fileURLWithPath: root))
        }
        for path in state.tabs where FileManager.default.fileExists(atPath: path) {
            open(URL(fileURLWithPath: path), newTab: true)
        }
        if let active = state.active, let tab = tabs.first(where: { $0.url?.path == active }) {
            activate(tab)
        }
    }

    private func persistSession() {
        NotificationCenter.default.post(name: .shioriSessionChanged, object: nil)
    }
}

// MARK: - ビューワーからの通知

extension WorkspaceModel: ViewerDelegate {
    func viewerDidScroll(position: Double, progress: Double) {
        guard let tab = activeTab, tab.mode == .read else { return }
        status.topLine = Int(position)
        status.progress = progress
        tab.viewerLine = position
        if let url = tab.url { ReadingStore.shared.update(url) { $0.line = position } }
    }

    func viewerOpenPath(_ path: String, fragment: String?, newTab: Bool) {
        let url = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: path) {
            if FileKinds.isOpenable(url) {
                open(url, newTab: newTab, fragment: fragment)
            } else {
                NSWorkspace.shared.open(url)
            }
        } else {
            showError("リンク先のファイルが見つかりません", detail: path)
        }
    }

    func viewerOpenExternal(_ url: URL) {
        // 開いてよいスキームだけ外部のアプリへ渡す
        guard let scheme = url.scheme?.lowercased(), ["http", "https", "mailto", "tel"].contains(scheme) else { return }
        NSWorkspace.shared.open(url)
    }

    func viewerOpenWikilink(_ target: String, newTab: Bool) {
        let fragment = target.firstIndex(of: "#").map { String(target[target.index(after: $0)...]) }
        if let url = index.resolveWikilink(target, from: activeTab?.url) {
            if url == activeTab?.url, let fragment {
                activeTab?.pendingFragment = fragment
                presentActive()
            } else {
                open(url, newTab: newTab, fragment: fragment)
            }
            return
        }
        // 見つからないリンクは作成を提案する（Obsidian と同じ流れ）
        let alert = NSAlert()
        alert.messageText = "「\(target)」は見つかりません"
        alert.informativeText = "新しいノートを作成しますか？"
        alert.addButton(withTitle: "作成")
        alert.addButton(withTitle: "キャンセル")
        guard alert.runModal() == .alertFirstButtonReturn,
              let directory = activeTab?.url?.deletingLastPathComponent() ?? rootURL else { return }
        let name = target.hasSuffix(".md") ? target : target + ".md"
        let url = directory.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: url)
            index.rebuild()
            tree.reload()
            open(url, newTab: newTab)
        } catch {
            showError("作成できませんでした", detail: error.localizedDescription)
        }
    }

    func viewerToggleTask(line: Int, checked: Bool) {
        guard let tab = activeTab, tab.kind == .markdown else { return }
        tab.toggleTask(line: line, checked: checked)
    }

    func viewerImageInfo(width: Int, height: Int) {
        activeTab?.imageSize = CGSize(width: width, height: height)
    }

    func viewerResolveWikilink(_ target: String, from: String?) -> URL? {
        index.resolveWikilink(target, from: from.map { URL(fileURLWithPath: $0) })
    }
}

extension Notification.Name {
    static let shioriSessionChanged = Notification.Name("ShioriSessionChanged")
}
