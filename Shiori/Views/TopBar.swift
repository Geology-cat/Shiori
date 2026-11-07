import SwiftUI
import UniformTypeIdentifiers

/// 上部バー: サイドバー切替、タブ、閲覧/編集の切替、表示設定
struct TopBar: View {
    @ObservedObject var workspace: WorkspaceModel
    @State private var showingOptions = false

    /// サイドバーを隠したときは信号ボタンのぶんだけ空ける
    private var leadingInset: CGFloat { workspace.sidebarVisible ? 8 : 84 }

    var body: some View {
        HStack(spacing: 6) {
            if !workspace.sidebarVisible {
                IconButton(systemName: "sidebar.left", help: "サイドバーを表示 (⌘\\)") { workspace.sidebarVisible = true }
            }
            TabStrip(workspace: workspace)
            if let tab = workspace.activeTab {
                TabControls(workspace: workspace, tab: tab, showingOptions: $showingOptions)
            }
        }
        .padding(.leading, leadingInset)
        .padding(.trailing, 10)
        .frame(height: 32)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct TabControls: View {
    @ObservedObject var workspace: WorkspaceModel
    @ObservedObject var tab: DocumentTab
    @Binding var showingOptions: Bool

    var body: some View {
        HStack(spacing: 6) {
            if tab.kind == .markdown {
                ModeSwitch(mode: tab.mode) { workspace.setMode($0) }
            }
            IconButton(systemName: "textformat.size", help: "表示の設定", isOn: showingOptions) {
                showingOptions.toggle()
            }
            .popover(isPresented: $showingOptions, arrowEdge: .bottom) {
                ReadingOptionsView(workspace: workspace, settings: AppSettings.shared, themes: ThemeManager.shared)
            }
        }
    }
}

/// 閲覧と編集を切り替えるボタン（Obsidian の切替に相当）
private struct ModeSwitch: View {
    let mode: DocMode
    let onChange: (DocMode) -> Void

    var body: some View {
        HStack(spacing: 0) {
            segment(.read, icon: "book")
            segment(.edit, icon: "pencil")
        }
        .padding(2)
        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 7))
        .help("閲覧 / 編集を切り替え (⌘E)")
    }

