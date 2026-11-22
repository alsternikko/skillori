import AppKit
import Observation
import SkilloriUI
import SwiftUI

/// Owns the menu bar item and the floating panel under it.
///
/// The panel is our own borderless window rather than `MenuBarExtra(.window)`, because the
/// design needs its own corner radius and frame and no system chrome.
@MainActor
final class StatusPanelController: NSObject, NSWindowDelegate {
    private let store: InventoryStore
    private let windows: WindowRouter
    private let statusItem: NSStatusItem
    private let panel: PanelWindow
    private let host: NSHostingView<AnyView>
    private var outsideClickMonitor: Any?

    static let panelWidth: CGFloat = 332

    init(store: InventoryStore, windows: WindowRouter) {
        self.store = store
        self.windows = windows
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        panel = PanelWindow()
        host = NSHostingView(rootView: AnyView(EmptyView()))
        super.init()

        host.rootView = AnyView(
            MenuPanel(actions: PanelActions(
                openLibrary: { [weak self] in self?.close(animated: false); self?.windows.showLibrary() },
                openPage: { [weak self] page in self?.close(animated: false); self?.windows.showLibrary(at: page) },
                openSettings: { [weak self] in self?.close(animated: false); self?.windows.showSettings() },
                addFolder: { [weak self] in self?.close(animated: false); self?.store.addProject() },
                rescan: { [weak self] in Task { await self?.store.refresh() } },
                openPrivacySettings: { [weak self] in
                    self?.close(animated: false)
                    if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_FilesAndFolders") {
                        NSWorkspace.shared.open(url)
                    }
                },
                contentHeightChanged: { [weak self] height in self?.contentHeightChanged(height) }
            ))
            .environment(store)
            .frame(width: Self.panelWidth)
        )
        // The window's height is ours alone. Left to the hosting view as well, Auto Layout
        // pushed the window to the content's new height at once, mid-animation, and the content
        // jumped up and slid back down for every line an update printed.
        host.sizingOptions = []
        panel.setContent(host)
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.panelDidCancel() }
        host.wantsLayer = true

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        observeStore()
        // The menu bar item can still be on its way into place when the panel opens, and it
        // moves when the menu bar does. The panel stays hung under it.
        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: nil, queue: .main) { [weak self] note in
            let moved = (note.object as AnyObject?).map(ObjectIdentifier.init)
            MainActor.assumeIsolated {
                guard let self, self.isOpen, let window = self.statusItem.button?.window,
                      moved == ObjectIdentifier(window) else { return }
                self.layoutPanel(animated: false)
            }
        }
    }

    // MARK: Menu bar item

    private func observeStore() {
        withObservationTracking {
            // A plate in the flat accent for what needs the reader or for something new at a source, plain otherwise.
            let updates = store.checksEnabled ? store.updateCount + store.pluginUpdates.count + store.codexMoved.count : 0
            let state: SkilloriMark.MenuBarState = store.needsAttention ? .attention : updates > 0 ? .new
                : store.isStale ? .stale : .rest
            statusItem.button?.image = SkilloriMark.menuBarImage(state)
            statusItem.button?.setAccessibilityLabel(
                store.needsAttention ? "Skillori, local changes"
                    : updates > 0 ? "Skillori, \(updates) update\(updates == 1 ? "" : "s")"
                    : store.isStale ? "Skillori, sources not reached" : "Skillori")
        } onChange: { [weak self] in
            // The panel's height follows its content on its own; see `contentHeightChanged`.
            Task { @MainActor in self?.observeStore() }
        }
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else if isOpen {
            close()
        } else if let lostFocusAt, ProcessInfo.processInfo.systemUptime - lostFocusAt < 0.5 {
            // The press that led to this click already closed the panel. Leave it closed.
        } else {
            open()
        }
        lostFocusAt = nil
    }

    private func showContextMenu() {
        close(animated: false)
        statusItem.menu = makeContextMenu()
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "Open Library…", action: #selector(menuLibrary), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Settings…", action: #selector(menuSettings), keyEquivalent: ",").target = self
        // The answer shows where the reader will look for it: the updates card in settings.
        if AppUpdater.shared.phase != .unavailable {
            menu.addItem(withTitle: "Check for Updates…", action: #selector(menuCheckForUpdates), keyEquivalent: "").target = self
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Skillori", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    @objc private func menuLibrary() { windows.showLibrary() }
    @objc private func menuSettings() { windows.showSettings() }
    @objc private func menuCheckForUpdates() {
        windows.showSettings()
        AppUpdater.shared.checkNow()
    }

    // MARK: Panel

    private(set) var isOpen = false
    private var closeGeneration = 0
    var panelWindow: NSWindow { panel }
    var statusButton: NSStatusBarButton? { statusItem.button }

    /// Opens with a short fade and a slight growth out of the menu bar item.
    func open() {
        closeGeneration += 1
        isOpen = true
        // The content's height is reported during layout; this makes it current before placing.
        host.layoutSubtreeIfNeeded()
        layoutPanel(animated: false)
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if !panel.isVisible { panel.alphaValue = 0 }
        panel.makeKeyAndOrderFront(nil)
        statusItem.button?.highlight(true)

        if !reduceMotion, let layer = host.layer {
            let grow = CABasicAnimation(keyPath: "transform")
            grow.fromValue = CATransform3DMakeScale(Motion.openScale, Motion.openScale, 1).around(originPoint(in: layer), in: layer)
            grow.toValue = CATransform3DIdentity
            grow.duration = Motion.open
            grow.timingFunction = Motion.easeOut
            layer.add(grow, forKey: "open")
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Motion.open
            context.timingFunction = Motion.easeOut
            panel.animator().alphaValue = 1
        }
        if outsideClickMonitor == nil {
            outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                Task { @MainActor in self?.pressedOutside() }
            }
        }
    }

    /// Closes the panel. Pointer-driven closes fade out quickly; keyboard and command
    /// closes pass `animated: false` and are immediate.
    func close(animated: Bool = true) {
        guard isOpen else { return }
        isOpen = false
        statusItem.button?.highlight(false)
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
        host.layer?.removeAnimation(forKey: "open")
        stopResizing()

        guard animated else {
            panel.orderOut(nil)
            return
        }
        closeGeneration += 1
        let generation = closeGeneration
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Motion.close
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self, self.closeGeneration == generation, !self.isOpen else { return }
                self.panel.orderOut(nil)
            }
        }
    }

    /// The point under the menu bar item, in the content layer's coordinates. The panel grows from here.
    private func originPoint(in layer: CALayer) -> CGPoint {
        var x = layer.bounds.midX
        if let button = statusItem.button, let window = button.window {
            let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
            x = min(max(anchor.midX - panel.frame.minX, 0), layer.bounds.width)
        }
        let top = host.isFlipped ? layer.bounds.minY : layer.bounds.maxY
        return CGPoint(x: x, y: top)
    }

    /// The height the panel's content asks for, as it last reported it.
    private(set) var contentHeight: CGFloat = 0
    private var layoutScheduled = false

    /// The content reports its height from inside a layout pass. The window follows once that
    /// pass is over, and changes that land together make one move.
    private func contentHeightChanged(_ height: CGFloat) {
        guard height != contentHeight else { return }
        contentHeight = height
        guard !layoutScheduled else { return }
        layoutScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.layoutScheduled = false
            self.layoutPanel(animated: true)
        }
    }

    /// Sizes the panel to its content and hangs it under the menu bar item, kept on screen.
    /// When the panel is open and its content changes height, the change is eased.
    private func layoutPanel(animated: Bool) {
        guard contentHeight > 0 else { return }
        let width = Self.panelWidth
        // Whole points, so the top edge stays exactly where it is while the height moves.
        var height = contentHeight.rounded(.up)
        guard let button = statusItem.button, let buttonWindow = button.window else {
            stopResizing()
            panel.setContentSize(NSSize(width: width, height: height))
            return
        }
        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        var x = anchor.midX - width / 2
        if let screen = buttonWindow.screen ?? NSScreen.main {
            x = min(max(x, screen.visibleFrame.minX + 8), screen.visibleFrame.maxX - width - 8)
            // Never taller than the room under the menu bar, however many lists are open.
            height = min(height, max(anchor.minY - 6 - screen.visibleFrame.minY - 8, 200).rounded(.down))
        }
        let top = (anchor.minY - 6).rounded(.down)
        let frame = NSRect(x: x.rounded(), y: top - height, width: width, height: height)
        if animated, isOpen, panel.isVisible, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            guard frame != (resize?.to ?? panel.frame) else { return }
            startResizing(to: frame)
        } else {
            stopResizing()
            guard frame != panel.frame else { return }
            panel.setFrame(frame, display: true)
            panel.invalidateShadow()
        }
    }

    // MARK: Resizing

    /// A height change on its way. The window's animator moves the origin and the size
    /// separately and rounds each, so the top edge wavered by a point, frame after frame. This
    /// moves the height only, a whole point at a time, and sets the origin from the fixed top.
    private struct Resize {
        let from: NSRect
        let to: NSRect
        let start: CFTimeInterval
    }

    private var resize: Resize?
    private var resizeLink: CADisplayLink?

    private func startResizing(to frame: NSRect) {
        // A new height while one is on its way: carry on from where the window is now.
        resize = Resize(from: panel.frame, to: frame, start: CACurrentMediaTime())
        if resizeLink == nil {
            let link = host.displayLink(target: self, selector: #selector(resizeStep))
            link.add(to: .main, forMode: .common)
            resizeLink = link
        }
    }

    private func stopResizing() {
        resizeLink?.invalidate()
        resizeLink = nil
        resize = nil
    }

    @objc private func resizeStep() {
        guard let resize else { stopResizing(); return }
        let progress = min((CACurrentMediaTime() - resize.start) / Motion.resize, 1)
        let eased = Motion.easeOutCurve.value(at: progress)
        let height = (resize.from.height + (resize.to.height - resize.from.height) * eased).rounded()
        let frame = NSRect(x: resize.to.minX, y: resize.to.maxY - height, width: resize.to.width, height: height)
        if frame != panel.frame {
            panel.setFrame(frame, display: true)
            // The shadow follows the window's shape, which just changed.
            panel.invalidateShadow()
        }
        if progress >= 1 { stopResizing() }
    }

    /// True while the pointer is over our menu bar item.
    private var pointerIsOnStatusItem: Bool {
        guard let button = statusItem.button, let window = button.window else { return false }
        let frame = window.convertToScreen(button.convert(button.bounds, to: nil))
        return frame.insetBy(dx: -2, dy: -2).contains(NSEvent.mouseLocation)
    }

    /// A press somewhere outside the panel. The system can deliver a press on our own menu
    /// bar item this way too, before the click itself arrives. That press must leave the
    /// panel alone, or the click would find it closed and open it again.
    private func pressedOutside() {
        guard isOpen, !pointerIsOnStatusItem else { return }
        lostFocusAt = ProcessInfo.processInfo.systemUptime
        close()
    }

    /// When the panel last closed because it lost focus.
    private var lostFocusAt: TimeInterval?

    /// Pressing the menu bar item takes focus from the panel before the click arrives.
    /// That press must not close the panel here, or the click that follows would open it
    /// again; the click itself toggles.
    func windowDidResignKey(_ notification: Notification) {
        guard isOpen else { return }
        if pointerIsOnStatusItem, NSEvent.pressedMouseButtons & 1 == 1 { return }
        if let event = NSApp.currentEvent, event.type == .leftMouseDown,
           let buttonWindow = statusItem.button?.window, event.window === buttonWindow {
            return
        }
        lostFocusAt = ProcessInfo.processInfo.systemUptime
        close()
    }

    /// Escape: a keyboard action, so no animation.
    func panelDidCancel() { close(animated: false) }
}

