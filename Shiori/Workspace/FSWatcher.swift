import CoreServices
import Foundation

/// FSEvents でフォルダの変更を監視する。コールバックはメインスレッドで呼ばれる。
final class FSWatcher {
    private var stream: FSEventStreamRef?
    private var watchedPaths: [String] = []
    private let handler: ([String]) -> Void

    init(handler: @escaping ([String]) -> Void) {
        self.handler = handler
    }

    deinit { stop() }

    func watch(paths: [String]) {
        let unique = Array(Set(paths)).sorted()
        if unique == watchedPaths, stream != nil { return }
        stop()
        watchedPaths = unique
        guard !unique.isEmpty else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FSWatcher>.fromOpaque(info).takeUnretainedValue()
            let list = unsafeBitCast(paths, to: NSArray.self) as? [String] ?? []
            watcher.handler(Array(list.prefix(count)))
        }
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer)
        guard let created = FSEventStreamCreate(
            kCFAllocatorDefault, callback, &context, unique as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.3, flags
        ) else { return }
        FSEventStreamSetDispatchQueue(created, DispatchQueue.main)
        FSEventStreamStart(created)
        stream = created
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
}
