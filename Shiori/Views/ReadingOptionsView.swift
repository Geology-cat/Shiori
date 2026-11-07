import SwiftUI

/// 上部バーの「Aa」から開く表示パネル。ここでの変更はこのファイルだけに効き、既定は変えない。
struct ReadingOptionsView: View {
    @ObservedObject var workspace: WorkspaceModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var themes: ThemeManager

    private var tab: DocumentTab? { workspace.activeTab }
    private var currentTheme: String { workspace.effectiveThemeID(for: tab) }
    private var currentWriting: WritingMode { workspace.effectiveWriting(for: tab) }

    /// 詳細設定を編集すると、既定と違う項目だけがこのファイルの調整として残る
    private var styleBinding: Binding<ViewStyle> {
        Binding(
            get: { workspace.effectiveStyle(for: tab) },
            set: { newValue in
                let old = workspace.effectiveStyle(for: tab)
                workspace.updateOverrides { o in
                    if newValue.fontScale != old.fontScale { o.fontScale = newValue.fontScale }
                    if newValue.lineHeight != old.lineHeight { o.lineHeight = newValue.lineHeight }
                    if newValue.measure != old.measure { o.measure = newValue.measure }
                    if newValue.fontChoice != old.fontChoice { o.fontChoice = newValue.fontChoice }
                    if newValue.customFontName != old.customFontName { o.customFontName = newValue.customFontName }
                    if newValue.indent != old.indent { o.indent = newValue.indent }
                    if newValue.justify != old.justify { o.justify = newValue.justify }
                    if newValue.headingNumbers != old.headingNumbers { o.headingNumbers = newValue.headingNumbers }
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            OptionSection(title: "テーマ") {
                VStack(spacing: 3) {
                    ForEach(themes.allThemes) { theme in
                        ThemeRow(theme: theme, isSelected: currentTheme == theme.id) {
                            workspace.setTheme(theme.id)
                        }
                    }
                }
            }

            OptionSection(title: "組方向") {
                Picker("", selection: Binding(get: { currentWriting }, set: { workspace.setWriting($0) })) {
                    ForEach(WritingMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            StyleEditor(style: styleBinding, writing: currentWriting)

            Divider()

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(workspace.hasOverrides ? "このファイル用に調整しています" : "既定の表示です")
                        .font(.system(size: 11.5, weight: .medium))
                    Text("既定は環境設定で変更できます")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("既定に戻す") { workspace.resetOverrides() }
                    .controlSize(.small)
                    .disabled(!workspace.hasOverrides)
            }
            HStack {
                Spacer()
                Button("環境設定…") { AppDelegate.shared.showSettings(nil) }
                    .controlSize(.small)
            }
        }
        .padding(14)
        .frame(width: 300)
    }
}

/// 文字・組版の詳細設定（表示パネルと環境設定で共通）
struct StyleEditor: View {
    @Binding var style: ViewStyle
    let writing: WritingMode

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            OptionSection(title: "文字") {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Text("サイズ").font(.system(size: 12)).frame(width: 44, alignment: .leading)
                        IconButton(systemName: "textformat.size.smaller", help: "小さく") {
                            style.fontScale = ViewStyle.scaledDown(style.fontScale)
                        }
                        Text("\(Int((style.fontScale * 100).rounded()))%")
                            .font(.system(size: 12))
                            .monospacedDigit()
                            .frame(maxWidth: .infinity)
                        IconButton(systemName: "textformat.size.larger", help: "大きく") {
                            style.fontScale = ViewStyle.scaledUp(style.fontScale)
                        }
                    }
                    SliderRow(title: "行間", value: $style.lineHeight, range: 1.2...2.6, step: 0.05) {
                        String(format: "%.2f", $0)
                    }
                    SliderRow(title: writing == .vertical ? "字詰め" : "本文幅", value: $style.measure, range: 20...80, step: 1) {
                        "\(Int($0)) 字"
                    }
                    HStack(spacing: 8) {
                        Text("書体").font(.system(size: 12)).frame(width: 44, alignment: .leading)
                        Picker("", selection: $style.fontChoice) {
                            ForEach(FontChoice.allCases) { Text($0.label).tag($0) }
                        }
                        .labelsHidden()
                        .controlSize(.small)
                        .fixedSize()
                        Spacer(minLength: 0)
                    }
                    if style.fontChoice == .custom {
                        TextField("フォント名（例: Hiragino Maru Gothic ProN）", text: $style.customFontName)
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.small)
                    }
                }
            }

            OptionSection(title: "組版") {
                VStack(alignment: .leading, spacing: 5) {
                    Toggle("段落の字下げ", isOn: $style.indent)
                    Toggle("両端揃え", isOn: $style.justify)
                    Toggle("見出しに番号を振る", isOn: $style.headingNumbers)
                }
                .toggleStyle(.checkbox)
                .font(.system(size: 12))
            }
        }
    }
}

struct OptionSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            content()
        }
    }
}

private struct ThemeRow: View {
    let theme: ViewerTheme
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.5))
                VStack(alignment: .leading, spacing: 0) {
                    Text(theme.name).font(.system(size: 12.5, weight: .medium))
                    Text(theme.summary).font(.system(size: 10.5)).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(isHovering ? Color.primary.opacity(0.05) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

/// 0 を「テーマの値」として扱うスライダー
private struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: (Double) -> String

    var body: some View {
        HStack(spacing: 8) {
            Text(title).font(.system(size: 12)).frame(width: 44, alignment: .leading)
            Slider(
                value: Binding(
                    get: { value == 0 ? (range.lowerBound + range.upperBound) / 2 : value },
                    set: { value = $0 }
                ),
                in: range,
                step: step
            )
            .controlSize(.small)
            Button(value == 0 ? "テーマ" : format(value)) { value = 0 }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 46, alignment: .trailing)
                .help("クリックでテーマの値に戻す")
        }
    }
}