/// A borderless window with no chrome of its own. The view inside draws the rounded, solid
/// surface; the window is clear around it so the corners and the shadow follow that shape.
final class PanelWindow: NSPanel {
    private let container = NSView()

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 332, height: 300),
                   styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                   backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        // The system's own window shadow. It comes with a thin dark rim along the window's
        // shape, so the surface inside draws no frame of its own in light mode: two edges
        // side by side read as one thick border.
        hasShadow = true
        level = .popUpMenu
        collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
        isMovable = false
        hidesOnDeactivate = false
        animationBehavior = .none
        container.wantsLayer = true
        contentView = container
    }

    /// The view fills the window and follows it. Its size comes only from the window's frame,
    /// never the other way around.
    func setContent(_ view: NSView) {
        view.translatesAutoresizingMaskIntoConstraints = true
        view.frame = container.bounds
        view.autoresizingMask = [.width, .height]
        container.addSubview(view)
    }

    override var canBecomeKey: Bool { true }

    var onCancel: (() -> Void)?

    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

/// Timing for the panel. It opens often, so everything is short and nothing bounces.
@MainActor
private enum Motion {
    static let open: TimeInterval = 0.16
    static let close: TimeInterval = 0.09
    static let resize: TimeInterval = 0.25
    static let openScale: CGFloat = 0.96
    /// A strong ease-out: fast at first, then settling.
    static let easeOut = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
    /// The same curve, for animations we step ourselves.
    static let easeOutCurve = UnitBezier(0.23, 1, 0.32, 1)
}

