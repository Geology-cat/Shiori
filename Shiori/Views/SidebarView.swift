import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 左のサイドパネル: ファイラーと目次
struct SidebarView: View {
    @ObservedObject var workspace: WorkspaceModel
    @ObservedObject var tree: FileTreeModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Group {
                switch workspace.sidebarPanel {
                case .files: FilesPanel(workspace: workspace, tree: tree)
                case .outline: OutlinePanel(workspace: workspace, status: workspace.status)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(VisualEffect(material: .sidebar))
    }

    private var header: some View {
        HStack(spacing: 4) {
            // 信号ボタンのぶんを空ける
            Spacer().frame(width: 72)
            Spacer()
            IconButton(systemName: "folder", help: "ファイル (⌥⌘1)", isOn: workspace.sidebarPanel == .files) {
                workspace.sidebarPanel = .files
            }
            IconButton(systemName: "list.bullet.indent", help: "目次 (⌥⌘2)", isOn: workspace.sidebarPanel == .outline) {
                workspace.sidebarPanel = .outline
            }
            IconButton(systemName: "sidebar.left", help: "サイドバーを隠す (⌘\\)") {
                workspace.sidebarVisible = false
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 32)
    }
}

// MARK: - ファイラー

private struct FilesPanel: View {
    @ObservedObject var workspace: WorkspaceModel
    @ObservedObject var tree: FileTreeModel
    @FocusState private var filterFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if workspace.rootURL != nil {
                filterField
                if workspace.filterText.isEmpty {
                    treeList
                } else {
                    FilterResults(workspace: workspace, query: workspace.filterText)
                }
                Divider()
                RootBar(workspace: workspace)
            } else {
                noFolder
            }
        }
    }

    private var filterField: some View {
        HStack(spacing: 5) {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            TextField("ファイル名で絞り込み", text: $workspace.filterText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($filterFocused)
                .onExitCommand { workspace.filterText = "" }
            if !workspace.filterText.isEmpty {
                Button {
                    workspace.filterText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 11)).foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }

    private var treeList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(tree.rows) { row in
                    FileRowView(
                        workspace: workspace,
                        tree: tree,
                        row: row,
                        isActive: workspace.activeTab?.url?.standardizedFileURL == row.url.standardizedFileURL
                    )
                }
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 8)
        }
        .contextMenu {
            if let root = workspace.rootURL { DirectoryMenu(workspace: workspace, directory: root) }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let root = workspace.rootURL else { return false }
            return moveDropped(providers, into: root, workspace: workspace)
        }
    }

    private var noFolder: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "folder")
                .font(.system(size: 24))
                .foregroundStyle(.tertiary)
            Button("フォルダを開く…") {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                if panel.runModal() == .OK, let url = panel.url { workspace.setRoot(url) }
            }
            .controlSize(.small)
            Spacer()
        }
    }
}

/// ドロップされた項目をフォルダへ移動する（Finder からのドロップも移動扱い）
private func moveDropped(_ providers: [NSItemProvider], into directory: URL, workspace: WorkspaceModel) -> Bool {
    var handled = false
    for provider in providers where provider.canLoadObject(ofClass: URL.self) {
        handled = true
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            DispatchQueue.main.async {
                let destination = directory.appendingPathComponent(url.lastPathComponent)
                guard url.deletingLastPathComponent().standardizedFileURL != directory.standardizedFileURL else { return }
                workspace.move(url, to: destination)
            }
        }
    }
    return handled
}

private struct FileRowView: View {
    let workspace: WorkspaceModel
    let tree: FileTreeModel
    let row: FileRow
    let isActive: Bool
    @State private var isHovering = false
    @State private var isDropTarget = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(row.isExpanded ? 90 : 0))
                .opacity(row.isDirectory ? 1 : 0)
                .frame(width: 10)
            Image(systemName: iconName)
                .font(.system(size: 11))
                .foregroundStyle(row.isDirectory ? Color.accentColor.opacity(0.85) : Color.secondary)
                .frame(width: 16)
            Text(displayName)
                .font(.system(size: 12.5))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.leading, CGFloat(row.depth) * 13 + 4)
        .padding(.trailing, 4)
        .frame(height: 24)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(background)
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .gesture(TapGesture().modifiers(.command).onEnded { open(alternate: true) })
        .onTapGesture { open(alternate: false) }
        .help(row.name)
        .contextMenu { menu }
        .onDrag { NSItemProvider(object: row.url as NSURL) }
        .modifier(DirectoryDropTarget(isDirectory: row.isDirectory, isTargeted: $isDropTarget) { providers in
            moveDropped(providers, into: row.url, workspace: workspace)
        })
    }

    private var background: Color {
        if isDropTarget { return Color.accentColor.opacity(0.25) }
        if isActive { return Color.primary.opacity(0.11) }
        if isHovering { return Color.primary.opacity(0.05) }
        return .clear
    }

    private var iconName: String {
        if row.isDirectory { return row.isExpanded ? "folder.fill" : "folder" }
        return FileKinds.isImage(row.url) ? "photo" : "doc.text"
    }

    /// Markdown の拡張子は見せない（Obsidian と同じ）
    private var displayName: String {
        FileKinds.isMarkdown(row.url) ? row.url.deletingPathExtension().lastPathComponent : row.name
    }

    private func open(alternate: Bool) {
        if row.isDirectory {
            tree.toggle(row)
        } else {
            workspace.openFromFiler(row.url, alternate: alternate)
        }
    }


    @ViewBuilder
    private var menu: some View {
        if row.isDirectory {
            DirectoryMenu(workspace: workspace, directory: row.url)
            Divider()
            Button("このフォルダをルートにする") { workspace.setRoot(row.url) }
        } else {
            Button("今のタブで開く") { workspace.open(row.url, newTab: false) }
            Button("新しいタブで開く") { workspace.open(row.url, newTab: true) }
            Button("新規ファイル…") { workspace.createFile(in: row.url.deletingLastPathComponent()) }
        }
        Divider()
        Button("名前を変更…") { workspace.rename(row.url) }
        Button("ゴミ箱に入れる") { workspace.moveToTrash(row.url) }
        Divider()
        Button("Finder で表示") { NSWorkspace.shared.activateFileViewerSelecting([row.url]) }
        Button("パスをコピー") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(row.url.path, forType: .string)
        }
    }
}

