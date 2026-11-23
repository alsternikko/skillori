#if DEBUG
import AppKit
import SkilloriCore

/// Debug builds only: `SKILLORI_SHARE_PROBE=/some/file` opens Your skills, clicks Share skills…,
/// and works the sheet with mouse events posted to the app: None, two skills, Copy; then Back,
/// the source's own box, All, one agent, Agent, Copy; then Done. What Copy made goes to a
/// pasteboard of the probe's own and is compared with what the same choices should make. One
/// line per step, PASS or FAIL at the end, and a picture of the sheet after each step.
/// Save as file… is not clicked: it opens the system's save panel.
@MainActor
enum DebugShareProbe {
    /// What the sheet has ticked, and whether it shows its receipt, as it shows them now.
    static var ticked: Set<String> = []
    static var showsReceipt = false

    static func runIfRequested(store: InventoryStore, windows: WindowRouter) {
        guard let path = ProcessInfo.processInfo.environment["SKILLORI_SHARE_PROBE"] else { return }
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
            // The reader's clipboard and remembered choices are theirs: the probe uses its own
            // pasteboard, and puts the choices back as they were before it quits.
            let board = NSPasteboard(name: NSPasteboard.Name("app.skillori.share-probe"))
            ShareSheet.board = board
            let defaults = UserDefaults.standard
            let kept = [ShareSheet.targetKey, ShareSheet.agentKey].map { ($0, defaults.string(forKey: $0)) }
            for (key, _) in kept { defaults.removeObject(forKey: key) }
            @MainActor func finish() {
                log(failures == 0 ? "PASS" : "FAIL (\(failures))")
                for (key, value) in kept {
                    if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
                }
                defaults.synchronize()
                log("choices put back: \(kept.map { "\($0.0)=\($0.1 ?? "unset")" }.joined(separator: ", ")), now \(kept.map { defaults.string(forKey: $0.0) ?? "unset" })")
                board.releaseGlobally()
                // The app does not quit under an open sheet, so a run that stops early closes it first.
                if let window = windows.library, let sheet = window.attachedSheet { window.endSheet(sheet) }
                NSApp.terminate(nil)
            }

            while store.inventory == nil || store.isScanning { await pause(100) }
            windows.showLibrary(at: .mine)
            await pause(900)
            guard let window = windows.library, let content = window.contentView else { log("no library window"); finish(); return }

            @MainActor func click(_ point: NSPoint, in target: NSWindow, _ name: String) async {
                guard let view = target.contentView else { return }
                let y = view.isFlipped ? point.y : view.bounds.height - point.y
                let place = view.convert(NSPoint(x: point.x, y: y), to: nil)
                let landed = (view.superview ?? view).hitTest((view.superview ?? view).convert(place, from: nil))
                for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                    if let event = NSEvent.mouseEvent(with: type, location: place, modifierFlags: [],
                                                      timestamp: ProcessInfo.processInfo.systemUptime,
                                                      windowNumber: target.windowNumber, context: nil,
                                                      eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0) {
                        NSApp.postEvent(event, atStart: false)
                    }
                    // A press held for a moment, as a finger holds it.
                    await pause(60)
                }
                log("  click \(name) at \(Int(point.x)),\(Int(point.y)) on \(landed.map { String(describing: type(of: $0)).prefix(48) } ?? "nothing")")
            }
            var step = 0
            @MainActor func picture(_ target: NSWindow, _ name: String) {
                step += 1
                guard let view = target.contentView?.superview ?? target.contentView,
                      let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path + ".\(step)-\(name).png"))
            }

            let list = store.shareList()
            guard let first = list.groups.first, first.rows.count >= 2, let agent = store.shareAgents.first else {
                log("skipped: the first source needs two skills, and one agent has to be offered"); finish(); return
            }
            log("1. Share skills… above your skills")
            await click(NSPoint(x: content.bounds.width - 70, y: 73), in: window, "Share skills…")
            await pause(1200)
            guard let sheet = window.attachedSheet, let inside = sheet.contentView else { check("the sheet opened", false); finish(); return }
            check("the sheet opened", true)
            check("everything is ticked from the start", ticked == Set(list.rows.map(\.id)))
            picture(sheet, "all")
            log("   sheet content \(Int(inside.bounds.width))×\(Int(inside.bounds.height))")
            // From the bottom, where the buttons and the two choices sit whatever the list holds.
            @MainActor func bottom() -> CGFloat { (sheet.contentView?.bounds.height ?? 0) - 34 }
            let pair = Set(first.rows.prefix(2).map(\.id))

            log("2. None, then the first two skills, then Copy")
            await click(NSPoint(x: 557, y: 167), in: sheet, "None"); await pause(300)
            check("None unticks everything", ticked.isEmpty)
            await click(NSPoint(x: 150, y: 236), in: sheet, first.rows[0].name); await pause(200)
            await click(NSPoint(x: 150, y: 264), in: sheet, first.rows[1].name); await pause(300)
            check("a click on a skill ticks it", ticked == pair)
            picture(sheet, "two")
            guard ticked == pair else { finish(); return }
            await click(NSPoint(x: 72, y: bottom()), in: sheet, "Copy command"); await pause(700)
            let two = ShareCommand(first.rows.prefix(2).map(\.skill)).line
            check("copied the line for those two: \(board.string(forType: .string) ?? "(nothing)")", board.string(forType: .string) == two)
            check("the receipt shows", showsReceipt)
            picture(sheet, "copied")
            // Back sits where Save as file… does on the list, and that one opens the save panel.
            guard showsReceipt else { finish(); return }

            log("3. Back, the source’s box off, All, \(agent.displayName), Agent, Copy")
            await click(NSPoint(x: 199, y: bottom()), in: sheet, "Back"); await pause(700)
            check("Back keeps what was ticked", !showsReceipt && ticked == pair)
            board.clearContents()
            await click(NSPoint(x: 100, y: 206), in: sheet, first.source); await pause(300)
            check("a click on a source with all its skills ticked unticks them", ticked.isEmpty)
            await click(NSPoint(x: 72, y: bottom()), in: sheet, "Copy command with nothing ticked"); await pause(400)
            check("nothing is copied with nothing ticked", board.string(forType: .string) == nil && !showsReceipt)
            await click(NSPoint(x: 100, y: 206), in: sheet, first.source); await pause(300)
            check("a click on a source with none ticked ticks them all", ticked == Set(first.rows.map(\.id)))
            await click(NSPoint(x: 510, y: 167), in: sheet, "All"); await pause(300)
            check("All ticks everything", ticked == Set(list.rows.map(\.id)))
            await click(NSPoint(x: 251, y: bottom() - 85), in: sheet, agent.displayName); await pause(300)
            await click(NSPoint(x: 224, y: bottom() - 123), in: sheet, "Agent"); await pause(300)
            picture(sheet, "agent")
            check("the choices are remembered", defaults.string(forKey: ShareSheet.targetKey) == "agent"
                && defaults.string(forKey: ShareSheet.agentKey) == agent.id)
            await click(NSPoint(x: 72, y: bottom()), in: sheet, "Copy request"); await pause(700)
            let all = ShareCommand(list.rows.map(\.skill), agent: agent).prompt
            check("copied the request for all \(list.rows.count), for \(agent.displayName)", board.string(forType: .string) == all)
            picture(sheet, "copied-request")

            log("4. Done")
            await click(NSPoint(x: 45, y: bottom()), in: sheet, "Done"); await pause(900)
            check("the sheet closed", window.attachedSheet == nil)
            finish()
        }
    }
}
#endif
