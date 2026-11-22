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

    override init() {
        // macOS thickens text a little when it smooths it ("font smoothing"). The design is
        // drawn without that, so the app turns it off for itself, before any text is drawn.
        // It has to be a stored value of the app's own: the text system does not read registered defaults.
        // A reader who asks for more contrast gets the system's smoothing, which is easier to read.
        let wantsContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        let stored = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")?["AppleFontSmoothing"]
        if wantsContrast {
            if stored != nil { UserDefaults.standard.removeObject(forKey: "AppleFontSmoothing") }
        } else if stored == nil {
            UserDefaults.standard.set(0, forKey: "AppleFontSmoothing")
        }
        super.init()
    }

    /// An update that is still running would go on without anyone to see how it ends.
    func applicationWillTerminate(_ notification: Notification) {
        store.updater.stop()
        store.pluginUpdater.stop()
        store.codexRunner.stop()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        SkilloriFonts.register()
        AppearanceSetting.current.apply()
        AppUpdater.shared.start()
        let windows = WindowRouter(store: store)
        self.windows = windows
        Notifier.shared.openLibrary = { [weak windows] in windows?.showLibrary() }
        Notifier.shared.start()
        statusPanel = StatusPanelController(store: store, windows: windows)
        let firstStart = FirstStartController(store: store, windows: windows)
        self.firstStart = firstStart
        NotificationCenter.default.addObserver(forName: .showFirstStart, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.firstStart?.show() }
        }
        let env = ProcessInfo.processInfo.environment
        if env["SKILLORI_SNAPSHOT_DIR"] == nil, env["SKILLORI_SELFTEST"] == nil, env["SKILLORI_LIBRARY_PROBE"] == nil, env["SKILLORI_ADOPT_PROBE"] == nil, env["SKILLORI_PANEL_PROBE"] == nil, env["SKILLORI_LIBRARY_RUN_PROBE"] == nil, env["SKILLORI_LOST_PROBE"] == nil, env["SKILLORI_PAGE_PICTURE"] == nil { firstStart.showIfNeeded() }
        #if DEBUG
        DebugSnapshots.runIfRequested(store: store, statusPanel: statusPanel)
        DebugLibraryProbe.runIfRequested(store: store, windows: windows)
        DebugPagePicture.runIfRequested(store: store, windows: windows)
        DebugLibraryRunProbe.runIfRequested(store: store, windows: windows)
        DebugAdoptProbe.runIfRequested(store: store)
        DebugLostSourceProbe.runIfRequested(store: store, windows: windows)
        DebugPluginUpdate.runIfRequested(store: store)
        if let statusPanel { DebugSelfTest.runIfRequested(store: store, panel: statusPanel, windows: windows) }
        if let statusPanel { DebugPanelProbe.runIfRequested(store: store, panel: statusPanel) }
        #endif
    }
}

/// The library and settings windows. In a quiet test run (debug builds) they stay where they
/// are put, off screen; otherwise AppKit pulls a titled window back onto the nearest screen.
final class AppWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        #if DEBUG
        if DebugQuiet.isOn { return frameRect }
        #endif
        return super.constrainFrameRect(frameRect, to: screen)
    }
}

/// Opens the app's ordinary windows. They are created on first use and kept.
@MainActor
final class WindowRouter {
    private let store: InventoryStore
    private(set) var library: NSWindow?
    private(set) var settings: NSWindow?
    private var settingsHeight: CGFloat = 0
    /// Window delegates that hold a window at its smallest size; a window keeps its delegate weakly.
    private var minSizeKeepers: [MinSizeKeeper] = []

    init(store: InventoryStore) { self.store = store }

    /// Opens the library, at `page` when one is given.
    func showLibrary(at page: LibraryPage? = nil) {
        if library == nil {
            library = makeWindow(title: "Skillori Library", size: NSSize(width: 1120, height: 760),
                                 minSize: NSSize(width: 900, height: 520), resizable: true, ownChrome: true,
                                 content: LibraryView(path: page.map { [$0] } ?? []).environment(store))
        } else if let page {
            NotificationCenter.default.post(name: LibraryView.openPage, object: page)
        }
        present(library)
    }

    func showSettings() {
        if settings == nil {
            settings = makeWindow(title: "Settings", size: NSSize(width: 640, height: 720),
                                  minSize: nil, resizable: false, ownChrome: true,
                                  content: SettingsView(ownChrome: true, onHeight: { [weak self] height in
                                      // Reported from inside a layout pass; resize the window after it.
                                      DispatchQueue.main.async { self?.fitSettings(height: height) }
                                  }).environment(store))
            settings?.contentView?.layoutSubtreeIfNeeded()
            fitSettings(height: settingsHeight)
            settings?.center()
        }
        present(settings)
    }

    /// Keeps the settings window exactly as tall as its content, with the top edge in place.
    private func fitSettings(height: CGFloat) {
        settingsHeight = height
        guard let settings, height > 0, abs(settings.frame.height - height) > 0.5 else { return }
        var frame = settings.frame
        frame.origin.y += frame.height - height
        frame.size.height = height
        settings.setFrame(frame, display: true)
    }

    private func present(_ window: NSWindow?) {
        #if DEBUG
        // A test run: off screen, and without taking the keyboard from the app in front.
        if DebugQuiet.isOn, let window {
            if window.frame.minX > DebugQuiet.shift / 2 {
                window.setFrameOrigin(NSPoint(x: DebugQuiet.shift, y: 0))
            }
            window.orderFrontRegardless()
            window.makeKey()
            return
        }
        #endif
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    private func makeWindow(title: String, size: NSSize, minSize: NSSize?, resizable: Bool,
                            ownChrome: Bool = false, content: some View) -> NSWindow {
        var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
        if resizable { style.insert(.resizable) }
        if ownChrome { style.insert(.fullSizeContentView) }
        let window = AppWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: style,
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
        // We size our windows ourselves. Left to size the window, the hosting view adds the
        // title bar's height below content that already draws under the title bar.
        let host = NSHostingView(rootView: content)
        host.sizingOptions = []
        window.contentView = host
        window.setContentSize(size)
        if let minSize {
            // The library's top row of six counts and its columns need this much room. The
            // content minimum alone did not hold when dragging (seen in 0.1.0), so the window's
            // own minimum and a delegate that clamps every resize hold it as well.
            window.contentMinSize = minSize
            window.minSize = window.frameRect(forContentRect: NSRect(origin: .zero, size: minSize)).size
            let keeper = MinSizeKeeper(minFrameSize: window.minSize)
            window.delegate = keeper
            minSizeKeepers.append(keeper)
        }
        window.center()
        return window
    }
}

/// Keeps a window from being dragged smaller than its minimum.
@MainActor
private final class MinSizeKeeper: NSObject, NSWindowDelegate {
    let minFrameSize: NSSize

    init(minFrameSize: NSSize) { self.minFrameSize = minFrameSize }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        NSSize(width: max(frameSize.width, minFrameSize.width), height: max(frameSize.height, minFrameSize.height))
    }
}
