import SwiftUI

/// 上部バーの「Aa」から開く、表示の設定パネル
struct ReadingOptionsView: View {
    @ObservedObject var workspace: WorkspaceModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var themes: ThemeManager

    private var tab: DocumentTab? { workspace.activeTab }
    private var currentTheme: String { workspace.effectiveThemeID(for: tab) }
    private var currentWriting: WritingMode { workspace.effectiveWriting(for: tab) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            section("テーマ") {
                VStack(spacing: 3) {
                    ForEach(themes.allThemes) { theme in
                        ThemeRow(theme: theme, isSelected: currentTheme == theme.id) {
                            workspace.setTheme(theme.id)
                        }
                    }
                }
            }

            section("組方向") {
                Picker("", selection: Binding(get: { currentWriting }, set: { workspace.setWriting($0) })) {
                    ForEach(WritingMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            section("文字") {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Text("サイズ").font(.system(size: 12)).frame(width: 44, alignment: .leading)
                        IconButton(systemName: "textformat.size.smaller", help: "小さく (⌘-)") { settings.decreaseFontScale() }
                        Text("\(Int((settings.fontScale * 100).rounded()))%")
                            .font(.system(size: 12))
                            .monospacedDigit()
                            .frame(maxWidth: .infinity)
                        IconButton(systemName: "textformat.size.larger", help: "大きく (⌘+)") { settings.increaseFontScale() }
                    }
                    SliderRow(
                        title: "行間",
                        value: $settings.lineHeight,
                        range: 1.2...2.6,
                        step: 0.05,
                        format: { String(format: "%.2f", $0) }
                    )
                    SliderRow(
                        title: currentWriting == .vertical ? "字詰め" : "本文幅",
                        value: $settings.measure,
                        range: 20...80,
                        step: 1,
                        format: { "\(Int($0)) 字" }
                    )
                    HStack(spacing: 8) {
                        Text("書体").font(.system(size: 12)).frame(width: 44, alignment: .leading)
                        Picker("", selection: $settings.fontChoice) {
                            ForEach(FontChoice.allCases) { Text($0.label).tag($0) }
                        }
                        .labelsHidden()
                        .controlSize(.small)
                    }
                    if settings.fontChoice == .custom {
                        TextField("フォント名（例: Hiragino Maru Gothic ProN）", text: $settings.customFontName)
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.small)
                    }
                }
            }

            section("組版") {
                VStack(alignment: .leading, spacing: 5) {
                    Toggle("段落の字下げ", isOn: $settings.indent)
                    Toggle("両端揃え", isOn: $settings.justify)
                    Toggle("見出しに番号を振る", isOn: $settings.headingNumbers)
                }
                .toggleStyle(.checkbox)
                .font(.system(size: 12))
            }

            Divider()

            if tab?.url != nil {
                Toggle("テーマと組方向をこのファイルに固定", isOn: Binding(
                    get: { workspace.isViewPinned(tab) },
                    set: { workspace.setViewPinned($0) }
                ))
                .toggleStyle(.checkbox)
                .font(.system(size: 12))
                .help("オンにすると、このファイルだけ今のテーマと組方向で開きます")
            }

            HStack {
                Button("元に戻す") {
                    settings.fontScale = 1
                    settings.lineHeight = 0
                    settings.measure = 0
                    settings.fontChoice = .theme
                    settings.indent = false
                    settings.justify = false
                    settings.headingNumbers = false
                }
                .controlSize(.small)
                Spacer()
                Button("環境設定…") { AppDelegate.shared.showSettings(nil) }
                    .controlSize(.small)
            }
        }
        .padding(14)
        .frame(width: 300)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
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

/// 0 を「テーマの既定」として扱うスライダー
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
            Button(value == 0 ? "既定" : format(value)) { value = 0 }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 42, alignment: .trailing)
                .help("クリックでテーマの既定に戻す")
        }
    }
}
