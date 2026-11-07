import AppKit
import UniformTypeIdentifiers

/// クロージャで動くメニュー項目
final class ActionMenuItem: NSMenuItem {
    private let handler: () -> Void
    var isEnabledCheck: (() -> Bool)?
    var isCheckedCheck: (() -> Bool)?

    init(_ title: String, key: String = "", modifiers: NSEvent.ModifierFlags = [.command], handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: key)
        keyEquivalentModifierMask = modifiers
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) は使わない") }

    @objc private func run() { handler() }
}

extension ActionMenuItem: NSMenuItemValidation {
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if let isCheckedCheck { state = isCheckedCheck() ? .on : .off }
        return isEnabledCheck?() ?? true
    }
}

/// メインメニューを組み立てる。コマンドは AppDelegate の現在のワークスペースへ送る。
final class MainMenuBuilder: NSObject, NSMenuDelegate {
    private unowned let delegate: AppDelegate
    private var themeMenu: NSMenu?
    private var recentFilesMenu: NSMenu?
    private var recentFoldersMenu: NSMenu?
    private var fontKeyMonitor: Any?

    init(delegate: AppDelegate) {
        self.delegate = delegate
    }

    private var ws: WorkspaceModel? { delegate.workspace }
    private var hasMarkdownTab: Bool { ws?.activeTab?.kind == .markdown }
    private var isEditing: Bool { ws?.activeTab?.mode == .edit && hasMarkdownTab }

