#if DEBUG
import AppKit
import SkilloriCore
import SkilloriUI
import SwiftUI

/// Debug builds only: `SKILLORI_SNAPSHOT_DIR=/some/dir` renders the main views to PNG files
/// and quits. Lets us check the UI without screen recording permission.
/// Debug builds only: `SKILLORI_UPDATE_PLUGIN=<name@marketplace>` with `SKILLORI_UPDATE_LOG=<file>`
/// runs the real plugin update through the app's own runner, writes how it went, and quits.
@MainActor
enum DebugPluginUpdate {
    static func runIfRequested(store: InventoryStore) {
        let env = ProcessInfo.processInfo.environment
        guard let id = env["SKILLORI_UPDATE_PLUGIN"], let log = env["SKILLORI_UPDATE_LOG"] else { return }
        Task { @MainActor in
            while store.inventory == nil || store.isScanning { try? await Task.sleep(for: .milliseconds(100)) }
            guard let plugin = store.pluginRecords.first(where: { $0.id == id }) else {
                try? "no such plugin: \(id)\n".write(toFile: log, atomically: true, encoding: .utf8)
                NSApp.terminate(nil)
                return
            }
            let before = "before: \(plugin.version ?? "?") \(plugin.commit ?? "?") state \(String(describing: store.pluginReadings[id]?.state))\n"
            await store.updatePlugins([plugin])
            while store.isChecking || store.isScanning { try? await Task.sleep(for: .milliseconds(200)) }
            let after = store.pluginRecords.first { $0.id == id }
            let text = before + "phase: \(store.pluginUpdater.phase)\n"
                + "after: \(after?.version ?? "?") \(after?.commit ?? "?") state \(String(describing: store.pluginReadings[id]?.state))\n"
                + "--- output\n" + store.pluginUpdater.output
            try? text.write(toFile: log, atomically: true, encoding: .utf8)
            NSApp.terminate(nil)
        }
    }
}

