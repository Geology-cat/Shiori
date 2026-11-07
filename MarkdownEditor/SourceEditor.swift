import SwiftUI

struct SourceEditor: View {
    @Binding var text: String
    let bridge: EditorBridge

    var body: some View {
        MarkdownTextView(text: $text, bridge: bridge)
            .background(Color(nsColor: .textBackgroundColor))
    }
}