/// フォルダの行にだけドロップ先を付ける
private struct DirectoryDropTarget: ViewModifier {
    let isDirectory: Bool
    @Binding var isTargeted: Bool
    let perform: ([NSItemProvider]) -> Bool

    func body(content: Content) -> some View {
        if isDirectory {
            content.onDrop(of: [.fileURL], isTargeted: $isTargeted, perform: perform)
        } else {
            content
        }
    }
}

private struct DirectoryMenu: View {
    let workspace: WorkspaceModel
    let directory: URL

    var body: some View {
        Button("新規ファイル…") { workspace.createFile(in: directory) }
        Button("新規フォルダ…") { workspace.createFolder(in: directory) }
    }
}

/// 絞り込みの結果
private struct FilterResults: View {
    let workspace: WorkspaceModel
    let query: String

    var body: some View {
        let results = workspace.index.search(query, limit: 200)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(results, id: \.self) { url in
                    FilterResultRow(workspace: workspace, url: url)
                }
                if results.isEmpty {
                    Text("見つかりません")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(12)
                }
            }
            .padding(.horizontal, 6)
        }
    }
}

private struct FilterResultRow: View {
    let workspace: WorkspaceModel
    let url: URL
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(url.lastPathComponent)
                .font(.system(size: 12.5))
                .lineLimit(1)
            Text(relativeDirectory)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 5).fill(isHovering ? Color.primary.opacity(0.05) : .clear))
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture { workspace.openFromFiler(url, alternate: NSEvent.modifierFlags.contains(.command)) }
    }

    private var relativeDirectory: String {
        guard let root = workspace.rootURL else { return url.deletingLastPathComponent().path }
        let relative = MarkdownEditing.relativePath(from: root, to: url.deletingLastPathComponent())
        return relative.isEmpty ? "/" : relative
    }
}

/// ファイラー下部: 今のルートフォルダと切替メニュー
private struct RootBar: View {
    @ObservedObject var workspace: WorkspaceModel

    var body: some View {
        HStack(spacing: 2) {
            IconButton(systemName: "arrow.up", help: "親フォルダへ") { workspace.goToParentFolder() }
            Menu {
                Button("フォルダを開く…") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.directoryURL = workspace.rootURL
                    if panel.runModal() == .OK, let url = panel.url { workspace.setRoot(url) }
                }
                let folders = RecentItems.folders
                if !folders.isEmpty {
                    Divider()
                    ForEach(folders, id: \.self) { url in
                        Button(url.path(percentEncoded: false)) { workspace.setRoot(url) }
                    }
                }
                if let root = workspace.rootURL {
                    Divider()
                    Button("Finder で表示") { NSWorkspace.shared.activateFileViewerSelecting([root]) }
                }
            } label: {
                Text(workspace.rootURL?.lastPathComponent ?? "")
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .menuStyle(.borderlessButton)
            .help(workspace.rootURL?.path ?? "")
            Spacer(minLength: 0)
            if let root = workspace.rootURL {
                IconButton(systemName: "plus", help: "新規ファイル") { workspace.createFile(in: root) }
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 30)
    }
}

// MARK: - 目次

private struct OutlinePanel: View {
    @ObservedObject var workspace: WorkspaceModel
    @ObservedObject var status: ReadingStatus

    var body: some View {
        if workspace.outline.isEmpty {
            VStack {
                Spacer()
                Text(workspace.activeTab == nil ? "文書を開いていません" : "見出しがありません")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
            }
        } else {
            let current = workspace.currentOutlineItem(topLine: status.topLine)
            let minLevel = workspace.outline.map(\.level).min() ?? 1
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(workspace.outline) { item in
                            OutlineRow(item: item, minLevel: minLevel, isCurrent: item.id == current?.id) {
                                workspace.scrollToOutlineItem(item)
                            }
                            .id(item.id)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 10)
                }
                .onChange(of: current?.id) { _, id in
                    guard let id else { return }
                    withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id, anchor: .center) }
                }
            }
        }
    }
}

private struct OutlineRow: View {
    let item: OutlineItem
    let minLevel: Int
    let isCurrent: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Text(item.title)
            .font(.system(size: 12.5, weight: item.level == minLevel ? .medium : .regular))
            .foregroundStyle(isCurrent ? Color.accentColor : Color.primary.opacity(item.level > minLevel + 1 ? 0.7 : 0.9))
            .lineLimit(2)
            .padding(.leading, CGFloat(item.level - minLevel) * 13 + 8)
            .padding(.trailing, 6)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 5).fill(isHovering ? Color.primary.opacity(0.05) : .clear))
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .onTapGesture(perform: action)
    }
}
