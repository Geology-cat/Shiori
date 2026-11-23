import AppKit
import SwiftUI

/// 本文を載せる NSHostingView。
/// 透明なビューは既定でドラッグするとウインドウが動くので、タブのドラッグと取り合わないよう止める。
/// ウインドウを動かしてよい余白には TitlebarArea を敷いている。
final class MainHostingView<Content: View>: NSHostingView<Content> {
    override var mouseDownCanMoveWindow: Bool { false }
}

/// メインウインドウ。
/// 裏にあるウインドウの上部バーをクリックすると、AppKit はそれを「ウインドウを動かす操作」として扱い、
/// タブを引いてもウインドウごと動いてしまう。上部バーの帯（余白以外）へのクリックでは、先に前へ出して
/// キーウインドウにしてから、前面のウインドウと同じように処理させる。
final class MainWindow: NSWindow {
    static let topBarHeight: CGFloat = 34

    override func sendEvent(_ event: NSEvent) {
        // hitTest には親（ウインドウの枠）の座標を渡す。余白（TitlebarAreaView）は自前でドラッグを扱うので除く
        if event.type == .leftMouseDown, !isKeyWindow, isInTopBar(event),
           !(contentView?.hitTest(event.locationInWindow) is TitlebarAreaView) {
            makeKeyAndOrderFront(nil)
        }
        super.sendEvent(event)
    }

    private func isInTopBar(_ event: NSEvent) -> Bool {
        guard let contentView else { return false }
        let point = contentView.convert(event.locationInWindow, from: nil)
        let fromTop = contentView.isFlipped ? point.y : contentView.bounds.height - point.y
        return fromTop <= Self.topBarHeight
    }
}

/// メインウィンドウ。ウィンドウ 1 枚につきワークスペースを 1 つ持つ。
final class MainWindowController: NSWindowController, NSWindowDelegate {
    let workspace: WorkspaceModel

    init(workspace: WorkspaceModel) {
        self.workspace = workspace
        let window = MainWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 780),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.minSize = NSSize(width: 560, height: 360)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.setFrameAutosaveName("ShioriMainWindow")
        super.init(window: window)

        workspace.windowController = self
        window.delegate = self
        window.contentView = MainHostingView(rootView: MainView(workspace: workspace))
        if !window.setFrameUsingName("ShioriMainWindow") { window.center() }
        // 複数枚開くときは少しずらす
        if AppDelegate.shared.windowControllers.contains(where: { $0 !== self && $0.window?.frame == window.frame }) {
            let origin = window.frame.origin
            window.setFrameOrigin(NSPoint(x: origin.x + 28, y: origin.y - 28))
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) は使わない") }

    func windowDidBecomeMain(_ notification: Notification) {
        AppDelegate.shared.windowDidBecomeMain(self)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        workspace.prepareToCloseAll()
    }

    func windowWillClose(_ notification: Notification) {
        AppDelegate.shared.windowWillClose(self)
    }

    // アプリを切り替えたら保存しておく（他のアプリで開いたときに古い内容を見せない）
    func windowDidResignMain(_ notification: Notification) {
        if let tab = workspace.activeTab, tab.isDirty, AppSettings.shared.autosave, tab.url != nil {
            _ = try? tab.save()
        }
    }
}
