import SwiftUI

/// ファイル名を入力して素早く開く（⌘⇧P）
struct QuickOpenOverlay: View {
    let workspace: WorkspaceModel
    @State private var query = ""
    @State private var selection = 0
    @FocusState private var isFocused: Bool

    private var results: [URL] { workspace.index.search(query, limit: 30) }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.12)
                .ignoresSafeArea()
                .onTapGesture { close() }
            VStack(spacing: 0) {
                TextField("ファイル名を入力", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .focused($isFocused)
                    .onChange(of: query) { _, _ in selection = 0 }
                    .onSubmit { openSelection() }
                    .onKeyPress(.upArrow) { move(-1); return .handled }
                    .onKeyPress(.downArrow) { move(1); return .handled }
                    .onExitCommand { close() }
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(results.enumerated()), id: \.element) { index, url in
                                row(url, isSelected: index == selection)
                                    .id(index)
                                    .onTapGesture {
                                        selection = index
                                        openSelection()
                                    }
                            }
                        }
                        .padding(5)
                    }
                    .frame(maxHeight: 340)
                    .onChange(of: selection) { _, value in proxy.scrollTo(value) }
                }
                if results.isEmpty {
                    Text(workspace.rootURL == nil ? "フォルダを開くと使えます" : "見つかりません")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(14)
                }
            }
            .frame(width: 480)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.primary.opacity(0.1)))
            .shadow(color: .black.opacity(0.25), radius: 20, y: 6)
            .padding(.top, 72)
        }
        .onAppear { isFocused = true }
    }

    private func row(_ url: URL, isSelected: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: FileKinds.isImage(url) ? "photo" : "doc.text")
                .font(.system(size: 11))
                .foregroundStyle(isSelected ? Color.white : Color.secondary)
            Text(url.lastPathComponent)
                .font(.system(size: 13))
                .lineLimit(1)
            Text(relativeDirectory(url))
                .font(.system(size: 11))
                .foregroundStyle(isSelected ? Color.white.opacity(0.75) : Color.secondary)
                .lineLimit(1)
                .truncationMode(.head)
            Spacer(minLength: 0)
        }
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6).fill(isSelected ? Color.accentColor : .clear))
        .contentShape(Rectangle())
    }

    private func relativeDirectory(_ url: URL) -> String {
        guard let root = workspace.rootURL else { return "" }
        return MarkdownEditing.relativePath(from: root, to: url.deletingLastPathComponent())
    }

    private func move(_ delta: Int) {
        let count = results.count
        guard count > 0 else { return }
        selection = (selection + delta + count) % count
    }

    private func openSelection() {
        let list = results
        guard list.indices.contains(selection) else { return }
        let url = list[selection]
        close()
        workspace.open(url, newTab: NSEvent.modifierFlags.contains(.command))
    }

    private func close() {
        workspace.quickOpenVisible = false
    }
}
