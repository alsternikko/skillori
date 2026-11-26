#if DEBUG
import AppKit

/// Debug builds only: `SKILLORI_SELFTEST=/some/file` drives the panel from inside the app
/// and writes one PASS/FAIL line per check. It sends real key events to the panel window.
/// It cannot produce a real mouse click from outside the app; that needs Accessibility access.
@MainActor
enum DebugSelfTest {
    static func runIfRequested(store: InventoryStore, panel: StatusPanelController, windows: WindowRouter) {
        guard let path = ProcessInfo.processInfo.environment["SKILLORI_SELFTEST"] else { return }
        Task { @MainActor in
            var lines: [String] = []
            @MainActor func check(_ name: String, _ ok: Bool, _ note: String = "") {
                lines.append("\(ok ? "PASS" : "FAIL")  \(name)\(note.isEmpty ? "" : "  (\(note))")")
                try? lines.joined(separator: "\n").appending("\n").write(toFile: path, atomically: true, encoding: .utf8)
            }
            @MainActor func pause(_ ms: Int) async { try? await Task.sleep(for: .milliseconds(ms)) }
            @MainActor func key(_ chars: String, code: UInt16, command: Bool) {
                guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero,
                                                   modifierFlags: command ? .command : [],
                                                   timestamp: ProcessInfo.processInfo.systemUptime,
                                                   windowNumber: panel.panelWindow.windowNumber, context: nil,
                                                   characters: chars, charactersIgnoringModifiers: chars,
                                                   isARepeat: false, keyCode: code) else { return }
                NSApp.sendEvent(event)
            }

            while store.inventory == nil || store.isScanning { await pause(100) }
            // The system places the menu bar item a moment after launch.
            for _ in 0..<50 where (panel.statusButton?.window?.frame.minY ?? 0) <= 0 { await pause(100) }

            check("menu bar item has the mark", panel.statusButton?.image != nil)

            panel.open()
            await pause(400)
            // Measured where the panel would be: a quiet run moves it off screen.
            let frame = panel.panelWindow.frame.offsetBy(dx: DebugQuiet.isOn ? -DebugQuiet.shift : 0, dy: 0)
            check("panel opens", panel.isOpen)
            check("panel takes keyboard focus", panel.panelWindow.isKeyWindow)
            check("panel is fully opaque after opening", panel.panelWindow.alphaValue == 1, "alpha \(panel.panelWindow.alphaValue)")
            check("content is back at full size after opening",
                  panel.panelWindow.contentView?.subviews.first?.layer.map { CATransform3DIsIdentity($0.transform) } ?? false)
            check("panel is 332 pt wide", abs(frame.width - 332) < 0.5, "\(frame.width) × \(frame.height)")
            if let button = panel.statusButton, let window = button.window {
                let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
                check("panel hangs under the menu bar item", abs(frame.maxY - (anchor.minY - 6)) < 1
                      && frame.minX <= anchor.midX && frame.maxX >= anchor.midX,
                      "panel \(frame), item \(anchor), screen \(window.screen?.visibleFrame ?? .zero)")
            }

            let before = store.inventory?.scannedAt
            key("r", code: 15, command: true)
            var rescanned = false
            for _ in 0..<60 where !rescanned {
                await pause(100)
                rescanned = store.inventory?.scannedAt != before
            }
            check("⌘R reads again", rescanned)
            check("panel stays open after ⌘R", panel.isOpen)

            key("\u{1B}", code: 53, command: false)
            await pause(300)
            check("Escape closes the panel", !panel.isOpen)

            panel.open()
            await pause(300)
            key(",", code: 43, command: true)
            await pause(500)
            check("⌘, opens Settings", windows.settings?.isVisible == true)
            check("panel closes when Settings opens", !panel.isOpen)
            let settingsHeight = windows.settings?.frame.height ?? 0
            if let view = windows.settings?.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds),
               let path = ProcessInfo.processInfo.environment["SKILLORI_SELFTEST"] {
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path + ".settings.png"))
            }
            // The shell runner behind "Run": output comes back, arguments stay arguments, failure is reported.
            let printed = OutputBox()
            let ok = await Shell.run(script: "printf '%s\\n' \"$1\" \"$2\"", arguments: ["one", "two; echo injected"], timeout: 20) { printed.add($0) }
            check("shell runs a command and returns what it prints", ok == 0 && printed.text == "one\ntwo; echo injected\n", printed.text.debugDescription)
            let failing = await Shell.run(script: "exit 3", timeout: 20)
            check("shell reports a failing command", failing == 3, "status \(failing)")
            // A background process that keeps the pipe open must not keep the run from ending.
            let started = Date()
            let detached = await Shell.run(script: "sleep 30 & echo done", timeout: 20)
            let waited = Date().timeIntervalSince(started)
            check("a process left in the background does not hold up the run", detached == 0 && waited < 5,
                  String(format: "%.1f s", waited))
            let stopper = ShellControl()
            let stopStart = Date()
            Task { try? await Task.sleep(for: .milliseconds(300)); stopper.stop() }
            let stopped = await Shell.run(script: "sleep 30", timeout: 20, control: stopper)
            check("Stop ends a running command at once", stopper.wasStopped && Date().timeIntervalSince(stopStart) < 5,
                  "status \(stopped)")
            var chunks = UTF8Chunks()
            let euro = Data("€".utf8)
            let joined = chunks.text(from: euro.prefix(2)) + chunks.text(from: euro.suffix(1))
            check("a character split between two chunks is kept whole", joined == "€", joined.debugDescription)
            let npx = await Shell.run(script: "command -v npx >/dev/null", timeout: 20)
            check("shell finds npx the way Terminal does", npx == 0, "status \(npx)")
            // What the scan asks the login shell for: set variables come back, unset ones do not.
            let asked = Date()
            let values = await InventoryStore.loginShellValues(of: ["HOME", "SKILLORI_NEVER_SET"])
            check("login shell gives the variables it has set and leaves out the rest",
                  values == ["HOME": NSHomeDirectory()],
                  "\(values) in \(Int(Date().timeIntervalSince(asked) * 1000)) ms")
            let runner = UpdateRunner()
            runner.append("Checking\rUpdating 1\rUpdating 2\n\u{1B}[32mDone\u{1B}[0m\n")
            check("printed text is shown as a terminal would", runner.output == "Updating 2\nDone\n", runner.output.debugDescription)
            check("unsafe skill names are refused", !UpdateRunner.isSafeName("a; rm -rf x") && !UpdateRunner.isSafeName("-g") && !UpdateRunner.isSafeName("..") && UpdateRunner.isSafeName("find-skills"))
            check("Settings window fits its content", settingsHeight > 300 && settingsHeight < 800, "height \(settingsHeight)")
            windows.settings?.close()

            panel.open()
            await pause(300)
            windows.showLibrary()
            await pause(500)
            check("panel closes when another window takes focus", !panel.isOpen)
            check("Library window opens", windows.library?.isVisible == true)
            windows.library?.close()
            // Closing a window moves focus; let that settle so it cannot close the panel opened next.
            await pause(400)

            panel.open()
            await pause(300)
            panel.open()
            await pause(200)
            check("opening twice keeps one panel", panel.isOpen)
            panel.close()
            check("close() closes", !panel.isOpen)
            await pause(300)
            check("window is gone after the fade-out", !panel.panelWindow.isVisible)
            panel.open()
            panel.close()
            panel.open()
            await pause(400)
            check("reopening during the fade-out leaves the panel open and opaque",
                  panel.isOpen && panel.panelWindow.isVisible && panel.panelWindow.alphaValue == 1)
            panel.close(animated: false)
            check("immediate close removes the window at once", !panel.panelWindow.isVisible)

            let menu = panel.makeContextMenu()
            let titles = menu.items.filter { !$0.isSeparatorItem }.map(\.title)
            // "Check for Updates…" is there only in a build that can update itself.
            check("right-click menu has Library, Settings, Quit",
                  titles.filter { $0 != "Check for Updates…" } == ["Open Library…", "Settings…", "Quit Skillori"],
                  titles.joined(separator: ", "))
            if let item = menu.items.first(where: { $0.title == "Settings…" }), let action = item.action {
                NSApp.sendAction(action, to: item.target, from: item)
                await pause(400)
                check("menu item Settings… opens Settings", windows.settings?.isVisible == true)
                windows.settings?.close()
            }
            if let item = menu.items.first(where: { $0.title == "Open Library…" }), let action = item.action {
                NSApp.sendAction(action, to: item.target, from: item)
                await pause(400)
                check("menu item Open Library… opens the Library", windows.library?.isVisible == true)
                windows.library?.close()
            }
            // Reading an install script, without linking: only runs when the skill is on this Mac.
            if let craft = store.inventory?.installations.first(where: { $0.directoryName == "interface-craft" && $0.provenance == .unknown }) {
                let pasted = "curl -fsSL https://www.interfacecraft.dev/api/install-skills | bash"
                // Read as a source while the script is there; since 2026-11-26 it answers 410 and
                // says where it moved, which is followed instead of reported as not found.
                switch await store.searchSource(pasted, for: craft) {
                case .success(let search):
                    check("install script is read as a source", search.candidates.first?.subpath == "interface-craft",
                          "\(search.candidates.first.map { "\($0.subpath) \($0.match)" } ?? "none")")
                case .failure(.moved(let notice)):
                    check("a moved install script says where it went", notice.url != nil, "\(notice.message) → \(notice.url?.absoluteString ?? "no address")")
                    if let url = notice.url {
                        let page = await store.readPage(url)
                        check("the page it moved to is read", { if case .success = page { true } else { false } }(), "\(page)")
                    }
                case .failure(let problem):
                    check("install script is read as a source", false, problem.sentence)
                }
                // A key kept for its installer is offered when the link was lost.
                if let group = await store.unlinkedGroups(only: [craft.id]).first {
                    check("a kept installer key is offered", true, store.keptKeys(for: group).joined(separator: ", "))
                }
            }

            let quit = menu.items.first { $0.title == "Quit Skillori" }
            check("menu item Quit targets the app", quit?.action == #selector(NSApplication.terminate(_:)))

            panel.open()
            await pause(300)
            check("about to send ⌘Q (process must exit after this line)", panel.isOpen)
            key("q", code: 12, command: true)
            await pause(1500)
            check("⌘Q quits", false, "still running")
        }
    }
}
#endif

#if DEBUG
/// Collects what a shell command prints, from whichever thread it arrives on.
private final class OutputBox: @unchecked Sendable {
    private let lock = NSLock()
    private var collected = ""
    func add(_ text: String) { lock.withLock { collected += text } }
    var text: String { lock.withLock { collected } }
}
#endif
