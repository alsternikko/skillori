#if DEBUG
import AppKit
import SwiftUI

/// Debug builds only: `SKILLORI_SNAPSHOT_DIR=/some/dir` renders the main views to PNG files
/// and quits. Lets us check the UI without screen recording permission.
@MainActor
enum DebugSnapshots {
    static func runIfRequested(store: InventoryStore) {
        guard let dir = ProcessInfo.processInfo.environment["SKILLORI_SNAPSHOT_DIR"] else { return }
        Task { @MainActor in
            while store.inventory == nil || store.isScanning { try? await Task.sleep(for: .milliseconds(100)) }
            let out = URL(fileURLWithPath: dir)
            render(MenuPanel().environment(store), size: CGSize(width: 280, height: 380), to: out.appendingPathComponent("panel.png"))
            render(LibraryView().environment(store), size: CGSize(width: 1040, height: 640), to: out.appendingPathComponent("library.png"))
            render(LibraryView(initialFilter: .coverage).environment(store), size: CGSize(width: 1040, height: 640),
                   to: out.appendingPathComponent("coverage.png"))
            if let tracked = store.inventory?.installations.first(where: { if case .skillsLock = $0.provenance { true } else { false } }) {
                render(LibraryView(initialSelection: tracked.id).environment(store), size: CGSize(width: 1040, height: 640),
                       to: out.appendingPathComponent("detail.png"))
            }
            NSApp.terminate(nil)
        }
    }

    private static func render(_ view: some View, size: CGSize, to url: URL) {
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -4000, y: -4000), size: size),
                              styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        window.contentView = host
        window.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        window.orderOut(nil)
    }
}
#endif
