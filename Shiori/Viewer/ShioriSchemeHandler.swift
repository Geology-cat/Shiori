import UniformTypeIdentifiers
import WebKit

/// ビューワー専用の URL スキームを配信する。
///   shiori://app/...         アプリ同梱のリソースとユーザーの CSS
///   shiori-file://local/...  md から参照されたローカルの画像など
final class ShioriSchemeHandler: NSObject, WKURLSchemeHandler {
    static let appScheme = "shiori"
    static let fileScheme = "shiori-file"
    static let shellURL = URL(string: "shiori://app/viewer.html")!

    /// shiori-file で配信してよいファイル。本文のスクリプトが任意のファイルを読めないよう限定する
    private static let allowedLocalExtensions: Set<String> = FileKinds.imageExtensions.union([
        "mp4", "m4v", "mov", "webm", "mp3", "m4a", "wav", "ogg", "flac", "woff", "woff2", "otf", "ttf",
    ])

    private let lock = NSLock()
    private var active = Set<ObjectIdentifier>()

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url else {
            task.didFailWithError(URLError(.badURL))
            return
        }
        let key = ObjectIdentifier(task)
        lock.withLock { _ = active.insert(key) }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Self.load(url)
            DispatchQueue.main.async {
                guard let self, self.lock.withLock({ self.active.remove(key) != nil }) else { return }
                switch result {
                case .success(let (data, mime)):
                    let response = HTTPURLResponse(
                        url: url,
                        statusCode: 200,
                        httpVersion: "HTTP/1.1",
                        headerFields: [
                            "Content-Type": mime,
                            "Content-Length": String(data.count),
                            "Cache-Control": "no-store",
                            "Access-Control-Allow-Origin": "*",
                        ]
                    )!
                    task.didReceive(response)
                    task.didReceive(data)
                    task.didFinish()
                case .failure(let error):
                    task.didFailWithError(error)
                }
            }
        }
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {
        let key = ObjectIdentifier(task)
        lock.withLock { _ = active.remove(key) }
    }

    private static func load(_ url: URL) -> Result<(Data, String), Error> {
        guard let fileURL = resolve(url) else { return .failure(URLError(.fileDoesNotExist)) }
        do {
            let data = try Data(contentsOf: fileURL)
            return .success((data, mimeType(for: fileURL)))
        } catch {
            return .failure(error)
        }
    }

    /// URL を実際のファイルへ対応付ける。不正なパスは nil
    static func resolve(_ url: URL) -> URL? {
        switch url.scheme {
        case appScheme:
            let path = url.path
            if path.hasPrefix("/user-themes/") {
                return inside(ThemeManager.shared.themesURL, relative: String(path.dropFirst("/user-themes/".count)))
            }
            if path == "/user-css/custom.css" {
                return ThemeManager.shared.customCSSURL
            }
            guard let dist = Bundle.main.url(forResource: "dist", withExtension: nil) else { return nil }
            return inside(dist, relative: String(path.dropFirst()))
        case fileScheme:
            let file = URL(fileURLWithPath: url.path).standardizedFileURL
            guard allowedLocalExtensions.contains(file.pathExtension.lowercased()) else { return nil }
            return file
        default:
            return nil
        }
    }

    /// base の外へ出るパス（../ など）を拒否する
    private static func inside(_ base: URL, relative: String) -> URL? {
        let candidate = base.appendingPathComponent(relative).standardizedFileURL
        let basePath = base.standardizedFileURL.path
        guard candidate.path.hasPrefix(basePath.hasSuffix("/") ? basePath : basePath + "/") else { return nil }
        return candidate
    }

    private static func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "html": return "text/html; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "js": return "text/javascript; charset=utf-8"
        case "svg": return "image/svg+xml"
        case "woff2": return "font/woff2"
        case "woff": return "font/woff"
        default:
            return UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        }
    }
}
