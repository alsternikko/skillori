#if DEBUG
import AppKit

/// Debug builds only: `SKILLORI_LIBRARY_PROBE=/some/file` opens the library and clicks its top
/// bar with mouse events posted to the app, the way the window server hands them over: on the
/// first home, and again after a visit to Your skills. One line per step, with the view the
/// window's hit test lands on, and a picture of the window after each step.
@MainActor
enum DebugLibraryProbe {
    /// Asks the library to open a page, as a click on its door would.
    static let openPage = Notification.Name("DebugLibraryProbe.openPage")
    /// The library's pages as it shows them now.
    static var path: [LibraryPage] = []

    static func runIfRequested(store: InventoryStore, windows: WindowRouter) {
        guard let path = ProcessInfo.processInfo.environment["SKILLORI_LIBRARY_PROBE"] else { return }
        Task { @MainActor in
            var lines: [String] = []
            @MainActor func log(_ line: String) {
                lines.append(line)
                try? lines.joined(separator: "\n").appending("\n").write(toFile: path, atomically: true, encoding: .utf8)
            }
            @MainActor func pause(_ ms: Int) async { try? await Task.sleep(for: .milliseconds(ms)) }

            while store.inventory == nil || store.isScanning { await pause(100) }
            windows.showLibrary()
            await pause(700)
            guard let window = windows.library, let content = window.contentView else { log("no library window"); NSApp.terminate(nil); return }
            log("window key: \(window.isKeyWindow), app active: \(NSApp.isActive), content \(Int(content.bounds.width))×\(Int(content.bounds.height))")

            var step = 0
            @MainActor func picture(_ name: String) {
                step += 1
                guard let frameView = content.superview,
                      let rep = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) else { return }
                frameView.cacheDisplay(in: frameView.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?
                    .write(to: URL(fileURLWithPath: path + ".\(step)-\(name).png"))
            }
            // Where the controls are, measured from the top left of the window's content, in points.
            let width = content.bounds.width, height = content.bounds.height
            // The hosting view counts from the top; an unflipped view from the bottom.
            @MainActor func top(_ y: CGFloat) -> CGFloat { content.isFlipped ? y : height - y }
            let places: [String: NSPoint] = [
                "Folders": NSPoint(x: width - 150, y: top(26)),
                "Check now": NSPoint(x: width - 56, y: top(26)),
                "‹ Library": NSPoint(x: 50, y: top(73)),
            ]
            @MainActor func hit(_ name: String) -> String {
                let point = places[name]!
                let view = content.superview?.hitTest(content.convert(point, to: nil))
                var chain: [String] = []
                var walker = view
                while let current = walker, chain.count < 4 { chain.append(String(describing: type(of: current))); walker = current.superview }
                return chain.joined(separator: " < ")
            }
            @MainActor func click(_ name: String) {
                let point = content.convert(places[name]!, to: nil)
                log("  click \(name): hit \(hit(name))")
                for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                    if let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                                                      timestamp: ProcessInfo.processInfo.systemUptime,
                                                      windowNumber: window.windowNumber, context: nil,
                                                      eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0) {
                        NSApp.postEvent(event, atStart: false)
                    }
                }
            }
            /// The scroll views AppKit holds for SwiftUI, with their frames in the window's content, from the top.
            @MainActor func scrollers() -> String {
                var found: [String] = []
                @MainActor func walk(_ view: NSView) {
                    if view is NSScrollView {
                        let frame = view.convert(view.bounds, to: content)
                        let y = content.isFlipped ? frame.minY : height - frame.maxY
                        found.append("y \(Int(y))…\(Int(y + frame.height)) x \(Int(frame.minX))…\(Int(frame.maxX)) inset top \(Int((view as! NSScrollView).contentInsets.top))")
                    }
                    for sub in view.subviews { walk(sub) }
                }
                walk(content)
                return found.isEmpty ? "none" : found.joined(separator: "; ")
            }
            @MainActor func showing() -> String { DebugLibraryProbe.path.isEmpty ? "home" : "\(DebugLibraryProbe.path)" }

            picture("home")
            log("   scroll views on home: \(scrollers())")
            log("   safe area top: \(Int(content.safeAreaInsets.top))")
            log("1. Folders on the first home")
            click("Folders"); await pause(500)
            log("   now: \(showing())")
            click("‹ Library"); await pause(500)
            log("   back: \(showing())")

            log("2. Into Your skills, back with the crumb")
            NotificationCenter.default.post(name: openPage, object: LibraryPage.mine); await pause(600)
            log("   now: \(showing())")
            log("   scroll views on mine: \(scrollers())")
            click("Folders"); await pause(500)
            log("   Folders on mine → now: \(showing())")
            NotificationCenter.default.post(name: openPage, object: LibraryPage.home); await pause(500)
            NotificationCenter.default.post(name: openPage, object: LibraryPage.mine); await pause(600)
            picture("mine")
            click("‹ Library"); await pause(600)
            log("   back: \(showing())")
            picture("home-again")

            log("3. Folders after coming back")
            click("Folders"); await pause(500)
            log("   now: \(showing())")
            picture("after")
            if !DebugLibraryProbe.path.isEmpty { click("‹ Library"); await pause(500) }

            log("4. Check now after coming back")
            let before = store.inventory?.scannedAt
            click("Check now")
            for _ in 0..<30 where store.inventory?.scannedAt == before { await pause(100) }
            log("   read again: \(store.inventory?.scannedAt != before)")
            NSApp.terminate(nil)
        }
    }
}
#endif
