#if DEBUG
import AppKit
import SkilloriCore
import UserNotifications

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
/// - **chosen**: the saved choice stands. With checks on, macOS is asked about notifications
///   when the app opens (it shows its question only if it never has); with checks off it is not.
///
/// Run it on a copy of the app with a bundle identifier of its own, so the settings it starts
/// from and writes are not the reader's, and with `SKILLORI_TEST_HOME` (and `HOME`) set to a
/// folder made for it. macOS is not really asked about notifications; the probe counts the
/// times it would have been. `SKILLORI_FIRST_START_PROBE_NOTIFY=real` asks for real: on a copy
/// macOS has never seen, its question then shows on screen, and the probe writes down where
/// the permission stands before and after, and waits a while for it to be answered.
/// One line per step, a picture of each step, PASS or FAIL last.
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
        // An answer younger than six hours stands, so an opening soon after another asks no source.
        let freshAnswer = store.lastCheck.map { Date().timeIntervalSince($0) < InventoryStore.checkInterval } ?? false
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
            let asksForReal = env["SKILLORI_FIRST_START_PROBE_NOTIFY"] == "real"
            /// Where macOS has the permission for this copy of the app.
            @MainActor func permission() async -> String {
                switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
                case .notDetermined: "not asked yet"
                case .denied: "denied"
                case .authorized: "allowed"
                case .provisional: "provisional"
                default: "other"
                }
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

            // First start not finished is "new" whatever is saved: the wait holds until it has closed.
            let kind = !finishedAtStart ? "new" : chosenAtStart != nil ? "chosen" : "older"
            log("bundle \(Bundle.main.bundleIdentifier ?? "none"), home \(InventoryStore.home.path)")
            log("started from: asksSources=\(chosenAtStart.map { "\($0)" } ?? "unset"), didFinishFirstStart=\(finishedAtStart) → \(kind)")
            log("at launch: checks \(onAtStart ? "on" : "off"), waits for first start \(waitsAtStart), first start \(shownAtStart ? "showing" : "not showing")")

            while store.inventory == nil || store.isScanning { await pause(100) }
            let tracked = store.trackedCount
            log("read: \(store.inventory?.installations.count ?? 0) skills, \(tracked) with a source to ask")
            // The first reading asks the sources on its own when it may. Give it time to.
            await pause(4000)
            log("4 s after the first reading: \(asked()); \(saved())")
            var permissionBefore = ""
            if asksForReal {
                permissionBefore = await permission()
                log("macOS has the notification permission as: \(permissionBefore)")
            }
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
                if chosenAtStart == true {
                    // With checks on, the app asks macOS when it opens; macOS shows its question only if it never has.
                    check("macOS was asked about notifications when the app opened, once", Notifier.shared.permissionAsks == 1)
                    if freshAnswer {
                        check("no source was asked again: the last answer is younger than six hours", store.checksStarted == 0)
                    } else {
                        check("the sources were asked on the first reading", tracked == 0 || store.checksStarted > 0)
                    }
                    if asksForReal {
                        let wait = Int(env["SKILLORI_FIRST_START_PROBE_WAIT"] ?? "") ?? 90
                        let started = Date()
                        for _ in 0..<(wait * 2) where Notifier.shared.permissionAnswer == nil { await pause(500) }
                        // The answer comes at once when macOS already had one, and after the reader's click when it asked.
                        // What the first reading found came before the reader answered macOS: none of it may count as told.
                        let toldBefore = defaults.stringArray(forKey: "notifiedUpdates") ?? []
                        let waiting = store.updateCount
                        log("   \(waiting) with updates after the first reading; counted as told before macOS was answered: \(toldBefore.count)")
                        log("   macOS answered the request \(Int(Date().timeIntervalSince(started)) + 4) s after the app opened: \(Notifier.shared.permissionAnswer ?? "nothing yet (the question is still open)"); permission now \(await permission())")
                        check("macOS took the request", !(Notifier.shared.permissionAnswer ?? "").hasPrefix("error"))
                        if waiting > 0, Notifier.shared.permissionAnswer == "allowed" {
                            if started.timeIntervalSinceNow > -1 {
                                log("   macOS already had an answer, so the first reading told at once")
                            } else {
                                check("nothing counted as told while macOS had no answer", toldBefore.isEmpty)
                            }
                            // The next check is the one that tells. Check now, as the reader would.
                            await store.checkSources(force: true)
                            while store.isChecking { await pause(100) }
                            await pause(1500)
                            let shown = await UNUserNotificationCenter.current().deliveredNotifications()
                            for notification in shown {
                                log("   notification shown: \(notification.request.content.title) / \(notification.request.content.body)")
                            }
                            check("macOS shows a notification about what was waiting", !shown.isEmpty)
                            check("and it now counts as told", (defaults.stringArray(forKey: "notifiedUpdates") ?? []).count == waiting)
                        }
                    }
                } else {
                    check("macOS was not asked about notifications", Notifier.shared.permissionAsks == 0)
                    check("no source was asked", store.checksStarted == 0)
                    check("the panel offers to turn checks on", tracked == 0 || saysOff)
                }

            default:
                check("checks are on", onAtStart && store.checksEnabled)
                check("the app waits for first start", waitsAtStart)
                check("first start shows", shownAtStart && firstStart.panel != nil)
                check("the panel does not say checks are off", !saysOff)
                check("macOS was not asked about notifications while first start is up", Notifier.shared.permissionAsks == 0)
                check("no source was asked while first start is up", store.checksStarted == 0 && store.lastCheck == nil)
                check("nothing new is saved yet", defaults.object(forKey: "asksSources") as? Bool == chosenAtStart && !defaults.bool(forKey: FirstStartController.doneKey))
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
                    if asksForReal {
                        // The marker a script outside waits for before it takes a picture of the screen.
                        log("   ASKED-FOR-REAL: macOS had it as \(permissionBefore) until now")
                        check("macOS had not been asked before first start closed", permissionBefore == "not asked yet")
                        let wait = Int(env["SKILLORI_FIRST_START_PROBE_WAIT"] ?? "") ?? 90
                        // macOS has the permission as denied for as long as its question is unanswered,
                        // so only its answer to the request says that the reader has chosen.
                        log("   macOS has it as \(await permission()) while its question is up")
                        for _ in 0..<(wait * 2) where Notifier.shared.permissionAnswer == nil { await pause(500) }
                        await pause(300)
                        log("   after up to \(wait) s: permission \(await permission()), macOS answered the request: \(Notifier.shared.permissionAnswer ?? "nothing yet (the question is still open)")")
                        check("macOS took the request", !(Notifier.shared.permissionAnswer ?? "").hasPrefix("error"))
                    }
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

