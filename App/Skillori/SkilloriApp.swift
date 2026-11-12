import AppKit
import SkilloriUI
import SwiftUI

@main
struct SkilloriApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // The menu bar item, the panel and the windows are owned by `AppDelegate`.
        // SwiftUI needs one scene; Settings also gives the standard ⌘, behaviour.
        Settings {
            SettingsView()
                .environment(delegate.store)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = InventoryStore()
    private(set) var windows: WindowRouter?
    private var statusPanel: StatusPanelController?
    private var firstStart: FirstStartController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        SkilloriFonts.register()
        AppearanceSetting.current.apply()
        let windows = WindowRouter(store: store)
        self.windows = windows
        statusPanel = StatusPanelController(store: store, windows: windows)
        let firstStart = FirstStartController(store: store, windows: windows)
        self.firstStart = firstStart
        NotificationCenter.default.addObserver(forName: .showFirstStart, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.firstStart?.show() }
        }
        let env = ProcessInfo.processInfo.environment
        if env["SKILLORI_SNAPSHOT_DIR"] == nil, env["SKILLORI_SELFTEST"] == nil { firstStart.showIfNeeded() }
        #if DEBUG
        DebugSnapshots.runIfRequested(store: store, statusPanel: statusPanel)
        if let statusPanel { DebugSelfTest.runIfRequested(store: store, panel: statusPanel, windows: windows) }
        #endif
    }
}

/// Opens the app's ordinary windows. They are created on first use and kept.
@MainActor
final class WindowRouter {
    private let store: InventoryStore
    private(set) var library: NSWindow?
    private(set) var settings: NSWindow?

    init(store: InventoryStore) { self.store = store }

    func showLibrary() {
        if library == nil {
            library = makeWindow(title: "Skillori Library", size: NSSize(width: 1120, height: 760),
                                 minSize: NSSize(width: 900, height: 520), resizable: true, ownChrome: true,
                                 content: LibraryView().environment(store))
        }
        present(library)
    }

    func showSettings() {
        if settings == nil {
            settings = makeWindow(title: "Settings", size: NSSize(width: 640, height: 420),
                                  minSize: nil, resizable: false, ownChrome: true,
                                  content: SettingsView(ownChrome: true).environment(store))
        }
        present(settings)
    }

    private func present(_ window: NSWindow?) {
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    private func makeWindow(title: String, size: NSSize, minSize: NSSize?, resizable: Bool,
                            ownChrome: Bool = false, content: some View) -> NSWindow {
        var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
        if resizable { style.insert(.resizable) }
        if ownChrome { style.insert(.fullSizeContentView) }
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: style,
                              backing: .buffered, defer: false)
        if ownChrome {
            // The view draws its own top bar. An empty unified toolbar gives the taller title
            // bar that centres the window buttons on that bar.
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.toolbar = NSToolbar()
            window.toolbarStyle = .unified
            window.backgroundColor = NSColor(Palette.panel)
        }
        window.title = title
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: content)
        if resizable { window.setContentSize(size) }
        if let minSize { window.contentMinSize = minSize }
        window.center()
        return window
    }
}
