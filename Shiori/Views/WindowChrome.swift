import AppKit
import SwiftUI

// MARK: - タイトルバーの余白

/// 上部バーやサイドバー見出しの空いた所。ドラッグでウインドウを動かし、ダブルクリックで拡大・しまう。
/// ウインドウのほかの部分ではマウスでウインドウが動かないようにしている（タブのドラッグと取り合わないように）ので、
/// 動かしてよい所はこのビューを背景に敷いて示す。
struct TitlebarArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { TitlebarAreaView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

final class TitlebarAreaView: NSView {
    // 自前で performDrag するので、AppKit には任せない（ダブルクリックを受け取るため）
    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        if event.clickCount == 2 {
            WindowTitlebar.performDoubleClick(window)
        } else {
            window.performDrag(with: event)
        }
    }
}

enum WindowTitlebar {
    /// システム設定（デスクトップと Dock →「ウインドウのタイトルバーをダブルクリックして」）に従う
    static func performDoubleClick(_ window: NSWindow) {
        let defaults = UserDefaults.standard
        let action = defaults.string(forKey: "AppleActionOnDoubleClick")
        switch action {
        case "Minimize":
            window.performMiniaturize(nil)
        case "None":
            break
        case "Fill":
            fill(window)
        case nil where defaults.bool(forKey: "AppleMiniaturizeOnDoubleClick"):
            // 古い形式の設定
            window.performMiniaturize(nil)
        default:
            // 「拡大／縮小」（既定）
            window.performZoom(nil)
        }
    }

    /// 画面いっぱいに広げる。すでに広がっていれば元に戻す
    private static var restoreFrames: [ObjectIdentifier: NSRect] = [:]

    private static func fill(_ window: NSWindow) {
        guard let screen = window.screen ?? NSScreen.main else { return }
        let key = ObjectIdentifier(window)
        let visible = screen.visibleFrame
        if window.frame.equalTo(visible), let previous = restoreFrames[key] {
            window.setFrame(previous, display: true, animate: true)
            restoreFrames[key] = nil
        } else {
            restoreFrames[key] = window.frame
            window.setFrame(visible, display: true, animate: true)
        }
    }
}

// MARK: - タブを切り離すときの影

/// タブをタブ欄の外へ引き出している間、カーソルに付いてくる小さな札
final class TabDragGhost {
    static let shared = TabDragGhost()

    /// 離したときに何が起きるか
    enum Mode {
        /// 新しいウインドウにする
        case newWindow
        /// カーソルの下のウインドウのタブにする
        case join
    }

    private var panel: NSPanel?
    private var title = ""
    private var mode = Mode.newWindow

    func show(title: String, mode: Mode, at point: NSPoint) {
        let panel = self.panel ?? makePanel()
        if self.panel == nil || self.title != title || self.mode != mode {
            self.title = title
            self.mode = mode
            let host = NSHostingView(rootView: GhostLabel(title: title, mode: mode))
            host.frame = NSRect(origin: .zero, size: host.fittingSize)
            panel.setContentSize(host.fittingSize)
            panel.contentView = host
        }
        self.panel = panel
        // カーソルの右下に出す（ドロップ先が見えるように）
        panel.setFrameOrigin(NSPoint(x: point.x + 10, y: point.y - panel.frame.height - 6))
        if !panel.isVisible { panel.orderFront(nil) }
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 30),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        return panel
    }
}

private struct GhostLabel: View {
    let title: String
    let mode: TabDragGhost.Mode

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: mode == .join ? "plus.rectangle.on.rectangle" : "macwindow.badge.plus")
                .font(.system(size: 11))
                .foregroundStyle(mode == .join ? Color.accentColor : Color.secondary)
            Text(title)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .frame(maxWidth: 240)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.primary.opacity(0.12)))
        .fixedSize()
    }
}
