import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum SettingsWindow {
    static func make() -> NSWindow {
        let hosting = NSHostingController(rootView: SettingsView(settings: AppSettings.shared, themes: ThemeManager.shared))
        let window = NSWindow(contentViewController: hosting)
        window.title = "環境設定"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 520, height: 440))
        return window
    }
}

/// 環境設定（⌘,）
struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var themes: ThemeManager

    var body: some View {
        TabView {
            GeneralTab(settings: settings)
                .tabItem { Label("一般", systemImage: "gearshape") }
            ViewerTab(settings: settings, themes: themes)
                .tabItem { Label("ビューワー", systemImage: "book") }
            ThemesTab(settings: settings, themes: themes)
                .tabItem { Label("テーマ", systemImage: "paintpalette") }
            EditorTab(settings: settings)
                .tabItem { Label("エディタ", systemImage: "pencil") }
        }
        .padding(16)
        .frame(width: 520, height: 440)
    }
}

private struct GeneralTab: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Picker("Markdown を開いたとき", selection: $settings.defaultOpenMode) {
                Text("閲覧モードで開く").tag(DocMode.read)
                Text("編集モードで開く").tag(DocMode.edit)
            }
            Picker("外観", selection: $settings.appearance) {
                ForEach(AppearanceChoice.allCases) { Text($0.label).tag($0) }
            }
            Section {
                Toggle("自動で保存する", isOn: $settings.autosave)
                Toggle("起動時に前回の状態を復元する", isOn: $settings.restoreSession)
            }
            Section("ファイラー") {
                Toggle("隠しファイルも表示する", isOn: $settings.showHiddenFiles)
                Text("フォルダ、Markdown、画像だけを表示します。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct ViewerTab: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var themes: ThemeManager

    var body: some View {
        Form {
            Picker("既定のテーマ", selection: $settings.themeID) {
                ForEach(themes.allThemes) { Text($0.name).tag($0.id) }
            }
            Picker("既定の組方向", selection: $settings.writing) {
                ForEach(WritingMode.allCases) { Text($0.label).tag($0) }
            }
            LabeledContent("文字サイズ") {
                HStack {
                    Slider(value: $settings.fontScale, in: 0.5...3.0, step: 0.1)
                    Text("\(Int((settings.fontScale * 100).rounded()))%")
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }
            }
            Section("表示") {
                Toggle("改行をそのまま改行として表示する", isOn: $settings.breaks)
                Toggle("フロントマターのプロパティを表示する", isOn: $settings.showProperties)
                Toggle("画面の端をクリックしてページ送りする", isOn: $settings.clickToPage)
            }
        }
        .formStyle(.grouped)
    }
}

private struct ThemesTab: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var themes: ThemeManager

    var body: some View {
        Form {
            Section("自前の CSS テーマ") {
                if themes.userThemes.isEmpty {
                    Text("まだありません。CSS を読み込むか、雛形から作成できます。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(themes.userThemes) { theme in
                        HStack {
                            Text(theme.name)
                            Spacer()
                            if settings.themeID == theme.id {
                                Text("使用中").font(.caption).foregroundStyle(.secondary)
                            } else {
                                Button("使う") { settings.themeID = theme.id }.controlSize(.small)
                            }
                        }
                    }
                }
                HStack {
                    Button("CSS を読み込む…") { importCSS() }
                    Button("雛形から作成") { createTemplate() }
                    Button("フォルダを開く") { themes.revealThemesFolder() }
                }
                Text("テーマのフォルダに置いた .css は自動で一覧に追加され、保存するとすぐ反映されます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("追加の CSS") {
                Toggle("どのテーマにも custom.css を重ねる", isOn: $settings.useCustomCSS)
                Button("custom.css を編集") { editCustomCSS() }
                Text("見出しの色だけ変えたい、といった小さな調整に使えます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func importCSS() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "css") ?? .plainText]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            settings.themeID = try themes.importCSS(from: url)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private func createTemplate() {
        do {
            let url = try themes.createTemplate()
            settings.themeID = "user:\(url.lastPathComponent)"
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private func editCustomCSS() {
        do {
            let url = try themes.ensureCustomCSS()
            settings.useCustomCSS = true
            NSWorkspace.shared.open(url)
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}

private struct EditorTab: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            LabeledContent("文字サイズ") {
                Stepper("\(Int(settings.editorFontSize)) pt", value: $settings.editorFontSize, in: 9...40)
            }
            TextField("フォント名", text: $settings.editorFontName, prompt: Text("システムの等幅フォント"))
            Toggle("広い画面では行の長さを制限する", isOn: $settings.editorLimitWidth)
            Text("リストの継続、Tab での字下げ、画像の貼り付け（assets フォルダへ保存）に対応しています。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}
