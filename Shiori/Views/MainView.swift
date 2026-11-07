import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// ウィンドウ全体のレイアウト: 左にサイドバー、右に上部バーと本文
struct MainView: View {
    @ObservedObject var workspace: WorkspaceModel

    var body: some View {
        HStack(spacing: 0) {
            if workspace.sidebarVisible && !workspace.focusMode {
                SidebarView(workspace: workspace, tree: workspace.tree)
                    .frame(width: workspace.sidebarWidth)
                SidebarResizer(width: $workspace.sidebarWidth)
            }
            VStack(spacing: 0) {
                if !workspace.focusMode {
                    TopBar(workspace: workspace)
                    Divider()
                }
                DocumentArea(workspace: workspace)
            }
        }
        .ignoresSafeArea()
        .frame(minWidth: 560, minHeight: 360)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
        .overlay {
            if workspace.quickOpenVisible {
                QuickOpenOverlay(workspace: workspace)
            }
        }
        .overlay(alignment: .topTrailing) {
            if workspace.focusMode {
                FocusExitButton { workspace.focusMode = false }
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers where provider.canLoadObject(ofClass: URL.self) {
            handled = true
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async { workspace.open(url, newTab: true) }
            }
        }
        return handled
    }
}

/// サイドバーの幅を変えるつまみ
private struct SidebarResizer: View {
    @Binding var width: CGFloat
    @State private var startWidth: CGFloat?

    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: 1)
            .overlay {
                Color.clear
                    .frame(width: 9)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { value in
                                let start = startWidth ?? width
                                startWidth = start
                                width = min(520, max(170, start + value.translation.width))
                            }
                            .onEnded { _ in startWidth = nil }
                    )
            }
    }
}

/// 本文の領域: ビューワーとエディタを重ね、見せるほうだけ表示する
struct DocumentArea: View {
    @ObservedObject var workspace: WorkspaceModel

    var body: some View {
        ZStack {
            Group {
                if let tab = workspace.activeTab {
                    ActiveDocumentView(workspace: workspace, tab: tab)
                } else {
                    ZStack {
                        Color(nsColor: .textBackgroundColor)
                        WelcomeView(workspace: workspace)
                    }
                }
            }
        }
    }
}

private struct ActiveDocumentView: View {
    @ObservedObject var workspace: WorkspaceModel
    @ObservedObject var tab: DocumentTab

    var body: some View {
        VStack(spacing: 0) {
            if tab.mode == .edit && tab.kind == .markdown && !workspace.focusMode {
                FormatBar(editor: workspace.editor)
                Divider()
            }
            if tab.hasExternalChange {
                ExternalChangeBanner(workspace: workspace, tab: tab)
            } else if tab.isMissing {
                MissingFileBanner(workspace: workspace, tab: tab)
            }
            ZStack(alignment: .topTrailing) {
                HostedView(view: workspace.viewer.webView, isVisible: tab.mode == .read)
                HostedView(view: workspace.editor.scrollView, isVisible: tab.mode == .edit)
                if workspace.find.isVisible {
                    FindBar(workspace: workspace, find: workspace.find)
                        .padding(.top, workspace.focusMode ? 34 : 10)
                        .padding(.trailing, 16)
                }
            }
            if !workspace.focusMode {
                Divider()
                StatusBar(workspace: workspace, tab: tab, status: workspace.status)
            }
        }
    }
}

/// 既存の NSView を SwiftUI に載せる。1 つのビューを使い回し、切替では隠すだけにする
struct HostedView: NSViewRepresentable {
    let view: NSView
    let isVisible: Bool

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        view.frame = container.bounds
        view.autoresizingMask = [.width, .height]
        container.addSubview(view)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        if view.superview !== container {
            view.frame = container.bounds
            container.addSubview(view)
        }
        if view.isHidden == isVisible { view.isHidden = !isVisible }
        container.isHidden = !isVisible
    }
}

// MARK: - 共通の小物

/// ウィンドウの背景に透ける素材
struct VisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
    }
}

/// カーソルを載せると背景が付く、アイコンだけのボタン
struct IconButton: View {
    let systemName: String
    var help: String = ""
    var isOn: Bool = false
    var isEnabled: Bool = true
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                .frame(width: 26, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovering && isEnabled ? Color.primary.opacity(0.08) : (isOn ? Color.accentColor.opacity(0.12) : Color.clear))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .onHover { isHovering = $0 }
        .help(help)
    }
}