    private func segment(_ target: DocMode, icon: String) -> some View {
        Button {
            onChange(target)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 11, weight: .medium))
                Text(target.label).font(.system(size: 12))
            }
            .foregroundStyle(mode == target ? Color.primary : Color.secondary)
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(mode == target ? Color(nsColor: .controlBackgroundColor) : Color.clear)
                    .shadow(color: .black.opacity(mode == target ? 0.12 : 0), radius: 1, y: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - タブ

private struct TabStrip: View {
    @ObservedObject var workspace: WorkspaceModel
    @State private var draggingID: UUID?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(workspace.tabs) { tab in
                    TabItem(workspace: workspace, tab: tab, isActive: tab.id == workspace.activeTabID)
                        .onDrag {
                            draggingID = tab.id
                            return NSItemProvider(object: tab.id.uuidString as NSString)
                        }
                        .onDrop(of: [.text], delegate: TabDropDelegate(workspace: workspace, target: tab, draggingID: $draggingID))
                }
                IconButton(systemName: "plus", help: "新規タブ (⌘N)") { workspace.newUntitledTab() }
            }
            .padding(.vertical, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TabDropDelegate: DropDelegate {
    let workspace: WorkspaceModel
    let target: DocumentTab
    @Binding var draggingID: UUID?

    func dropEntered(info: DropInfo) {
        guard let draggingID, draggingID != target.id,
              let from = workspace.tabs.firstIndex(where: { $0.id == draggingID }),
              let to = workspace.tabs.firstIndex(where: { $0.id == target.id }) else { return }
        workspace.moveTab(from: from, to: to > from ? to + 1 : to)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        draggingID = nil
        return true
    }
}

private struct TabItem: View {
    let workspace: WorkspaceModel
    @ObservedObject var tab: DocumentTab
    let isActive: Bool
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: tab.kind == .image ? "photo" : "doc.text")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(tab.title)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(isActive ? Color.primary : Color.secondary)
            closeButton
        }
        .padding(.leading, 9)
        .padding(.trailing, 4)
        .frame(height: 26)
        .frame(minWidth: 90, maxWidth: 200)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isActive ? Color.primary.opacity(0.09) : (isHovering ? Color.primary.opacity(0.05) : Color.clear))
        )
        .contentShape(Rectangle())
        .onTapGesture { workspace.activate(tab) }
        .onHover { isHovering = $0 }
        .help(tab.url?.path ?? tab.title)
        .contextMenu {
            Button("タブを閉じる") { workspace.close(tab) }
            Button("他のタブを閉じる") {
                for other in workspace.tabs where other.id != tab.id { workspace.close(other) }
            }
            if let url = tab.url {
                Divider()
                Button("Finder で表示") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                Button("パスをコピー") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.path, forType: .string)
                }
            }
        }
    }

    private var closeButton: some View {
        Button {
            workspace.close(tab)
        } label: {
            ZStack {
                if tab.isDirty && !isHovering {
                    Circle().fill(Color.secondary).frame(width: 6, height: 6)
                } else {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .opacity(isHovering || isActive ? 1 : 0)
                }
            }
            .frame(width: 16, height: 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("タブを閉じる (⌘W)")
    }
}

// MARK: - 書式バー（編集モードのみ）

struct FormatBar: View {
    let editor: EditorController
    @State private var showingTable = false

    var body: some View {
        HStack(spacing: 1) {
            Menu {
                ForEach(1...6, id: \.self) { level in
                    Button("見出し \(level)") { editor.setHeading(level: level) }
                }
                Divider()
                Button("本文に戻す") { editor.setHeading(level: 0) }
            } label: {
                Image(systemName: "number")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 26, height: 24)
            .help("見出し")

            IconButton(systemName: "bold", help: "太字 (⌘B)") { editor.toggleWrap(prefix: "**", suffix: "**", placeholder: "太字") }
            IconButton(systemName: "italic", help: "斜体 (⌘I)") { editor.toggleWrap(prefix: "*", suffix: "*", placeholder: "斜体") }
            IconButton(systemName: "strikethrough", help: "取り消し線") { editor.toggleWrap(prefix: "~~", suffix: "~~", placeholder: "取り消し線") }
            IconButton(systemName: "highlighter", help: "マーカー") { editor.toggleWrap(prefix: "==", suffix: "==", placeholder: "マーカー") }
            separator
            IconButton(systemName: "link", help: "リンク (⌘K)") { editor.toggleWrap(prefix: "[", suffix: "](url)", placeholder: "リンク") }
            IconButton(systemName: "photo", help: "画像") { editor.toggleWrap(prefix: "![", suffix: "](path)", placeholder: "説明") }
            IconButton(systemName: "chevron.left.forwardslash.chevron.right", help: "インラインコード") { editor.toggleWrap(prefix: "`", suffix: "`", placeholder: "code") }
            IconButton(systemName: "curlybraces", help: "コードブロック") { editor.insertBlock("```\n\n```", cursorOffset: 4) }
            IconButton(systemName: "function", help: "数式") { editor.toggleWrap(prefix: "$", suffix: "$", placeholder: "x^2") }
            separator
            IconButton(systemName: "list.bullet", help: "箇条書き") { editor.toggleLinePrefix("- ") }
            IconButton(systemName: "list.number", help: "番号付きリスト") { editor.toggleLinePrefix("1. ") }
            IconButton(systemName: "checklist", help: "タスク") { editor.toggleLinePrefix("- [ ] ") }
            IconButton(systemName: "text.quote", help: "引用") { editor.toggleLinePrefix("> ") }
            IconButton(systemName: "tablecells", help: "表を挿入") { showingTable = true }
                .popover(isPresented: $showingTable) {
                    TableInsertView(editor: editor, isPresented: $showingTable)
                }
            IconButton(systemName: "minus", help: "水平線") { editor.insertBlock("---") }
            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var separator: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: 1, height: 14)
            .padding(.horizontal, 5)
    }
}

private struct TableInsertView: View {
    let editor: EditorController
    @Binding var isPresented: Bool
    @State private var rows = 3
    @State private var columns = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Stepper("本文の行数: \(rows)", value: $rows, in: 1...50)
            Stepper("列数: \(columns)", value: $columns, in: 1...20)
            HStack {
                Spacer()
                Button("キャンセル") { isPresented = false }
                Button("挿入") {
                    editor.insertBlock(MarkdownEditing.tableTemplate(rows: rows, columns: columns))
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .frame(width: 240)
    }
}
