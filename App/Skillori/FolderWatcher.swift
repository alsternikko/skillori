import CoreServices
import Foundation

/// Tells the app when something changes in the folders where skills live, so the inventory
/// follows an install, an update or a deletion made outside Skillori.
///
/// Uses FSEvents, which reports changes per folder and coalesces bursts. Events are not
/// guaranteed, so the app still reads again on its own schedule; this only makes it sooner.
/// Nothing is read here: the watcher only says "something changed", and the store reads.
final class FolderWatcher: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private var watched: [String] = []
    private let queue = DispatchQueue(label: "app.skillori.folder-watcher", qos: .utility)
    private let onChange: @Sendable () -> Void

    /// `onChange` runs on the main queue, at most once per `latency` seconds of changes.
    init(onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange
    }

    deinit { stop() }

    /// Watches these folders and nothing else. Calling it again with the same set does nothing.
    func watch(_ paths: [String], latency: TimeInterval = 2) {
        let unique = Array(Set(paths.filter { !$0.isEmpty })).sorted()
        guard unique != watched else { return }
        stop()
        watched = unique
        guard !unique.isEmpty else { return }

        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
            DispatchQueue.main.async { watcher.onChange() }
        }
        // Not FileEvents: one event per changed folder is enough, and far fewer arrive. Without
        // NoDefer the first event waits out the latency too, so an install that writes many
        // files gives one call, not one at its start and one at its end.
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagWatchRoot)
        guard let stream = FSEventStreamCreate(nil, callback, &context, unique as CFArray,
                                               FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                                               latency, flags) else { return }
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
        watched = []
    }
}
