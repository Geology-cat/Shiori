import SwiftUI

/// 編集ツールバー本体。`ContentView` の `.toolbar` 内から呼ばれる。
struct MarkdownToolbar: View {
    let bridge: EditorBridge
    @Binding var showingTableSheet: Bool
    @AppStorage("editorFontSize") var editorFontSize: Double = 14.0

    var body: some View {
        Group {
            // フォントサイズ変更
            Button { editorFontSize = max(editorFontSize - 2, 8) } label: { Image(systemName: "textformat.size.smaller") }
            .help("フォントサイズを小さく")
            Button { editorFontSize = min(editorFontSize + 2, 48) } label: { Image(systemName: "textformat.size.larger") }
            .help("フォントサイズを大きく")

            Divider()

            // 見出し
            Menu {
                Button("見出し 1") { bridge.prefixLines("# ") }
                Button("見出し 2") { bridge.prefixLines("## ") }
                Button("見出し 3") { bridge.prefixLines("### ") }
                Button("見出し 4") { bridge.prefixLines("#### ") }
            } label: {
                Image(systemName: "textformat.size")
            }
            .help("見出し")

            // 太字
            Button { bridge.wrapSelection(prefix: "**", suffix: "**", placeholder: "太字") } label: {
                Image(systemName: "bold")
            }
            .help("太字")

            // 斜体
            Button { bridge.wrapSelection(prefix: "*", suffix: "*", placeholder: "斜体") } label: {
                Image(systemName: "italic")
            }
            .help("斜体")

            // 取り消し線
            Button { bridge.wrapSelection(prefix: "~~", suffix: "~~", placeholder: "取り消し") } label: {
                Image(systemName: "strikethrough")
            }
            .help("取り消し線")

            // インラインコード
            Button { bridge.wrapSelection(prefix: "`", suffix: "`", placeholder: "code") } label: {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
            }
            .help("インラインコード")

            // コードブロック
            Button {
                bridge.insertBlock("```\n\n```")
                // フェンス内側 (1 行下) にキャレットを置く
            } label: {
                Image(systemName: "curlybraces")
            }
            .help("コードブロック")

            // リンク
            Button {
                bridge.wrapSelection(prefix: "[", suffix: "](url)", placeholder: "リンクテキスト")
            } label: {
                Image(systemName: "link")
            }
            .help("リンク")

            // 画像
            Button {
                bridge.wrapSelection(prefix: "![", suffix: "](url)", placeholder: "alt")
            } label: {
                Image(systemName: "photo")
            }
            .help("画像")

            // 引用
            Button { bridge.prefixLines("> ") } label: {
                Image(systemName: "text.quote")
            }
            .help("引用")

            // 箇条書き
            Button { bridge.prefixLines("- ") } label: {
                Image(systemName: "list.bullet")
            }
            .help("箇条書き")

            // 番号付きリスト
            Button { bridge.prefixLines("1. ") } label: {
                Image(systemName: "list.number")
            }
            .help("番号付きリスト")

            // タスクリスト
            Button { bridge.prefixLines("- [ ] ") } label: {
                Image(systemName: "checklist")
            }
            .help("タスクリスト")

            // 水平線
            Button { bridge.insertBlock("---") } label: {
                Image(systemName: "minus")
            }
            .help("水平線")

            // 表
            Button { showingTableSheet = true } label: {
                Image(systemName: "tablecells")
            }
            .help("表を挿入…")
        }
    }
}

/// 行数 / 列数を指定して md の表テンプレートを挿入するシート。
struct TableInsertSheet: View {
    let bridge: EditorBridge
    @Binding var isPresented: Bool

    @State private var rows: Int = 3
    @State private var cols: Int = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("表を挿入")
                .font(.headline)

            HStack {
                Text("行数 (本文):")
                Stepper(value: $rows, in: 1...50) {
                    Text("\(rows)")
                        .frame(minWidth: 32, alignment: .trailing)
                        .monospacedDigit()
                }
            }
            HStack {
                Text("列数:")
                Stepper(value: $cols, in: 1...20) {
                    Text("\(cols)")
                        .frame(minWidth: 32, alignment: .trailing)
                        .monospacedDigit()
                }
            }

            Text("プレビュー").font(.subheadline).foregroundStyle(.secondary)
            ScrollView([.horizontal]) {
                Text(buildTable())
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(6)
            }
            .frame(maxHeight: 140)

            HStack {
                Spacer()
                Button("キャンセル", role: .cancel) { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button("挿入") {
                    bridge.insertBlock(buildTable())
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 360)
    }

    private func buildTable() -> String {
        let header = (1...cols).map { "列\($0)" }
        let sep = Array(repeating: "---", count: cols)
        let empty = Array(repeating: "    ", count: cols)
        var lines: [String] = []
        lines.append("| " + header.joined(separator: " | ") + " |")
        lines.append("| " + sep.joined(separator: " | ") + " |")
        for _ in 0..<rows {
            lines.append("| " + empty.joined(separator: " | ") + " |")
        }
        return lines.joined(separator: "\n")
    }
}
