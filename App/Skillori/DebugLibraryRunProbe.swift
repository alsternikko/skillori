#if DEBUG
import AppKit
import SkilloriCore

/// Debug builds only: `SKILLORI_LIBRARY_RUN_PROBE=/some/dir` (with `SKILLORI_SAMPLE_READINGS=1`)
/// opens the library and plays an update of the first source's skills on its home, without the
/// installer: first one that fails, then one that goes well. It writes the library window's
/// number to `window.txt`, so frames can be taken from outside with `screencapture -l`, and
/// what it did when to `log.txt`.
@MainActor
enum DebugLibraryRunProbe {
    static func runIfRequested(store: InventoryStore, windows: WindowRouter) {
        guard let dir = ProcessInfo.processInfo.environment["SKILLORI_LIBRARY_RUN_PROBE"] else { return }
        Task { @MainActor in
            let t0 = ProcessInfo.processInfo.systemUptime
            var lines: [String] = []
            @MainActor func log(_ line: String) {
                lines.append(String(format: "%6d  ", Int((ProcessInfo.processInfo.systemUptime - t0) * 1000)) + line)
                try? lines.joined(separator: "\n").appending("\n").write(toFile: dir + "/log.txt", atomically: true, encoding: .utf8)
            }
            @MainActor func pause(_ ms: Int) async { try? await Task.sleep(for: .milliseconds(ms)) }

            while store.inventory == nil || store.isScanning || store.isChecking { await pause(100) }
            windows.showLibrary()
            await pause(800)
            guard let window = windows.library else { log("no library window"); NSApp.terminate(nil); return }
            try? "\(window.windowNumber)".write(toFile: dir + "/window.txt", atomically: true, encoding: .utf8)
            let bySource = Dictionary(grouping: store.updatable) { store.upstreamSource(for: $0)?.name ?? "" }
            guard let source = bySource.keys.sorted().first, let skills = bySource[source] else { log("nothing to update"); NSApp.terminate(nil); return }
            await pause(2500)
            log("-- run that fails: \(skills.map(\.directoryName))")
            await store.playSampleUpdate(skills, fails: true)
            log("-- failed")
            await pause(3000)
            log("-- run that goes well")
            await store.playSampleUpdate(skills)
            log("-- receipt")
            await pause(6000)
            log("-- end")
            NSApp.terminate(nil)
        }
    }
}
#endif
