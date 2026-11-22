#if DEBUG
import AppKit
import SwiftUI

/// Debug builds only: `SKILLORI_PANEL_PROBE=/some/file` checks that the panel follows its
/// content's height without shaking. It opens the panel, opens and closes the first source's
/// list with clicks posted to the panel, then plays a run (output arriving line by line, then
/// done, then a fresh reading) without starting the installer. Every frame of the panel window
/// is written down with the time, followed by one PASS/FAIL line per check.
///
/// `SKILLORI_PANEL_PROBE_ROW` is where the source's row is, in points from the panel's top
/// (265 by default, right under the hero). `SKILLORI_PANEL_PROBE_SKILL` names a skill of that
/// source, so the played run reports in its command frame.
///
/// Found with it (2026-11-19): the hosting view also sized the window through Auto Layout, so
/// each printed line pushed the content 16–33 pt up before the window caught up, and the
/// window's animator rounded origin and height apart, so the top edge wavered by a point.
@MainActor
enum DebugPanelProbe {
    static func runIfRequested(store: InventoryStore, panel: StatusPanelController) {
        guard let path = ProcessInfo.processInfo.environment["SKILLORI_PANEL_PROBE"] else { return }
        let rowY = Double(ProcessInfo.processInfo.environment["SKILLORI_PANEL_PROBE_ROW"] ?? "") ?? 265
        Task { @MainActor in
            let book = Book(path: path)
            @MainActor func pause(_ ms: Int) async { try? await Task.sleep(for: .milliseconds(ms)) }

            while store.inventory == nil || store.isScanning { await pause(100) }
            for _ in 0..<50 where (panel.statusButton?.window?.frame.minY ?? 0) <= 0 { await pause(100) }

            let window = panel.panelWindow
            guard let container = window.contentView, let host = container.subviews.first else {
                book.log("no panel"); NSApp.terminate(nil); return
            }
            let recorder = Timer(timeInterval: 0.004, repeats: true) { _ in
                MainActor.assumeIsolated { book.record(window: window.frame, host: host.frame, container: container.bounds) }
            }
            RunLoop.main.add(recorder, forMode: .common)

            /// The panel as it looks, next to the log; works off screen too.
            @MainActor func picture(_ name: String) {
                guard let rep = container.bitmapImageRepForCachingDisplay(in: container.bounds) else { return }
                container.cacheDisplay(in: container.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path + ".\(name).png"))
            }
            @MainActor func click(_ y: CGFloat) {
                let local = NSPoint(x: 120, y: host.isFlipped ? y : host.bounds.height - y)
                let point = host.convert(local, to: nil)
                book.log("   hit \(container.hitTest(container.convert(point, from: nil)).map { String(describing: type(of: $0)).prefix(40) } ?? "nothing"), panel key \(window.isKeyWindow)")
                for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                    if let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                                                      timestamp: ProcessInfo.processInfo.systemUptime,
                                                      windowNumber: window.windowNumber, context: nil,
                                                      eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0) {
                        NSApp.postEvent(event, atStart: false)
                    }
                }
            }
            @MainActor func settled(_ name: String) {
                let wanted = panel.contentHeight.rounded(.up)
                // Shorter only when the room under the menu bar runs out.
                book.check("\(name): window as tall as its content", abs(window.frame.height - wanted) < 0.5 || window.frame.height < wanted,
                           "window \(window.frame.height), content \(panel.contentHeight)")
            }

            book.log("-- open panel")
            panel.open()
            await pause(600)
            let top = window.frame.maxY
            book.top = top
            let closedHeight = window.frame.height
            settled("opened")
            picture("1-opened")

            book.log("-- click source row (open list) at y \(Int(rowY))")
            book.mark()
            click(rowY)
            await pause(900)
            picture("2-after-click")
            book.log("   panel at x \(Int(window.frame.minX)), open: \(panel.isOpen), other windows: \(NSApp.windows.filter { $0.isVisible && $0 !== window && !$0.title.isEmpty }.map { "\($0.title) at x \(Int($0.frame.minX))" })")
            let openedHeight = window.frame.height
            book.check("list opens: the panel grows", openedHeight > closedHeight, "\(closedHeight) → \(openedHeight)")
            book.check("list opens: the growth is eased", book.distinctHeightsSinceMark() >= 4, "\(book.distinctHeightsSinceMark()) heights")
            settled("list open")

            book.log("-- click source row (close list)")
            book.mark()
            click(rowY)
            await pause(900)
            book.check("list closes: back to the first height", window.frame.height == closedHeight, "\(window.frame.height)")
            book.check("list closes: the shrink is eased", book.distinctHeightsSinceMark() >= 4, "\(book.distinctHeightsSinceMark()) heights")

            if let name = ProcessInfo.processInfo.environment["SKILLORI_PANEL_PROBE_SKILL"] ?? store.inventory?.installations.first?.directoryName {
                book.log("-- run starts (played, \(name))")
                store.updater.setSample(names: [name], phase: .running, output: "")
                await pause(120)
                var output = ""
                for line in ["Updating \(name)…", "Fetching source", "Copying files", "Done: 1 skill updated"] {
                    output += line + "\n"
                    book.log("-- output: \(line)")
                    store.updater.setSample(names: [name], phase: .running, output: output)
                    await pause(70)
                }
                book.log("-- run ends")
                store.updater.setSample(names: [name], phase: .succeeded, output: output)
                await pause(400)
                settled("run ended")
                book.log("-- refresh")
                await store.refresh()
                await pause(900)
                settled("read again")
            }
            recorder.invalidate()
            book.check("the top edge never moved", book.topMoves == 0, "\(book.topMoves) frames off \(top)")
            book.check("the content always fills the window from its top", book.hostOff == 0, "\(book.hostOff) frames off")
            book.log("-- end")
            NSApp.terminate(nil)
        }
    }

    @MainActor
    final class Book {
        let path: String
        let t0 = ProcessInfo.processInfo.systemUptime
        var lines: [String] = []
        var top: CGFloat?
        var topMoves = 0
        var hostOff = 0
        private var last = NSRect.zero
        private var lastHost = NSRect.zero
        private var heights: [CGFloat] = []

        init(path: String) { self.path = path }

        func log(_ line: String) {
            let ms = Int((ProcessInfo.processInfo.systemUptime - t0) * 1000)
            lines.append(String(format: "%6d  ", ms) + line)
            write()
        }

        func check(_ name: String, _ ok: Bool, _ note: String = "") {
            lines.append("\(ok ? "PASS" : "FAIL")  \(name)\(note.isEmpty ? "" : "  (\(note))")")
            write()
        }

        func record(window f: NSRect, host h: NSRect, container: NSRect) {
            guard f != last || h != lastHost else { return }
            log(String(format: "   frame top %.2f bottom %.2f h %.2f   host y %.2f h %.2f", f.maxY, f.minY, f.height, h.minY, h.height))
            last = f; lastHost = h
            if f.height != heights.last { heights.append(f.height) }
            if let top, f.maxY != top { topMoves += 1 }
            if top != nil, h != container { hostOff += 1 }
        }

        func mark() { heights = [] }
        func distinctHeightsSinceMark() -> Int { heights.count }

        private func write() {
            try? lines.joined(separator: "\n").appending("\n").write(toFile: path, atomically: true, encoding: .utf8)
        }
    }
}
#endif
