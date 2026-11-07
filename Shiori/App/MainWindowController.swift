import AppKit
import SwiftUI

/// メインウィンドウ。ウィンドウ 1 枚につきワークスペースを 1 つ持つ。
final class MainWindowController: NSWindowController, NSWindowDelegate {
    let workspace: WorkspaceModel

    init(workspace: WorkspaceModel) {
        self.workspace = workspace
        let window = NSWindow(
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
        window.contentView = NSHostingView(rootView: MainView(workspace: workspace))
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
