import AppKit
import Observation
import SkilloriUI
import SwiftUI

/// Owns the menu bar item and the floating panel under it.
///
/// The panel is our own borderless window rather than `MenuBarExtra(.window)`, because the
/// design needs a 28 pt corner radius, a tinted blur of the desktop and no system chrome.
@MainActor
final class StatusPanelController: NSObject, NSWindowDelegate {
    private let store: InventoryStore
    private let windows: WindowRouter
    private let statusItem: NSStatusItem
    private let panel: GlassPanelWindow
    private let host: NSHostingView<AnyView>
    private var outsideClickMonitor: Any?

    static let panelWidth: CGFloat = 332

    init(store: InventoryStore, windows: WindowRouter) {
        self.store = store
        self.windows = windows
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        panel = GlassPanelWindow(cornerRadius: Radius.panel)
        host = NSHostingView(rootView: AnyView(EmptyView()))
        super.init()

        host.rootView = AnyView(
            MenuPanel(actions: PanelActions(
                openLibrary: { [weak self] in self?.close(animated: false); self?.windows.showLibrary() },
                openSettings: { [weak self] in self?.close(animated: false); self?.windows.showSettings() },
                addFolder: { [weak self] in self?.close(animated: false); self?.store.addProject() },
                rescan: { [weak self] in Task { await self?.store.rescan() } },
                openPrivacySettings: { [weak self] in
                    self?.close(animated: false)
                    if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_FilesAndFolders") {
                        NSWorkspace.shared.open(url)
                    }
                }
            ))
            .environment(store)
            .frame(width: Self.panelWidth)
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
            statusItem.button?.image = SkilloriMark.menuBarImage(store.needsAttention ? .attention : .rest)
            statusItem.button?.setAccessibilityLabel(store.needsAttention ? "Skillori, local changes" : "Skillori")
            _ = store.inventory?.scannedAt
            _ = store.isScanning
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
        } else {
            isOpen ? close() : open()
        }
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
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Skillori", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    @objc private func menuLibrary() { windows.showLibrary() }
    @objc private func menuSettings() { windows.showSettings() }

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
                Task { @MainActor in self?.close() }
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
                Task { @MainActor in self?.panel.invalidateShadow() }
            }
        } else {
            panel.setFrame(frame, display: true)
            panel.invalidateShadow()
        }
    }

    func windowDidResignKey(_ notification: Notification) { close() }

    /// Escape: a keyboard action, so no animation.
    func panelDidCancel() { close(animated: false) }
}

/// A borderless, rounded window that blurs what is behind it.
final class GlassPanelWindow: NSPanel {
    private let effect = NSVisualEffectView()

    init(cornerRadius: CGFloat) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 332, height: 300),
                   styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                   backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
        isMovable = false
        hidesOnDeactivate = false
        animationBehavior = .none

        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.maskImage = Self.mask(cornerRadius: cornerRadius)
        contentView = effect
    }

    func setContent(_ view: NSView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            view.topAnchor.constraint(equalTo: effect.topAnchor),
            view.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
    }

    override var canBecomeKey: Bool { true }

    var onCancel: (() -> Void)?

    override func cancelOperation(_ sender: Any?) { onCancel?() }

    private static func mask(cornerRadius r: CGFloat) -> NSImage {
        let edge = r * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: r, left: r, bottom: r, right: r)
        image.resizingMode = .stretch
        return image
    }
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
