#if DEBUG
import AppKit
import SkilloriUI
import SwiftUI

/// Debug builds only: `SKILLORI_SNAPSHOT_DIR=/some/dir` renders the main views to PNG files
/// and quits. Lets us check the UI without screen recording permission.
@MainActor
enum DebugSnapshots {
    static func runIfRequested(store: InventoryStore, statusPanel: StatusPanelController?) {
        guard let dir = ProcessInfo.processInfo.environment["SKILLORI_SNAPSHOT_DIR"] else { return }
        Task { @MainActor in
            while store.inventory == nil || store.isScanning { try? await Task.sleep(for: .milliseconds(100)) }
            let out = URL(fileURLWithPath: dir)
            let states: [(String, PanelModel?, ColorScheme)] = [
                ("panel-live", nil, .light), ("panel-live-dark", nil, .dark),
                ("panel-updates", .sampleUpdates, .light), ("panel-in-sync", .sampleInSync, .light),
                ("panel-no-contact", .sampleNoContact, .light), ("panel-updates-dark", .sampleUpdates, .dark),
                ("panel-in-sync-dark", .sampleInSync, .dark),
            ]
            for (name, model, scheme) in states {
                render(PanelBackdrop { MenuPanel(fixedModel: model).frame(width: StatusPanelController.panelWidth) }
                    .environment(store).environment(\.colorScheme, scheme),
                       size: CGSize(width: 420, height: 470), to: out.appendingPathComponent("\(name).png"))
            }
            if ProcessInfo.processInfo.environment["SKILLORI_SNAPSHOT_OPEN_PANEL"] != nil {
                statusPanel?.open()
                try? await Task.sleep(for: .seconds(6))
            }
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

/// Stand-in for the desktop behind the panel, with the sketch's shapes. Snapshots cannot
/// capture the window's real blur, so this shows the tint over flat colour only.
private struct PanelBackdrop<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    @ViewBuilder var content: Content
    var body: some View {
        ZStack(alignment: .top) {
            scheme == .dark ? Color(hex: 0x0E0E0F) : Color(hex: 0xD4D4D9)
            Circle().fill(Palette.lime).frame(width: 300).offset(x: 190, y: -170)
            Circle().fill(Palette.charcoal).frame(width: 360).offset(x: -210, y: 300)
            content.padding(.top, 28)
        }
        .clipped()
    }
}
#endif