#if DEBUG
/// Debug builds only: `SKILLORI_NOTIFY_PROBE=/some/file` writes down where macOS has this copy's
/// notification permission, and quits. It asks nothing. With `SKILLORI_NOTIFY_PROBE_ASK=1` it
/// then asks macOS for the permission, as the app does when checks begin, and writes down what
/// macOS said, waiting up to `SKILLORI_NOTIFY_PROBE_WAIT` seconds (30) for the reader's answer.
@MainActor
enum DebugNotifyProbe {
    /// What macOS said when it was asked, once it has.
    private static var answer: String?

    static func runIfRequested() {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["SKILLORI_NOTIFY_PROBE"] else { return }
        Task { @MainActor in
            var lines: [String] = []
            @MainActor func log(_ line: String) {
                lines.append(line)
                try? lines.joined(separator: "\n").appending("\n").write(toFile: path, atomically: true, encoding: .utf8)
            }
            @MainActor func permission() async -> String {
                let settings = await UNUserNotificationCenter.current().notificationSettings()
                let status = switch settings.authorizationStatus {
                case .notDetermined: "not asked yet"
                case .denied: "denied"
                case .authorized: "allowed"
                case .provisional: "provisional"
                default: "other"
                }
                return "\(status) (alerts \(settings.alertSetting == .enabled ? "on" : "off"), style \(settings.alertStyle.rawValue))"
            }
            log("bundle \(Bundle.main.bundleIdentifier ?? "none") at \(Bundle.main.bundlePath)")
            log("HOME=\(env["HOME"] ?? "unset"), agent app \(Bundle.main.object(forInfoDictionaryKey: "LSUIElement") ?? "unset")")
            log("permission: \(await permission())")
            if env["SKILLORI_NOTIFY_PROBE_ASK"] != nil {
                let wait = Int(env["SKILLORI_NOTIFY_PROBE_WAIT"] ?? "") ?? 30
                let started = Date()
                answer = nil
                Task { @MainActor in
                    do {
                        let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                        answer = granted ? "allowed" : "not allowed"
                    } catch {
                        answer = "error: \(error.localizedDescription) (\((error as NSError).domain) \((error as NSError).code))"
                    }
                }
                while answer == nil, Date().timeIntervalSince(started) < Double(wait) {
                    try? await Task.sleep(for: .milliseconds(200))
                }
                log("asked macOS; after \(Int(Date().timeIntervalSince(started))) s it said: \(answer ?? "nothing yet (its question is still open)")")
                log("permission: \(await permission())")
            }
            log("done")
            NSApp.terminate(nil)
        }
    }
}
#endif
