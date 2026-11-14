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
                openSettings: { [weak self] in self?.close(animated: false); self?.windows.showSettings() },
                addFolder: { [weak self] in self?.close(animated: false); self?.store.addProject() },
                rescan: { [weak self] in Task { await self?.store.refresh() } },
                openPrivacySettings: { [weak self] in
                    self?.close(animated: false)
                    if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_FilesAndFolders") {
                        NSWorkspace.shared.open(url)
                    }
                },
                contentResized: { [weak self] in self?.layoutPanel(animated: true) }
            ))
            .environment(store)
            .frame(width: Self.panelWidth)
            // While the window is still on its way to a new height, the content stays at its top.
            .frame(maxHeight: .infinity, alignment: .top)
        )
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
    }

    // MARK: Menu bar item

    private func observeStore() {
        withObservationTracking {
            // A plate in the flat accent for what needs the reader or for something new at a source, plain otherwise.
            let updates = store.checksEnabled ? store.updateCount : 0
            let state: SkilloriMark.MenuBarState = store.needsAttention ? .attention : updates > 0 ? .new : .rest
            statusItem.button?.image = SkilloriMark.menuBarImage(state)
            statusItem.button?.setAccessibilityLabel(
                store.needsAttention ? "Skillori, local changes"
                    : updates > 0 ? "Skillori, \(updates) update\(updates == 1 ? "" : "s")" : "Skillori")
            _ = store.isChecking
            // The panel grows when an update prints something.
            _ = store.updater.phase
            _ = store.updater.output
            _ = store.inventory?.scannedAt
            _ = store.isScanning
            // A line about a new Skillori comes and goes in the panel.
            _ = AppUpdater.shared.phase
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.observeStore()
                self?.layoutPanel(animated: true)
            }
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

    /// Sizes the panel to its content and hangs it under the menu bar item, kept on screen.
    /// When the panel is open and its content changes height, the change is eased.
    private func layoutPanel(animated: Bool) {
        let size = host.fittingSize
        guard let button = statusItem.button, let buttonWindow = button.window else {
            panel.setContentSize(size)
            return
        }
        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        var x = anchor.midX - size.width / 2
        if let screen = buttonWindow.screen ?? NSScreen.main {
            x = min(max(x, screen.visibleFrame.minX + 8), screen.visibleFrame.maxX - size.width - 8)
        }
        let frame = NSRect(x: x, y: anchor.minY - 6 - size.height, width: size.width, height: size.height)
        guard frame != panel.frame else { return }
        if animated, isOpen, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Motion.resize
                context.timingFunction = Motion.easeOut
                panel.animator().setFrame(frame, display: true)
            } completionHandler: { [weak self] in
                // The shadow follows the window's shape, which just changed.
                Task { @MainActor in self?.panel.invalidateShadow() }
            }
        } else {
            panel.setFrame(frame, display: true)
            panel.invalidateShadow()
        }
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

    func setContent(_ view: NSView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
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
