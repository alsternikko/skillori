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

    func applicationDidFinishLaunching(_ notification: Notification) {
        SkilloriFonts.register()
        let windows = WindowRouter(store: store)
        self.windows = windows
        statusPanel = StatusPanelController(store: store, windows: windows)
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
            library = makeWindow(title: "Skillori Library", size: NSSize(width: 1040, height: 640),
                                 minSize: NSSize(width: 820, height: 480), resizable: true,
                                 content: LibraryView().environment(store))
        }
        present(library)
    }

    func showSettings() {
        if settings == nil {
            settings = makeWindow(title: "Settings", size: NSSize(width: 520, height: 420),
                                  minSize: nil, resizable: false,
                                  content: SettingsView().environment(store))
        }
        present(settings)
    }

    private func present(_ window: NSWindow?) {
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    private func makeWindow(title: String, size: NSSize, minSize: NSSize?, resizable: Bool,
                            content: some View) -> NSWindow {
        var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
        if resizable { style.insert(.resizable) }
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: style,
                              backing: .buffered, defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: content)
        if resizable { window.setContentSize(size) }
        if let minSize { window.contentMinSize = minSize }
        window.center()
        return window
    }
}