/// A cubic Bézier timing curve from (0, 0) to (1, 1), as CSS and Core Animation define them,
/// evaluated by solving for x and reading y.
struct UnitBezier {
    private let ax, bx, cx, ay, by, cy: Double

    init(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) {
        cx = 3 * x1; bx = 3 * (x2 - x1) - cx; ax = 1 - cx - bx
        cy = 3 * y1; by = 3 * (y2 - y1) - cy; ay = 1 - cy - by
    }

    func value(at x: Double) -> Double {
        guard x > 0 else { return 0 }
        guard x < 1 else { return 1 }
        return sampleY(solveT(x))
    }

    private func sampleX(_ t: Double) -> Double { ((ax * t + bx) * t + cx) * t }
    private func sampleY(_ t: Double) -> Double { ((ay * t + by) * t + cy) * t }
    private func slopeX(_ t: Double) -> Double { (3 * ax * t + 2 * bx) * t + cx }

    private func solveT(_ x: Double) -> Double {
        // Newton's method first; it settles in a few steps almost everywhere.
        var t = x
        for _ in 0..<8 {
            let error = sampleX(t) - x
            if abs(error) < 1e-6 { return t }
            let slope = slopeX(t)
            if abs(slope) < 1e-6 { break }
            t -= error / slope
        }
        // Bisection where the slope is too flat for it.
        var low = 0.0, high = 1.0
        t = x
        while high - low > 1e-6 {
            if sampleX(t) < x { low = t } else { high = t }
            t = (low + high) / 2
        }
        return t
    }
}

private extension CATransform3D {
    /// The same transform applied around `point` (in the layer's bounds) instead of the layer's anchor.
    func around(_ point: CGPoint, in layer: CALayer) -> CATransform3D {
        let anchor = CGPoint(x: layer.bounds.minX + layer.bounds.width * layer.anchorPoint.x,
                             y: layer.bounds.minY + layer.bounds.height * layer.anchorPoint.y)
        let dx = point.x - anchor.x, dy = point.y - anchor.y
        return CATransform3DTranslate(CATransform3DConcat(self, CATransform3DMakeTranslation(dx, dy, 0)), -dx, -dy, 0)
    }
}
