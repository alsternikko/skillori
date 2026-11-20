#if DEBUG
import AppKit
import SkilloriCore

/// Debug builds only: `SKILLORI_LOST_PROBE=/some/file` together with `SKILLORI_TEST_HOME` (and
/// `HOME`) set to a folder holding a skill whose recorded source is gone runs the way on, the
/// whole way: asks the source, links the skill to the folder named by `SKILLORI_LOST_PROBE_SOURCE`
/// (`owner/repository/folder`), presses Update, and writes what the installer's record says after.
/// Nothing outside the test home is touched.
///
/// Run on 2026-11-20 with twombly, whose materic-inc/twombly-skill is gone and which now lives in
/// materic-inc/plugins, where a second skill has the same name.
@MainActor
enum DebugLostSourceProbe {
    static func runIfRequested(store: InventoryStore) {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["SKILLORI_LOST_PROBE"], let target = env["SKILLORI_LOST_PROBE_SOURCE"],
              let home = InventoryStore.testHome else { return }
        Task { @MainActor in
            var lines: [String] = []
            @MainActor func log(_ line: String) {
                lines.append(line)
                try? lines.joined(separator: "\n").appending("\n").write(toFile: path, atomically: true, encoding: .utf8)
            }
            @MainActor func pause(_ ms: Int) async { try? await Task.sleep(for: .milliseconds(ms)) }
            @MainActor func lock() -> String {
                guard let data = try? Data(contentsOf: home.appendingPathComponent(".agents/.skill-lock.json")),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let skills = json["skills"] as? [String: [String: Any]] else { return "unreadable" }
                return skills.keys.sorted().map { name in
                    "\(name): \(skills[name]?["source"] ?? "?") \(skills[name]?["skillPath"] ?? "?") \(skills[name]?["skillFolderHash"] ?? "?")"
                }.joined(separator: "; ")
            }
            @MainActor func done() { log("-- end"); NSApp.terminate(nil) }

            while store.inventory == nil || store.isScanning { await pause(100) }
            log("checks on: \(store.checksEnabled)")
            guard store.checksEnabled else { log("turn checks on first"); done(); return }
            await store.checkSources(force: true)
            while store.isChecking { await pause(100) }
            log("lock before: \(lock())")
            guard let lost = store.lostSources.first else {
                log("nothing lost: \((store.inventory?.installations ?? []).map { "\($0.directoryName) \(store.status(for: $0))" })")
                done(); return
            }
            log("lost: \(lost.directoryName) · \(String(describing: store.lostSource(of: lost))) · status \(store.status(for: lost)) · can link \(store.canLink(lost))")
            log("panel row: \(PanelModel.live(from: store).rows.map(\.id))")

            switch await store.searchSource(target, for: lost) {
            case .failure(let problem):
                log("search failed: \(problem.sentence)"); done(); return
            case .success(let search):
                log("candidates: \(search.candidates.map { "\($0.subpath) \($0.match)" }) · suggested \(search.suggested ?? "-")")
                guard let candidate = search.candidates.first(where: { $0.subpath == search.suggested }) ?? search.candidates.first else {
                    log("no candidate"); done(); return
                }
                store.link(lost, to: candidate, in: search)
                log("linked to \(candidate.subpath): status \(store.status(for: lost)) · lost \(String(describing: store.lostSource(of: lost)))")
            }
            let updatable = store.updatable
            log("updatable: \(updatable.map(\.directoryName))")
            log("command: \(store.updateCommandText(for: updatable))")
            guard !updatable.isEmpty else { done(); return }
            await store.update(updatable)
            while store.isChecking || store.isScanning { await pause(100) }
            log("run: \(store.updater.phase)")
            for line in store.updater.lastLines(4) { log("  | \(line)") }
            log("lock after: \(lock())")
            log("links left: \(store.links.count)")
            let page = store.installation(id: lost.id)
            log("page for the old id \(lost.id): \(page.map { "\($0.directoryName) id \($0.id) · \(store.status(for: $0)) · receipt \(store.receipt.map { $0.source } ?? "-")" } ?? "gone")")
            @MainActor func after(_ label: String) {
                if let after = store.inventory?.installations.first(where: { $0.directoryName == lost.directoryName }) {
                    log("\(label): \(after.provenance) · \(store.status(for: after)) · source \(store.upstreamSource(for: after)?.name ?? "-") · scanned \(store.inventory?.scannedAt.formatted(date: .omitted, time: .standard) ?? "-") lock \(store.inventory?.lockFile ?? "-")")
                }
            }
            after("after")
            await pause(3000)
            after("3 s later")
            await store.rescan()
            after("read again")
            done()
        }
    }
}
#endif
