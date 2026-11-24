#if DEBUG
import AppKit
import SkilloriCore

/// Debug builds only: `SKILLORI_FIRST_START_PROBE=/some/file` checks what the app asks, and
/// when, on its first opening. It reads the saved choices as the app found them and follows
/// the case they make:
///
/// - **new** (no saved choice, first start never finished): checks are on, yet nothing is asked
///   while first start is up, neither macOS about notifications nor a source. The probe clicks
///   through to the last step and leaves by `SKILLORI_FIRST_START_PROBE_WAY`: `done` (the
///   default), `off` (Turn off checks, then Done) or `escape` (closed on the first step).
/// - **older** (first start finished, no saved choice): an installation from before 0.2.25,
///   where "Not now" saved nothing. Checks stay off and nothing is asked.
/// - **chosen**: the saved choice stands.
///
/// Run it on a copy of the app with a bundle identifier of its own, so the settings it starts
/// from and writes are not the reader's, and with `SKILLORI_TEST_HOME` (and `HOME`) set to a
/// folder made for it. macOS is never really asked about notifications here; the probe counts
/// the times it would have been. One line per step, a picture of each step, PASS or FAIL last.
@MainActor
enum DebugFirstStartProbe {
    /// The step first start shows now, as it shows it.
    static var step = 0

