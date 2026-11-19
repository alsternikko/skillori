#if DEBUG
import AppKit
import SkilloriCore

/// Debug builds only: `SKILLORI_ADOPT_PROBE=/some/file` together with `SKILLORI_TEST_HOME` (and
/// `HOME`) set to a folder of copies runs Update for skills linked by hand, the whole way: links
/// each copy to anthropics/skills as an earlier version, presses Update, and says what the
/// installer, the Trash and the next read left behind. Nothing outside the test home is touched,
/// except that folders under an old name go to the Trash.
@MainActor
enum DebugAdoptProbe {
    static func runIfRequested(store: InventoryStore) {
        guard let path = ProcessInfo.processInfo.environment["SKILLORI_ADOPT_PROBE"],
              let home = InventoryStore.testHome else { return }
        Task { @MainActor in
            var lines: [String] = []
            @MainActor func log(_ line: String) {
                lines.append(line)
                try? lines.joined(separator: "\n").appending("\n").write(toFile: path, atomically: true, encoding: .utf8)
            }
            @MainActor func pause(_ ms: Int) async { try? await Task.sleep(for: .milliseconds(ms)) }
            @MainActor func listing(_ folder: String) -> String {
                let url = home.appendingPathComponent(folder)
                let names = (try? FileManager.default.contentsOfDirectory(atPath: url.path))?.sorted() ?? []
                return names.map { name in
                    let target = try? FileManager.default.destinationOfSymbolicLink(atPath: url.appendingPathComponent(name).path)
                    return target.map { "\(name) → \($0)" } ?? name
                }.joined(separator: ", ")
            }

            while store.inventory == nil || store.isScanning { await pause(100) }
            let anthropic = UpstreamSource(owner: "anthropics", repository: "skills")
            let groups = await store.unlinkedGroups()
            log("unlinked: \(groups.map { "\($0.name) ×\($0.installations.count)" })")
            for group in groups {
                let name = group.installations.first?.displayName ?? group.name
                let proposal = SourceProposal(source: anthropic, subpath: "skills/\(name)",
                                              evidence: .olderVersion(date: nil, commit: "test", missing: 0),
                                              via: "test", upstreamHash: "0000000000000000000000000000000000000000")
                store.link(group, to: proposal)
            }
            let all = store.inventory?.installations ?? []
            for installation in all {
                log("  \(installation.directoryName) at \(installation.canonicalPath.replacingOccurrences(of: home.path, with: "~")): \(store.status(for: installation))")
            }
            let updatable = store.updatable
            log("updatable: \(updatable.count)")
            log("command: \(store.updateCommandText(for: updatable))")
            await store.update(updatable)
            log("run: \(store.updater.phase)")
            for line in store.updater.lastLines(4) { log("  | \(line)") }
            log(".claude/skills: \(listing(".claude/skills"))")
            log(".agents/skills: \(listing(".agents/skills"))")
            let lock = (try? Data(contentsOf: home.appendingPathComponent(".agents/.skill-lock.json")))
                .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            log("lock: \(((lock?["skills"] as? [String: Any])?.keys.sorted()) ?? [])")
            log("links left: \(store.links.count)")
            for installation in store.inventory?.installations ?? [] {
                let kind = if case .skillsLock = installation.provenance { "installer" } else { "\(installation.provenance)" }
                log("  after: \(installation.directoryName) — \(kind), \(store.status(for: installation))")
            }
            NSApp.terminate(nil)
        }
    }
}
#endif
