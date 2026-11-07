import AppKit
import Combine

/// ツールバーから NSTextView へコマンドを橋渡しするオブジェクト。
/// `ContentView` が `@StateObject` で保持し、`MarkdownTextView` と toolbar の双方に渡す。
/// MarkdownTextView の Coordinator が `attach(_:)` で NSTextView を登録する。
final class EditorBridge: ObservableObject {
    weak var textView: NSTextView?

    func attach(_ textView: NSTextView) {
        self.textView = textView
    }

    // MARK: - 基本オペレーション

    /// 現在のキャレット位置 or 選択範囲を `prefix` と `suffix` で囲む。
    /// 無選択時はキャレット位置に "\(prefix)\(suffix)" を挿入し、キャレットを真ん中へ。
    func wrapSelection(prefix: String, suffix: String, placeholder: String = "") {
        guard let tv = textView else { return }
        guard let storage = tv.textStorage else { return }
        tv.window?.makeFirstResponder(tv)

        let selected = tv.selectedRange()
        if selected.length > 0 {
            let inner = (storage.string as NSString).substring(with: selected)
            let replacement = prefix + inner + suffix
            replace(in: tv, range: selected, with: replacement,
                    newSelection: NSRange(location: selected.location + prefix.count,
                                          length: inner.count))
        } else {
            let body = placeholder
            let replacement = prefix + body + suffix
            replace(in: tv, range: selected, with: replacement,
                    newSelection: NSRange(location: selected.location + prefix.count,
                                          length: body.count))
        }
    }

    /// キャレット位置 (または選択末尾) に文字列を挿入。selectionOffset で挿入後の選択開始位置を相対指定可能。
    func insertAtCursor(_ text: String, selectionOffset: Int? = nil, selectionLength: Int = 0) {
        guard let tv = textView else { return }
        tv.window?.makeFirstResponder(tv)
        let selected = tv.selectedRange()
        let newLoc: Int
        if let offset = selectionOffset {
            newLoc = selected.location + offset
        } else {
            newLoc = selected.location + (text as NSString).length
        }
        replace(in: tv, range: selected, with: text,
                newSelection: NSRange(location: newLoc, length: selectionLength))
    }

    /// カーソル位置を含む行頭にプレフィックスを付ける。複数行選択時は各行に付ける。
    func prefixLines(_ prefix: String) {
        guard let tv = textView else { return }
        guard let storage = tv.textStorage else { return }
        tv.window?.makeFirstResponder(tv)
        let nsText = storage.string as NSString
        let selected = tv.selectedRange()
        let lineRange = nsText.lineRange(for: selected)
        let original = nsText.substring(with: lineRange)
        // 末尾改行は除いて行ごとに分割し、再度結合
        var trailing = ""
        var body = original
        if body.hasSuffix("\n") {
            trailing = "\n"
            body.removeLast()
        }
        let prefixed = body
            .components(separatedBy: "\n")
            .map { prefix + $0 }
            .joined(separator: "\n") + trailing
        replace(in: tv, range: lineRange, with: prefixed,
                newSelection: NSRange(location: lineRange.location,
                                      length: (prefixed as NSString).length))
    }

    /// ブロックを行頭 (= キャレット位置が行の途中なら改行を入れて) に挿入する。
    func insertBlock(_ block: String) {
        guard let tv = textView else { return }
        guard let storage = tv.textStorage else { return }
        tv.window?.makeFirstResponder(tv)
        let nsText = storage.string as NSString
        let selected = tv.selectedRange()

        var insertion = block
        // 直前の文字を見て改行が必要か判定
        if selected.location > 0 {
            let prevChar = nsText.substring(with: NSRange(location: selected.location - 1, length: 1))
            if prevChar != "\n" { insertion = "\n" + insertion }
        }
        // 直後に内容がある場合は末尾改行
        if selected.location + selected.length < nsText.length {
            let nextChar = nsText.substring(with: NSRange(location: selected.location + selected.length, length: 1))
            if nextChar != "\n" { insertion += "\n" }
        }
        let newLoc = selected.location + (insertion as NSString).length
        replace(in: tv, range: selected, with: insertion,
                newSelection: NSRange(location: newLoc, length: 0))
    }

    // MARK: - 内部

    /// shouldChangeText/didChangeText を呼んで undo 履歴に積みつつ置換する。
    private func replace(in tv: NSTextView, range: NSRange, with text: String, newSelection: NSRange) {
        guard tv.shouldChangeText(in: range, replacementString: text) else { return }
        tv.textStorage?.replaceCharacters(in: range, with: text)
        tv.didChangeText()
        let storage = tv.textStorage?.string as NSString? ?? ""
        let safeLoc = min(newSelection.location, storage.length)
        let safeLen = max(0, min(newSelection.length, storage.length - safeLoc))
        tv.setSelectedRange(NSRange(location: safeLoc, length: safeLen))
        tv.scrollRangeToVisible(NSRange(location: safeLoc, length: 0))
    }
}
