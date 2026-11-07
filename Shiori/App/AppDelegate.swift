import AppKit

@main
enum ShioriMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var windowControllers: [MainWindowController] = []
    /// 最後に操作していたウィンドウ（メニューの宛先）
    private(set) weak var currentController: MainWindowController?

    private var pendingURLs: [URL] = []
    private var didFinishLaunching = false
    private var settingsWindow: NSWindow?
    private var mainMenu: MainMenuBuilder?

    static var shared: AppDelegate { NSApp.delegate as! AppDelegate }

    var workspace: WorkspaceModel? { currentController?.workspace }

    func applicationWillFinishLaunching(_ notification: Notification) {
        AppSettings.shared.applyAppearance()
        let builder = MainMenuBuilder(delegate: self)
        NSApp.mainMenu = builder.build()
        mainMenu = builder
        // タブは自前で持つので、OS のウィンドウタブは使わない
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        didFinishLaunching = true
        NotificationCenter.default.addObserver(self, selector: #selector(saveSession), name: .shioriSessionChanged, object: nil)

        if !pendingURLs.isEmpty {
            let urls = pendingURLs
            pendingURLs = []
            open(urls)
        } else if AppSettings.shared.restoreSession, !SessionStore.load().isEmpty {
            for state in SessionStore.load() {
                let controller = makeWindow()
                // 先にウィンドウを見せてから読み込む（初回のアクセス許可待ちで白画面にならないように）
                DispatchQueue.main.async { controller.workspace.restore(state) }
            }
        } else {
            _ = makeWindow()
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if didFinishLaunching {
            open(urls)
        } else {
            pendingURLs.append(contentsOf: urls)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { _ = makeWindow() }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // 終了時の状態を保存してから、未保存の文書を確認する
        let session = windowControllers.map { $0.workspace.sessionState() }
        for controller in windowControllers {
            controller.window?.makeKeyAndOrderFront(nil)
            if !controller.workspace.prepareToCloseAll() { return .terminateCancel }
        }
        SessionStore.save(session)
        ReadingStore.shared.saveNow()
        return .terminateNow
    }

    // MARK: - ウィンドウ

    func makeWindow(root: URL? = nil) -> MainWindowController {
        let controller = MainWindowController(workspace: WorkspaceModel())
        windowControllers.append(controller)
        if let root { controller.workspace.setRoot(root) }
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        currentController = controller
        return controller
    }

    func windowDidBecomeMain(_ controller: MainWindowController) {
        currentController = controller
    }

    func windowWillClose(_ controller: MainWindowController) {
        windowControllers.removeAll { $0 === controller }
        if currentController === controller { currentController = windowControllers.last }
        saveSession()
    }

    @objc func saveSession() {
        SessionStore.save(windowControllers.map { $0.workspace.sessionState() })
    }

    // MARK: - Finder などから開く

    /// どこから開こうとしているか
    enum OpenSource {
        /// Finder のダブルクリック、Dock のアイコンへのドロップなど
        case external
        /// アプリ内の「開く…」や最近使った項目
        case app
    }

    /// ファイルやフォルダを開くウインドウを決める。
    /// - すでにどこかのタブで開いていれば、そのタブを前面に出す
    /// - 外から開くときは環境設定に従い、今のウインドウのタブか新しいウインドウで開く
    ///   （同じウインドウなら今の表示設定を引き継ぎ、新しいウインドウは既定の表示で始まる）
    /// - アプリ内から開くときは今のウインドウで開く
    func open(_ urls: [URL], from source: OpenSource = .external) {
        let useCurrentWindow = source == .app || AppSettings.shared.externalOpenMode == .existingWindow
        // 1 回の操作で複数のファイルを開くときは、新しいウインドウを 1 枚にまとめる
        var windowForThisRequest: MainWindowController?

        for url in urls {
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false

            if !isDirectory, let (controller, tab) = windowShowing(url) {
                bringToFront(controller)
                controller.workspace.activate(tab)
                continue
            }

            if isDirectory {
                if source == .app, let current = currentWindow {
                    bringToFront(current)
                    current.workspace.setRoot(url)
                    current.workspace.sidebarVisible = true
                } else if let empty = emptyWindow {
                    bringToFront(empty)
                    empty.workspace.setRoot(url)
                } else {
                    _ = makeWindow(root: url)
                }
                continue
            }

            let target = useCurrentWindow ? currentWindow : (windowForThisRequest ?? emptyWindow)
            if let target {
                bringToFront(target)
                target.workspace.open(url, newTab: true)
                if !useCurrentWindow { windowForThisRequest = target }
            } else {
                let controller = makeWindow(root: url.deletingLastPathComponent())
                controller.workspace.open(url, newTab: true)
                windowForThisRequest = controller
            }
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 最後に操作していたウインドウ
    private var currentWindow: MainWindowController? {
        currentController ?? windowControllers.last
    }

    /// 何も開いていないウインドウ（再利用できる）
    private var emptyWindow: MainWindowController? {
        windowControllers.first { $0.workspace.rootURL == nil && $0.workspace.tabs.isEmpty }
    }

    /// そのファイルを開いているウインドウとタブ
    private func windowShowing(_ url: URL) -> (MainWindowController, DocumentTab)? {
        let target = url.standardizedFileURL
        for controller in windowControllers {
            if let tab = controller.workspace.tabs.first(where: { $0.url?.standardizedFileURL == target }) {
                return (controller, tab)
            }
        }
        return nil
    }

    private func bringToFront(_ controller: MainWindowController) {
        controller.window?.makeKeyAndOrderFront(nil)
        currentController = controller
    }

    // MARK: - 環境設定

    @objc func showSettings(_ sender: Any?) {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let window = SettingsWindow.make()
        settingsWindow = window
        window.center()
        window.makeKeyAndOrderFront(nil)
    }
}