    /// ⌘+ は配列によって実際に届く文字が違う（US の ⌘=、JIS の ⌘;）ので、キーを直接見て受ける
    private func installFontSizeKeyMonitor() {
        fontKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.shift, .capsLock, .numericPad, .function])
            guard modifiers == .command, let self else { return event }
            let key = event.charactersIgnoringModifiers ?? ""
            guard ["+", "=", ";"].contains(key), self.delegate.workspace != nil else { return event }
            self.changeFontSize(1)
            return nil
        }
    }

    func build() -> NSMenu {
        installFontSizeKeyMonitor()
        let menu = NSMenu()
        menu.addItem(submenu(appMenu(), title: "Shiori"))
        menu.addItem(submenu(fileMenu(), title: "ファイル"))
        menu.addItem(submenu(editMenu(), title: "編集"))
        menu.addItem(submenu(formatMenu(), title: "書式"))
        menu.addItem(submenu(viewMenu(), title: "表示"))
        let window = windowMenu()
        menu.addItem(submenu(window, title: "ウィンドウ"))
        NSApp.windowsMenu = window
        let help = helpMenu()
        menu.addItem(submenu(help, title: "ヘルプ"))
        NSApp.helpMenu = help
        return menu
    }

    private func submenu(_ menu: NSMenu, title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        menu.title = title
        item.submenu = menu
        return item
    }

    private func action(_ title: String, _ key: String = "", _ modifiers: NSEvent.ModifierFlags = [.command],
                        enabled: (() -> Bool)? = nil, checked: (() -> Bool)? = nil, _ handler: @escaping () -> Void) -> ActionMenuItem {
        let item = ActionMenuItem(title, key: key, modifiers: key.isEmpty ? [] : modifiers, handler: handler)
        item.isEnabledCheck = enabled
        item.isCheckedCheck = checked
        return item
    }

    // MARK: - アプリ

    private func appMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "Shiori について", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "設定…", action: #selector(AppDelegate.showSettings(_:)), keyEquivalent: ",")
        settings.target = delegate
        menu.addItem(settings)
        menu.addItem(.separator())
        let services = NSMenuItem(title: "サービス", action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu()
        services.submenu = servicesMenu
        NSApp.servicesMenu = servicesMenu
        menu.addItem(services)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Shiori を隠す", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let others = NSMenuItem(title: "ほかを隠す", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        others.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(others)
        menu.addItem(withTitle: "すべてを表示", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Shiori を終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    // MARK: - ファイル

    private func fileMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(action("新規タブ", "n") { [weak self] in
            guard let self else { return }
            if let ws = self.ws { ws.newUntitledTab() } else { self.delegate.makeWindow().workspace.newUntitledTab() }
        })
        menu.addItem(action("新規ウィンドウ", "n", [.command, .shift]) { [weak self] in
            _ = self?.delegate.makeWindow()
        })
        menu.addItem(.separator())
        menu.addItem(action("開く…", "o") { [weak self] in self?.openPanel() })
        menu.addItem(action("クイックオープン…", "p", [.command, .shift]) { [weak self] in
            guard let ws = self?.ws else { return }
            ws.quickOpenVisible = true
        })

        let recentFiles = NSMenuItem(title: "最近開いたファイル", action: nil, keyEquivalent: "")
        let filesSub = NSMenu()
        filesSub.delegate = self
        recentFiles.submenu = filesSub
        recentFilesMenu = filesSub
        menu.addItem(recentFiles)

        let recentFolders = NSMenuItem(title: "最近開いたフォルダ", action: nil, keyEquivalent: "")
        let foldersSub = NSMenu()
        foldersSub.delegate = self
        recentFolders.submenu = foldersSub
        recentFoldersMenu = foldersSub
        menu.addItem(recentFolders)

        menu.addItem(.separator())
        menu.addItem(action("タブを閉じる", "w") { [weak self] in self?.ws?.closeActiveTab() })
        menu.addItem(action("ウィンドウを閉じる", "w", [.command, .shift]) {
            NSApp.keyWindow?.performClose(nil)
        })
        menu.addItem(.separator())
        menu.addItem(action("保存", "s", enabled: { [weak self] in self?.hasMarkdownTab ?? false }) { [weak self] in self?.ws?.saveActive() })
        menu.addItem(action("別名で保存…", "s", [.command, .shift], enabled: { [weak self] in self?.hasMarkdownTab ?? false }) { [weak self] in self?.ws?.saveActiveAs() })
        menu.addItem(.separator())
        menu.addItem(action("PDF として書き出す…", "e", [.command, .shift], enabled: { [weak self] in self?.hasMarkdownTab ?? false }) { [weak self] in self?.export(.pdf) })
        menu.addItem(action("HTML として書き出す…", "h", [.command, .shift], enabled: { [weak self] in self?.hasMarkdownTab ?? false }) { [weak self] in self?.export(.html) })
        menu.addItem(action("印刷…", "p", enabled: { [weak self] in self?.hasMarkdownTab ?? false }) { [weak self] in self?.printDocument() })
        return menu
    }

    private func openPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = "Markdown ファイルかフォルダを選んでください"
        guard panel.runModal() == .OK else { return }
        delegate.open(panel.urls)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if menu === recentFilesMenu {
            let files = RecentItems.files
            for url in files {
                menu.addItem(action(url.lastPathComponent) { [weak self] in self?.delegate.open([url]) })
            }
            if files.isEmpty {
                menu.addItem(withTitle: "なし", action: nil, keyEquivalent: "")
            } else {
                menu.addItem(.separator())
                menu.addItem(action("履歴を消去") { NSDocumentController.shared.clearRecentDocuments(nil) })
            }
        } else if menu === recentFoldersMenu {
            let folders = RecentItems.folders
            for url in folders {
                menu.addItem(action(url.lastPathComponent) { [weak self] in self?.delegate.open([url]) })
            }
            if folders.isEmpty { menu.addItem(withTitle: "なし", action: nil, keyEquivalent: "") }
        } else if menu === themeMenu {
            for theme in ThemeManager.shared.allThemes {
                menu.addItem(action(theme.name, checked: { [weak self] in
                    self?.ws?.effectiveThemeID(for: self?.ws?.activeTab) == theme.id
                }) { [weak self] in self?.ws?.setTheme(theme.id) })
            }
        }
    }

    private enum ExportKind { case pdf, html }

    private func export(_ kind: ExportKind) {
        guard let ws, let tab = ws.activeTab, tab.kind == .markdown else { return }
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        let base = tab.url?.deletingPathExtension().lastPathComponent ?? "名称未設定"
        panel.directoryURL = tab.url?.deletingLastPathComponent()
        switch kind {
        case .pdf:
            panel.allowedContentTypes = [.pdf]
            panel.nameFieldStringValue = base + ".pdf"
        case .html:
            panel.allowedContentTypes = [.html]
            panel.nameFieldStringValue = base + ".html"
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let output: Exporter.Output = kind == .pdf ? .pdf(url) : .html(url)
        Exporter.run(
            output,
            markdown: tab.text,
            path: tab.url?.path,
            settings: ws.viewerSettingsPayload(for: tab),
            resolver: { [weak ws] target, from in ws?.index.resolveWikilink(target, from: from.map { URL(fileURLWithPath: $0) }) },
            completion: { [weak ws] error in
                if let error { ws?.showError("書き出しに失敗しました", detail: error.localizedDescription) }
            }
        )
    }

    private func printDocument() {
        guard let ws, let tab = ws.activeTab, tab.kind == .markdown else { return }
        Exporter.run(
            .print,
            markdown: tab.text,
            path: tab.url?.path,
            settings: ws.viewerSettingsPayload(for: tab),
            resolver: { [weak ws] target, from in ws?.index.resolveWikilink(target, from: from.map { URL(fileURLWithPath: $0) }) },
            completion: { [weak ws] error in
                if let error { ws?.showError("印刷に失敗しました", detail: error.localizedDescription) }
            }
        )
    }

    // MARK: - 編集

    private func editMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "取り消す", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = NSMenuItem(title: "やり直す", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(redo)
        menu.addItem(.separator())
        menu.addItem(withTitle: "カット", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: "コピー", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "ペースト", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addItem(withTitle: "すべてを選択", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        menu.addItem(.separator())
        menu.addItem(action("検索…", "f") { [weak self] in self?.ws?.showFind() })
        menu.addItem(action("次を検索", "g") { [weak self] in self?.ws?.findNext(1) })
        menu.addItem(action("前を検索", "g", [.command, .shift]) { [weak self] in self?.ws?.findNext(-1) })
        return menu
    }

    // MARK: - 書式

    private func formatMenu() -> NSMenu {
        let menu = NSMenu()
        let editing: () -> Bool = { [weak self] in self?.isEditing ?? false }
        func wrap(_ title: String, _ key: String, _ prefix: String, _ suffix: String, _ placeholder: String, _ modifiers: NSEvent.ModifierFlags = [.command]) -> NSMenuItem {
            action(title, key, modifiers, enabled: editing) { [weak self] in
                self?.ws?.editor.toggleWrap(prefix: prefix, suffix: suffix, placeholder: placeholder)
            }
        }
        menu.addItem(wrap("太字", "b", "**", "**", "太字"))
        menu.addItem(wrap("斜体", "i", "*", "*", "斜体"))
        menu.addItem(wrap("取り消し線", "x", "~~", "~~", "取り消し線", [.command, .shift]))
        menu.addItem(wrap("マーカー", "m", "==", "==", "マーカー", [.command, .shift]))
        menu.addItem(wrap("インラインコード", "c", "`", "`", "code", [.command, .option]))
        menu.addItem(wrap("リンク", "k", "[", "](url)", "リンク"))
        menu.addItem(.separator())

        let headings = NSMenuItem(title: "見出し", action: nil, keyEquivalent: "")
        let headingMenu = NSMenu()
        for level in 1...6 {
            headingMenu.addItem(action("見出し \(level)", "\(level)", [.command, .control], enabled: editing) { [weak self] in
                self?.ws?.editor.setHeading(level: level)
            })
        }
        headingMenu.addItem(.separator())
        headingMenu.addItem(action("本文に戻す", "0", [.command, .control], enabled: editing) { [weak self] in
            self?.ws?.editor.setHeading(level: 0)
        })
        headings.submenu = headingMenu
        menu.addItem(headings)
        menu.addItem(.separator())
        menu.addItem(action("箇条書き", enabled: editing) { [weak self] in self?.ws?.editor.toggleLinePrefix("- ") })
        menu.addItem(action("番号付きリスト", enabled: editing) { [weak self] in self?.ws?.editor.toggleLinePrefix("1. ") })
        menu.addItem(action("タスク", enabled: editing) { [weak self] in self?.ws?.editor.toggleLinePrefix("- [ ] ") })
        menu.addItem(action("引用", enabled: editing) { [weak self] in self?.ws?.editor.toggleLinePrefix("> ") })
        return menu
    }

    // MARK: - 表示

    private func viewMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(action("閲覧 / 編集を切り替え", "e", enabled: { [weak self] in self?.hasMarkdownTab ?? false }) { [weak self] in self?.ws?.toggleMode() })
        menu.addItem(.separator())
        menu.addItem(action("サイドバーを表示", "\\", checked: { [weak self] in self?.ws?.sidebarVisible ?? false }) { [weak self] in
            self?.ws?.sidebarVisible.toggle()
        })
        menu.addItem(action("ファイル", "1", [.command, .option]) { [weak self] in
            self?.ws?.sidebarVisible = true
            self?.ws?.sidebarPanel = .files
        })
        menu.addItem(action("目次", "2", [.command, .option]) { [weak self] in
            self?.ws?.sidebarVisible = true
            self?.ws?.sidebarPanel = .outline
        })
        menu.addItem(.separator())

        // 文字サイズ（閲覧中はビューワー、編集中はエディタに効く）
        menu.addItem(action("文字を大きく", "+") { [weak self] in self?.changeFontSize(1) })
        menu.addItem(action("文字を小さく", "-") { [weak self] in self?.changeFontSize(-1) })
        menu.addItem(action("標準の文字サイズ", "0") { [weak self] in self?.changeFontSize(0) })
        menu.addItem(.separator())

        menu.addItem(action("縦書き", "v", [.command, .option], checked: { [weak self] in
            self?.ws?.effectiveWriting(for: self?.ws?.activeTab) == .vertical
        }) { [weak self] in self?.ws?.toggleWriting() })

        let theme = NSMenuItem(title: "テーマ", action: nil, keyEquivalent: "")
        let themeSub = NSMenu()
        themeSub.delegate = self
        theme.submenu = themeSub
        themeMenu = themeSub
        menu.addItem(theme)
        menu.addItem(.separator())

        menu.addItem(action("集中モード", "f", [.command, .option], checked: { [weak self] in self?.ws?.focusMode ?? false }) { [weak self] in
            self?.ws?.focusMode.toggle()
        })
        let fullscreen = NSMenuItem(title: "フルスクリーン", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fullscreen.keyEquivalentModifierMask = [.command, .control]
        menu.addItem(fullscreen)
        menu.addItem(.separator())

        menu.addItem(action("戻る", "[") { [weak self] in self?.ws?.goBack() })
        menu.addItem(action("進む", "]") { [weak self] in self?.ws?.goForward() })
        menu.addItem(action("前のタブ", "[", [.command, .shift]) { [weak self] in self?.ws?.activateAdjacentTab(-1) })
        menu.addItem(action("次のタブ", "]", [.command, .shift]) { [weak self] in self?.ws?.activateAdjacentTab(1) })
        for number in 1...9 {
            let item = action("タブ \(number)", "\(number)") { [weak self] in self?.ws?.activateTab(at: number - 1) }
            item.isHidden = true
            item.allowsKeyEquivalentWhenHidden = true
            menu.addItem(item)
        }
        return menu
    }

    private func changeFontSize(_ direction: Int) {
        let settings = AppSettings.shared
        if isEditing {
            switch direction {
            case 1: settings.editorFontSize = min(40, settings.editorFontSize + 1)
            case -1: settings.editorFontSize = max(9, settings.editorFontSize - 1)
            default: settings.editorFontSize = 14
            }
        } else {
            switch direction {
            case 1: settings.increaseFontScale()
            case -1: settings.decreaseFontScale()
            default: settings.fontScale = 1
            }
        }
    }

    // MARK: - ウィンドウ・ヘルプ

    private func windowMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "しまう", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        menu.addItem(withTitle: "拡大／縮小", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "すべてを手前に移動", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        return menu
    }

    private func helpMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(action("Markdown 記法ガイドを開く") { [weak self] in self?.openGuide() })
        return menu
    }

    /// 同梱の記法ガイドを一時フォルダへコピーして開く（編集しても同梱ファイルを壊さない）
    private func openGuide() {
        guard let dist = Bundle.main.url(forResource: "dist", withExtension: nil) else { return }
        let source = dist.appendingPathComponent("guide/記法ガイド.md")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ShioriGuide", isDirectory: true)
        let target = folder.appendingPathComponent("記法ガイド.md")
        do {
            try? FileManager.default.removeItem(at: folder)
            try FileManager.default.createDirectory(at: folder.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: source.deletingLastPathComponent(), to: folder)
        } catch {
            ws?.showError("ガイドを開けませんでした", detail: error.localizedDescription)
            return
        }
        delegate.open([target])
    }
}
