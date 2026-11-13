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
                ("state-no-reading", .sampleNoReading, .light), ("state-nothing-found", .sampleNothingFound, .light),
                ("state-no-access", .sampleNoAccess, .light),
            ]
            for (name, model, scheme) in states {
                render(PanelBackdrop { MenuPanel(fixedModel: model).frame(width: StatusPanelController.panelWidth) }
                    .environment(store).environment(\.colorScheme, scheme),
                       size: CGSize(width: 420, height: 470), to: out.appendingPathComponent("\(name).png"))
            }
            for (step, scheme, name) in [(1, ColorScheme.light, "first-start-1"), (2, .light, "first-start-2"),
                                         (3, .light, "first-start-3"), (2, .dark, "first-start-2-dark")] {
                render(PanelBackdrop { FirstStartView(step: step) }
                    .environment(store).environment(\.colorScheme, scheme),
                       size: CGSize(width: 400, height: 580), to: out.appendingPathComponent("\(name).png"))
            }
            if ProcessInfo.processInfo.environment["SKILLORI_SNAPSHOT_OPEN_PANEL"] != nil {
                statusPanel?.open()
                try? await Task.sleep(for: .seconds(6))
            }
            let lib = CGSize(width: 1120, height: 800)
            let installs = store.inventory?.installations ?? []
            let tracked = installs.first { if case .skillsLock = $0.provenance { true } else { false } }
            render(LibraryView().environment(store), size: lib, to: out.appendingPathComponent("library.png"))
            render(LibraryView(initialSelection: tracked?.id).environment(store), size: lib,
                   to: out.appendingPathComponent("library-selected.png"))
            render(LibraryView(initialSelection: tracked?.id).environment(store).environment(\.colorScheme, .dark),
                   size: lib, to: out.appendingPathComponent("library-dark.png"))
            render(LibraryView(initialFilter: .managed).environment(store), size: lib,
                   to: out.appendingPathComponent("library-managed.png"))
            render(LibraryView(initialFilter: .coverage).environment(store), size: lib,
                   to: out.appendingPathComponent("coverage.png"))
            render(LibraryView(initialSelection: tracked?.id, showsDetail: true).environment(store), size: lib,
                   to: out.appendingPathComponent("detail.png"))
            render(LibraryView(initialSelection: tracked?.id, showsDetail: true).environment(store)
                .environment(\.colorScheme, .dark), size: lib, to: out.appendingPathComponent("detail-dark.png"))
            render(SettingsView(ownChrome: true).environment(store), size: CGSize(width: 640, height: 580),
                   to: out.appendingPathComponent("settings.png"))
            render(SettingsView(ownChrome: true).environment(store).environment(\.colorScheme, .dark),
                   size: CGSize(width: 640, height: 580), to: out.appendingPathComponent("settings-dark.png"))
            let unknown = installs.first { $0.provenance == .unknown }
            render(LibraryView(initialSelection: unknown?.id, showsDetail: true).environment(store), size: lib,
                   to: out.appendingPathComponent("detail-unknown.png"))
            let icon = ImageRenderer(content: AppIconArt())
            icon.scale = 1
            if let image = icon.cgImage {
                try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?
                    .write(to: out.appendingPathComponent("app-icon-1024.png"))
            }
            render(MarkSheet(), size: CGSize(width: 1040, height: 460), to: out.appendingPathComponent("mark.png"))
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

/// Stand-in for the desktop behind the panel.
private struct PanelBackdrop<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    @ViewBuilder var content: Content
    var body: some View {
        ZStack(alignment: .top) {
            scheme == .dark ? Color(hex: 0x0E0E0F) : Color(hex: 0xE6E6E8)
            content.padding(.top, 28)
        }
        .clipped()
    }
}
#endif

/// The mark as app icon and as menu bar image, at real size and enlarged.
private struct MarkSheet: View {
    var body: some View {
        HStack(spacing: 32) {
            appIcon(side: 328)
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) { appIcon(side: 64); appIcon(side: 32); appIcon(side: 16) }
                bar(light: true, scale: 6)
                bar(light: false, scale: 6)
                bar(light: true, scale: 1)
                bar(light: false, scale: 1)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: 0xE6E6E8))
    }

    private func appIcon(side: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: side * 100 / 820, style: .circular)
            .fill(.black)
            .overlay(SkilloriMark(safeZone: true).fill(.white))
            .frame(width: side, height: side)
    }

    private func bar(light: Bool, scale: CGFloat) -> some View {
        HStack(spacing: 8 * scale) {
            ForEach([SkilloriMark.MenuBarState.rest, .attention, .stale], id: \.self) { state in
                // The image the menu bar really gets; template states take the bar's colour.
                Image(nsImage: SkilloriMark.menuBarImage(state, side: 22 * scale))
                    .foregroundStyle(light ? Color.white : Color.black)
            }
        }
        .padding(.horizontal, 8 * scale)
        .frame(height: 24 * scale)
        .background(light ? Color(hex: 0x8E8E93) : Color(hex: 0xD8D8DC))
    }
}

/// The app icon at 1024 px: macOS's standard plate (824 px, continuous corners) in black,
/// with the mark's full grid on it, so the safe zone is the distance to the plate's edge.
struct AppIconArt: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 185.4, style: .continuous)
            .fill(.black)
            .overlay(SkilloriMark(safeZone: true).fill(.white))
            .frame(width: 824, height: 824)
            .frame(width: 1024, height: 1024)
    }
}