    static func runIfRequested(store: InventoryStore, firstStart: FirstStartController, panelModel: @escaping () -> PanelModel) {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["SKILLORI_FIRST_START_PROBE"] else { return }
        let way = env["SKILLORI_FIRST_START_PROBE_WAY"] ?? "done"
        // Read before anything else runs, so this is what the app started from.
        let defaults = UserDefaults.standard
        let chosenAtStart = defaults.object(forKey: "asksSources") as? Bool
        let finishedAtStart = defaults.bool(forKey: FirstStartController.doneKey)
        let shownAtStart = firstStart.panel != nil
        let onAtStart = store.checksEnabled, waitsAtStart = store.waitsForFirstStart
        Task { @MainActor in
            var lines: [String] = []
            var failures = 0
            @MainActor func log(_ line: String) {
                lines.append(line)
                try? lines.joined(separator: "\n").appending("\n").write(toFile: path, atomically: true, encoding: .utf8)
            }
            @MainActor func check(_ what: String, _ ok: Bool) {
                if !ok { failures += 1 }
                log("   \(ok ? "ok  " : "FAIL") \(what)")
            }
            @MainActor func pause(_ ms: Int) async { try? await Task.sleep(for: .milliseconds(ms)) }
            @MainActor func saved() -> String {
                let choice = (defaults.object(forKey: "asksSources") as? Bool).map { "\($0)" } ?? "unset"
                return "asksSources=\(choice), didFinishFirstStart=\(defaults.bool(forKey: FirstStartController.doneKey))"
            }
            @MainActor func asked() -> String {
                "macOS asked \(Notifier.shared.permissionAsks)×, sources asked \(store.checksStarted)×"
            }
            @MainActor func finish() {
                log(failures == 0 ? "PASS" : "FAIL (\(failures))")
                NSApp.terminate(nil)
            }
            var pictures = 0
            @MainActor func picture(_ name: String) {
                pictures += 1
                guard let view = firstStart.panel?.contentView,
                      let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path + ".\(pictures)-\(name).png"))
            }
            /// A click at a point counted from the panel's top left corner.
            @MainActor func click(_ x: CGFloat, _ y: CGFloat, _ name: String) async {
                guard let panel = firstStart.panel, let view = panel.contentView else { log("  no panel to click \(name) in"); return }
                let place = view.convert(NSPoint(x: x, y: view.isFlipped ? y : view.bounds.height - y), to: nil)
                let landed = view.hitTest(view.convert(place, from: nil))
                for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                    if let event = NSEvent.mouseEvent(with: type, location: place, modifierFlags: [],
                                                      timestamp: ProcessInfo.processInfo.systemUptime,
                                                      windowNumber: panel.windowNumber, context: nil,
                                                      eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0) {
                        NSApp.postEvent(event, atStart: false)
                    }
                    await pause(60)
                }
                log("  click \(name) at \(Int(x)),\(Int(y)) on \(landed.map { String(describing: type(of: $0)).prefix(48) } ?? "nothing")")
            }
            /// The sources have been asked and have answered, or the wait ran out.
            @MainActor func answered(within seconds: Int) async -> Bool {
                for _ in 0..<(seconds * 10) {
                    if store.checksStarted > 0, !store.isChecking { return true }
                    await pause(100)
                }
                return false
            }

            let kind = chosenAtStart != nil ? "chosen" : finishedAtStart ? "older" : "new"
            log("bundle \(Bundle.main.bundleIdentifier ?? "none"), home \(InventoryStore.home.path)")
            log("started from: asksSources=\(chosenAtStart.map { "\($0)" } ?? "unset"), didFinishFirstStart=\(finishedAtStart) → \(kind)")
            log("at launch: checks \(onAtStart ? "on" : "off"), waits for first start \(waitsAtStart), first start \(shownAtStart ? "showing" : "not showing")")

            while store.inventory == nil || store.isScanning { await pause(100) }
            let tracked = store.trackedCount
            log("read: \(store.inventory?.installations.count ?? 0) skills, \(tracked) with a source to ask")
            // The first reading asks the sources on its own when it may. Give it time to.
            await pause(4000)
            log("4 s after the first reading: \(asked()); \(saved())")
            let panelLines = panelModel().rows.compactMap { row -> String? in
                if case let .link(text, label, _) = row { return "\(text) · \(label)" }
                if case let .line(text, data, _) = row { return "\(text) · \(data)" }
                return nil
            }
            log("the menu bar panel says: \(panelLines.joined(separator: " | "))")
            let saysOff = panelLines.contains { $0.hasPrefix("Update checks are off") }

            switch kind {
            case "older":
                check("checks are off", !store.checksEnabled && !onAtStart)
                check("first start does not show again", !shownAtStart && firstStart.panel == nil)
                check("macOS was not asked about notifications", Notifier.shared.permissionAsks == 0)
                check("no source was asked", store.checksStarted == 0 && store.lastCheck == nil)
                check("the panel offers to turn checks on", tracked == 0 || saysOff)
                check("nothing was saved as a choice", defaults.object(forKey: "asksSources") == nil)

            case "chosen":
                check("the saved choice stands", store.checksEnabled == chosenAtStart && !waitsAtStart)
                check("macOS was not asked about notifications", Notifier.shared.permissionAsks == 0)
                if chosenAtStart == true {
                    check("the sources were asked on the first reading", tracked == 0 || store.checksStarted > 0)
                } else {
                    check("no source was asked", store.checksStarted == 0)
                    check("the panel offers to turn checks on", tracked == 0 || saysOff)
                }

            default:
                check("checks are on", onAtStart && store.checksEnabled)
                check("first start shows", shownAtStart && firstStart.panel != nil)
                check("the panel does not say checks are off", !saysOff)
                check("macOS was not asked about notifications while first start is up", Notifier.shared.permissionAsks == 0)
                check("no source was asked while first start is up", store.checksStarted == 0 && store.lastCheck == nil)
                check("nothing is saved yet", defaults.object(forKey: "asksSources") == nil && !defaults.bool(forKey: FirstStartController.doneKey))
                guard firstStart.panel != nil else { finish(); return }
                if let view = firstStart.panel?.contentView { log("   panel \(Int(view.bounds.width))×\(Int(view.bounds.height))") }
                picture("step-1")

                if way == "escape" {
                    log("Escape on the first step (the panel's own cancel, since a quiet run has no keyboard)")
                    firstStart.panel?.cancelOperation(nil)
                    await pause(400)
                } else {
                    for next in 2...4 {
                        await click(48, 434, "Continue"); await pause(700)
                        check("step \(next) shows", step == next)
                        picture("step-\(next)")
                    }
                    guard step == 4 else { finish(); return }
                    check("still nothing asked on the last step: \(asked())", Notifier.shared.permissionAsks == 0 && store.checksStarted == 0)
                    if way == "off" {
                        log("Turn off checks")
                        await click(124, 434, "Turn off checks"); await pause(700)
                        picture("turned-off")
                        check("checks are off, and first start stays up", !store.checksEnabled && firstStart.panel != nil && step == 4)
                        check("the no is saved at once: \(saved())", defaults.object(forKey: "asksSources") as? Bool == false)
                    }
                    log("Done")
                    await click(36, 434, "Done"); await pause(400)
                }
                check("first start closed", firstStart.panel == nil)
                check("first start is saved as finished", defaults.bool(forKey: FirstStartController.doneKey))
                if way == "off" {
                    await pause(4000)
                    check("the no stands: \(saved())", defaults.object(forKey: "asksSources") as? Bool == false && !store.checksEnabled)
                    check("nothing was asked: \(asked())", Notifier.shared.permissionAsks == 0 && store.checksStarted == 0 && store.lastCheck == nil)
                    let lines = panelModel().rows.compactMap { row -> String? in
                        if case let .link(text, label, _) = row { return "\(text) · \(label)" } else { return nil }
                    }
                    check("the panel offers to turn checks on", tracked == 0 || lines.contains { $0.hasPrefix("Update checks are off") })
                } else {
                    check("the yes is saved: \(saved())", defaults.object(forKey: "asksSources") as? Bool == true && store.checksEnabled)
                    check("macOS is asked about notifications now, once", Notifier.shared.permissionAsks == 1)
                    if tracked > 0 {
                        let heard = await answered(within: 60)
                        check("the sources are asked now: \(asked())", store.checksStarted > 0)
                        log("   \(heard ? "answered" : "no answer in 60 s"): \(store.checkStamp), \(store.upToDateCount) up to date, \(store.updateCount) with updates, problem \(store.lastProblem.map { "\($0)" } ?? "none")")
                    } else {
                        log("   no skill has a source here, so there is no source to ask")
                    }
                }
            }
            finish()
        }
    }
}
#endif
