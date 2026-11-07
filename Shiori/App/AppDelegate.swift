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

    /// 開いている窓のどこで開くかを決める。
    /// ファイルを含むルートの窓があればそこのタブで、なければ親フォルダをルートにした窓で開く。
    func open(_ urls: [URL]) {
        for url in urls {
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if let controller = bestWindow(for: url, isDirectory: isDirectory) {
                controller.window?.makeKeyAndOrderFront(nil)
                currentController = controller
                controller.workspace.open(url, newTab: true)
            } else if isDirectory {
                _ = makeWindow(root: url)
            } else {
                let controller = makeWindow(root: url.deletingLastPathComponent())
                controller.workspace.open(url, newTab: true)
            }
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func bestWindow(for url: URL, isDirectory: Bool) -> MainWindowController? {
        let path = url.standardizedFileURL.path
        // ファイルを含むルートのうち、いちばん深いものを選ぶ
        var best: (MainWindowController, Int)?
        if !isDirectory {
            for controller in windowControllers {
                guard let root = controller.workspace.rootURL?.path else { continue }
                let prefix = root.hasSuffix("/") ? root : root + "/"
                if path.hasPrefix(prefix), root.count > (best?.1 ?? -1) { best = (controller, root.count) }
            }
        }
        if let best { return best.0 }
        // 何も開いていない窓があれば再利用する
        return windowControllers.first { $0.workspace.rootURL == nil && $0.workspace.tabs.isEmpty }
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
