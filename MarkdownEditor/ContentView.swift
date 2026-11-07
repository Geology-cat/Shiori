import SwiftUI
import UniformTypeIdentifiers

enum ViewMode: String, CaseIterable, Identifiable {
    case split
    case previewOnly
    var id: String { rawValue }
}

struct ContentView: View {
    @Binding var document: MarkdownDocument
    @State private var viewMode: ViewMode = .split
    @State private var showingTableSheet = false
    @State private var isExporting = false
    @StateObject private var bridge = EditorBridge()

    var body: some View {
        Group {
            switch viewMode {
            case .split:
                HSplitView {
                    SourceEditor(text: $document.text, bridge: bridge)
                        .frame(minWidth: 240)
                    PreviewView(text: document.text)
                        .frame(minWidth: 240)
                }
            case .previewOnly:
                PreviewView(text: document.text)
                    .frame(minWidth: 320)
            }
        }
        .frame(minWidth: 700, minHeight: 420)
        .overlay {
            if isExporting {
                // エクスポート中のオーバーレイ
                ZStack {
                    Color.black.opacity(0.3)
                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.large)
                        Text("PDF を生成しています…")
                            .font(.headline)
                            .foregroundStyle(.white)
                    }
                    .padding(24)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .toolbar {
            // 表示モード切替
            ToolbarItem(placement: .navigation) {
                Picker("表示", selection: $viewMode) {
                    Image(systemName: "square.split.2x1").tag(ViewMode.split)
                    Image(systemName: "eye").tag(ViewMode.previewOnly)
                }
                .pickerStyle(.segmented)
                .help("表示モード (分割 / プレビューのみ)")
            }
            // 記法挿入ボタン群 (split のときだけ表示)
            if viewMode == .split {
                ToolbarItemGroup(placement: .primaryAction) {
                    MarkdownToolbar(bridge: bridge, showingTableSheet: $showingTableSheet)
                }
            }
            
            // エクスポートボタン
            ToolbarItemGroup(placement: .primaryAction) {
                Button { exportHTML() } label: {
                    Label("HTML", systemImage: "doc.text")
                }
                .help("HTMLとして書き出す")
                
                Button { exportPDF() } label: {
                    Label("PDF", systemImage: "doc.richtext")
                }
                .help("PDFとして書き出す")
            }
        }
        .sheet(isPresented: $showingTableSheet) {
            TableInsertSheet(bridge: bridge, isPresented: $showingTableSheet)
        }
        .onReceive(NotificationCenter.default.publisher(for: .exportPDF)) { _ in
            exportPDF()
        }
        .onReceive(NotificationCenter.default.publisher(for: .exportHTML)) { _ in
            exportHTML()
        }
    }

    // MARK: - PDF エクスポート

    private func exportPDF() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "document.pdf"
        panel.canCreateDirectories = true
        panel.title = "PDFとして書き出す"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        isExporting = true
        PDFExporter.export(markdown: document.text, to: url) { error in
            DispatchQueue.main.async {
                isExporting = false
                if let error = error {
                    let alert = NSAlert()
                    alert.messageText = "PDFの書き出しに失敗しました"
                    alert.informativeText = error.localizedDescription
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
            }
        }
    }

    // MARK: - HTML エクスポート

    private func exportHTML() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = "document.html"
        panel.canCreateDirectories = true
        panel.title = "HTMLとして書き出す"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        if let error = HTMLExporter.export(markdown: document.text, to: url) {
            let alert = NSAlert()
            alert.messageText = "HTMLの書き出しに失敗しました"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
}
