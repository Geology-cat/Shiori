import AppKit
import SwiftUI

/// NSTextView ベースの Markdown ソース編集ビュー。
/// SwiftUI 標準の TextEditor では選択範囲やキャレット位置を扱えないため、ツールバー連動のために置き換えている。
struct MarkdownTextView: NSViewRepresentable {
    @Binding var text: String
    let bridge: EditorBridge
    @AppStorage("editorFontSize") var editorFontSize: Double = 14.0

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        guard let tv = scroll.documentView as? NSTextView else { return scroll }

        tv.delegate = context.coordinator
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isAutomaticLinkDetectionEnabled = false
        tv.isAutomaticDataDetectionEnabled = false
        tv.isRichText = false
        tv.allowsUndo = true
        tv.usesFindBar = true
        tv.font = NSFont.monospacedSystemFont(ofSize: CGFloat(editorFontSize), weight: .regular)
        tv.textContainerInset = NSSize(width: 8, height: 8)
        tv.backgroundColor = .textBackgroundColor
        tv.drawsBackground = true

        // 行間
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 2
        tv.defaultParagraphStyle = style
        tv.typingAttributes = [
            .font: tv.font!,
            .foregroundColor: NSColor.textColor,
            .paragraphStyle: style,
        ]

        tv.string = text
        bridge.attach(tv)
        context.coordinator.textView = tv
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView else { return }
        if tv.string != text {
            let sel = tv.selectedRange()
            tv.string = text
            let len = (tv.string as NSString).length
            tv.setSelectedRange(NSRange(location: min(sel.location, len), length: 0))
        }
        if tv.font?.pointSize != CGFloat(editorFontSize) {
            tv.font = NSFont.monospacedSystemFont(ofSize: CGFloat(editorFontSize), weight: .regular)
        }
        bridge.attach(tv)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        weak var textView: NSTextView?

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            let newValue = tv.string
            // 同値書き戻しによる無用な SwiftUI 再評価を避ける
            if text.wrappedValue != newValue {
                text.wrappedValue = newValue
            }
        }
    }
}