@MainActor
enum DebugSnapshots {
    static func runIfRequested(store: InventoryStore, statusPanel: StatusPanelController?) {
        guard let dir = ProcessInfo.processInfo.environment["SKILLORI_SNAPSHOT_DIR"] else { return }
        Task { @MainActor in
            while store.inventory == nil || store.isScanning { try? await Task.sleep(for: .milliseconds(100)) }
            // Give the source answers (sample ones in pictures) a moment to land.
            try? await Task.sleep(for: .milliseconds(400))
            while store.isChecking || store.isAskingCodex { try? await Task.sleep(for: .milliseconds(100)) }
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
                picture(PanelBackdrop { MenuPanel(fixedModel: model).frame(width: StatusPanelController.panelWidth) }
                    .environment(store).environment(\.colorScheme, scheme),
                        size: CGSize(width: 420, height: 560), to: out.appendingPathComponent("\(name).png"))
            }
            for (step, scheme, name) in [(1, ColorScheme.light, "first-start-1"), (2, .light, "first-start-2"),
                                         (3, .light, "first-start-3"), (2, .dark, "first-start-2-dark")] {
                let view = PanelBackdrop { FirstStartView(step: step) }
                    .environment(store).environment(\.colorScheme, scheme)
                let size = CGSize(width: 400, height: 580), file = out.appendingPathComponent("\(name).png")
                // Step 2 has app icons, which only the AppKit display draws right; the others have light.
                if step == 2 { render(view, size: size, to: file) } else { picture(view, size: size, to: file) }
            }
            picture(PanelBackdrop { FirstStartView(step: 3, previewsEmpty: true) }.environment(store),
                    size: CGSize(width: 400, height: 580), to: out.appendingPathComponent("first-start-3-empty.png"))
            if ProcessInfo.processInfo.environment["SKILLORI_SNAPSHOT_OPEN_PANEL"] != nil {
                statusPanel?.open()
                try? await Task.sleep(for: .seconds(6))
            }
            let lib = CGSize(width: 1120, height: 800)
            // The library and the pages it clicks through to. AppKit draws the lists and icons but
            // not the light; `picture` draws the light but no scrolling list, so the first has both.
            for (index, (name, view)) in LibraryView.snapshots(store: store).enumerated() {
                render(view.environment(store), size: lib, to: out.appendingPathComponent("\(name).png"))
                if index == 0 { picture(view.environment(store), size: lib, to: out.appendingPathComponent("\(name)-light.png")) }
                if index == 0 || name == "library-skill-twice" {
                    render(view.environment(store).environment(\.colorScheme, .dark), size: lib,
                           to: out.appendingPathComponent("\(name)-dark.png"))
                }
            }
            let installs = store.inventory?.installations ?? []
            render(SettingsView(ownChrome: true).environment(store), size: CGSize(width: 640, height: 680),
                   to: out.appendingPathComponent("settings.png"))
            render(SettingsView(ownChrome: true).environment(store).environment(\.colorScheme, .dark),
                   size: CGSize(width: 640, height: 680), to: out.appendingPathComponent("settings-dark.png"))
            let unknown = installs.first { $0.provenance == .unknown }
            if let unknown {
                let found = InventoryStore.LinkSearch(
                    source: UpstreamSource(owner: "example", repository: "skills"), localHash: "aaa",
                    candidates: [SourceCandidate(subpath: "skills/" + unknown.directoryName, hash: "bbb", match: .sameName),
                                 SourceCandidate(subpath: "skills/docx", hash: "c", match: .other),
                                 SourceCandidate(subpath: "skills/pdf", hash: "d", match: .other),
                                 SourceCandidate(subpath: "skills/xlsx", hash: "e", match: .other)],
                    suggested: nil)
                render(LinkSourceSheet(installation: unknown).environment(store),
                       size: CGSize(width: 520, height: 250), to: out.appendingPathComponent("link-source.png"))
                render(LinkSourceSheet(installation: unknown, preview: found, text: "example/skills").environment(store),
                       size: CGSize(width: 520, height: 440), to: out.appendingPathComponent("link-source-found.png"))
            }
            // The update command: waiting to be run, and after a run that printed something.
            if let target = store.updatable.first {
                // The panel with a source opened, and after a run for that source.
                let first = PanelModel.live(from: store).groups.first
                let open = PanelBackdrop { MenuPanel(opened: Set([first?.id].compactMap { $0 })).frame(width: StatusPanelController.panelWidth) }
                picture(open.environment(store), size: CGSize(width: 420, height: 760), to: out.appendingPathComponent("panel-live-open.png"))
                // The same through AppKit: no light in the block, but the scrolling list of skills is drawn.
                render(open.environment(store), size: CGSize(width: 420, height: 760), to: out.appendingPathComponent("panel-live-open-list.png"))
                store.updater.setSample(names: (first?.updatable ?? []).map(\.directoryName), phase: .succeeded,
                                        output: "Checking 1 skill for updates\nUpdating \(target.directoryName) from its source\nUpdated 1 skill\n")
                picture(open.environment(store), size: CGSize(width: 420, height: 820), to: out.appendingPathComponent("panel-update-ran.png"))
                store.updater.setSample(names: (first?.updatable ?? []).map(\.directoryName), phase: .failed("The installer ended with code 1."),
                                        output: "Checking 18 skills for updates\nCould not reach the source\n")
                picture(PanelBackdrop { MenuPanel().frame(width: StatusPanelController.panelWidth) }.environment(store),
                        size: CGSize(width: 420, height: 820), to: out.appendingPathComponent("panel-update-failed.png"))
                // One skill run from its own button: while it runs, and when it went wrong.
                store.updater.setSample(names: [target.directoryName], phase: .running, output: "Checking 1 skill for updates\n")
                render(open.environment(store), size: CGSize(width: 420, height: 820), to: out.appendingPathComponent("panel-update-one-running.png"))
                store.updater.setSample(names: [target.directoryName], phase: .failed("The installer ended with code 1."),
                                        output: "Checking 1 skill for updates\nCould not reach the source\n")
                render(open.environment(store), size: CGSize(width: 420, height: 820), to: out.appendingPathComponent("panel-update-one-failed.png"))
                store.updater.setSample(names: [], phase: .idle, output: "")
            }
            let icon = ImageRenderer(content: AppIconArt())
            icon.scale = AppIconArt.scale
            if let image = icon.cgImage {
                try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?
                    .write(to: out.appendingPathComponent("app-icon-1024.png"))
            }
            picture(MarkSheet(), size: CGSize(width: 1280, height: 460), to: out.appendingPathComponent("mark.png"))
            NSApp.terminate(nil)
        }
    }

    /// For views SwiftUI draws alone, such as the panel. Unlike a cached AppKit display this
    /// also draws shaders, so the light in a block shows in the picture.
    private static func picture(_ view: some View, size: CGSize, to url: URL) {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 2
        guard let image = renderer.cgImage else { return }
        try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: url)
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
        LightField(.meadow, radius: side * 100 / 820, still: true, easedThroughout: true)
            .overlay(SkilloriMark(safeZone: true).fill(.white))
            .frame(width: side, height: side)
    }

    private func bar(light: Bool, scale: CGFloat) -> some View {
        HStack(spacing: 8 * scale) {
            ForEach([SkilloriMark.MenuBarState.rest, .new, .attention, .stale], id: \.self) { state in
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

/// The app icon at 1024 px: macOS's standard plate (824 px, continuous corners) filled with the
/// Meadow light, with the mark's full grid on it in white, so the safe zone is the distance to
/// the plate's edge. It is drawn at a quarter of its pixel size and rendered at four times scale,
/// so the light's bevel has the proportions it has on a block in the app.
struct AppIconArt: View {
    static let scale: CGFloat = 4

    var body: some View {
        LightField(.meadow, radius: 185.4 / Self.scale, corners: .continuous, still: true, easedThroughout: true)
            .overlay(SkilloriMark(safeZone: true).fill(.white))
            .frame(width: 824 / Self.scale, height: 824 / Self.scale)
            .frame(width: 1024 / Self.scale, height: 1024 / Self.scale)
    }
}
#endif