/// 集中モードを抜けるボタン（カーソルを載せたときだけ見える）
private struct FocusExitButton: View {
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Label("集中モードを終了", systemImage: "arrow.down.right.and.arrow.up.left")
                .font(.system(size: 11))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.regularMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .opacity(isHovering ? 1 : 0.02)
        .onHover { isHovering = $0 }
        .padding(.top, 8)
        .padding(.trailing, 12)
    }
}

// MARK: - バナー

private struct ExternalChangeBanner: View {
    @ObservedObject var workspace: WorkspaceModel
    let tab: DocumentTab

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text("このファイルは他のアプリで変更されました。").font(.callout)
            Spacer()
            Button("ディスクの内容を読み込む") { workspace.reloadFromDisk(tab) }
            Button("自分の変更で上書き") { workspace.keepMyVersion(tab) }
        }
        .controlSize(.small)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Color.orange.opacity(0.1))
    }
}

private struct MissingFileBanner: View {
    @ObservedObject var workspace: WorkspaceModel
    let tab: DocumentTab

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "questionmark.folder.fill").foregroundStyle(.secondary)
            Text("ファイルが移動または削除されました。").font(.callout)
            Spacer()
            Button("別名で保存…") { workspace.saveActiveAs() }
            Button("タブを閉じる") {
                tab.setUntrackedClean()
                workspace.close(tab)
            }
        }
        .controlSize(.small)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Color.secondary.opacity(0.1))
    }
}

// MARK: - ステータスバー

struct StatusBar: View {
    let workspace: WorkspaceModel
    @ObservedObject var tab: DocumentTab
    @ObservedObject var status: ReadingStatus

    var body: some View {
        HStack(spacing: 14) {
            if tab.kind == .image {
                if let size = tab.imageSize {
                    Text("\(Int(size.width)) × \(Int(size.height)) px")
                }
            } else if tab.mode == .read {
                Text("\(tab.characterCount) 字")
                Text("約 \(tab.readingMinutes) 分")
            } else {
                Text("\(status.cursorLine) 行 \(status.cursorColumn) 列")
                Text("\(tab.characterCount) 字")
            }
            Spacer()
            if tab.kind == .markdown {
                if tab.mode == .edit {
                    Text(TextFile.encodingName(tab.encoding))
                    Text(tab.lineEnding.rawValue)
                    if tab.isDirty {
                        Text(AppSettings.shared.autosave && tab.url != nil ? "保存待ち" : "未保存")
                            .foregroundStyle(.orange)
                    }
                } else {
                    Text("\(Int((status.progress * 100).rounded()))%")
                        .monospacedDigit()
                }
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .frame(height: 24)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - ようこそ画面

struct WelcomeView: View {
    let workspace: WorkspaceModel

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 6) {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Color.accentColor.opacity(0.75))
                Text("Shiori")
                    .font(.system(size: 22, weight: .semibold))
                Text("Finder の Markdown をそのまま読み、そのまま書く")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Button("ファイルかフォルダを開く…") { openPanel() }
                    .keyboardShortcut(.defaultAction)
                Button("新規タブ") { workspace.newUntitledTab() }
            }
            let folders = RecentItems.folders.prefix(5)
            if !folders.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("最近開いたフォルダ").font(.caption).foregroundStyle(.secondary)
                    ForEach(Array(folders), id: \.self) { url in
                        Button {
                            workspace.setRoot(url)
                        } label: {
                            Label(url.lastPathComponent, systemImage: "folder")
                                .font(.callout)
                        }
                        .buttonStyle(.link)
                        .help(url.path)
                    }
                }
            }
        }
        .padding(40)
    }

    private func openPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        workspace.open(url, newTab: true)
    }
}

// MARK: - 検索バー

struct FindBar: View {
    let workspace: WorkspaceModel
    @ObservedObject var find: FindState
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.system(size: 12))
            TextField("本文を検索", text: $find.query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .frame(width: 180)
                .focused($isFocused)
                .onSubmit { workspace.findNext(NSEvent.modifierFlags.contains(.shift) ? -1 : 1) }
                .onChange(of: find.query) { _, _ in workspace.runFind() }
                .onExitCommand { workspace.hideFind() }
            Text(find.query.isEmpty ? "" : (find.count == 0 ? "0 件" : "\(find.index + 1) / \(find.count)"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            IconButton(systemName: "chevron.up", help: "前を検索") { workspace.findNext(-1) }
            IconButton(systemName: "chevron.down", help: "次を検索") { workspace.findNext(1) }
            IconButton(systemName: "xmark", help: "閉じる") { workspace.hideFind() }
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.primary.opacity(0.1)))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        .onAppear { isFocused = true }
        .onChange(of: find.focusRequest) { _, _ in isFocused = true }
    }
}
