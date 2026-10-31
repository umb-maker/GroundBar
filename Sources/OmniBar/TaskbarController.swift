import AppKit
import Combine
import SwiftUI

/// The bar itself never takes keyboard focus, so the app you were using stays in front.
final class BarPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Flyouts (Start, calendar, quick settings) take key focus without activating OmniBar.
final class FlyoutPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Owns the windows: bar, flyouts and the hover preview.
@MainActor
final class TaskbarController {
    static let shared = TaskbarController()
    static let barHeight: CGFloat = 48

    let model = TaskbarModel()
    let status = SystemStatus()
    let catalog = AppCatalog()
    let files = FileIndex()
    let crypto = CryptoTicker()

    private init() {
        WindowService.onDocuments = { app, documents in
            TaskbarController.shared.files.observe(app: app, documents: documents)
        }
    }
    let preview = PreviewModel()

    private var bar: BarPanel!
    private var flyout: FlyoutPanel?
    private(set) var flyoutKind: String?
    private var outsideClickMonitor: Any?
    private var keyMonitor: Any?
    private var previewPanel: BarPanel?
    private var previewAnchor: CGRect = .zero
    private var previewHovered = false
    private var previewSticky = false
    private var previewClickMonitor: Any?
    private var showTimer: Timer?
    private var hideTimer: Timer?
    private var bag: Set<AnyCancellable> = []

    // MARK: Setup

    func start() {
        catalog.reload()
        bar = BarPanel(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        configure(bar)
        bar.hasShadow = false
        bar.contentView = NSHostingView(rootView: TaskbarView(model: model, status: status))
        layoutBar()
        bar.orderFrontRegardless()

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { TaskbarController.shared.layoutBar() }
        }
        model.$theme.sink { [weak self] theme in self?.applyTheme(theme) }.store(in: &bag)
        preview.$windows.sink { [weak self] _ in DispatchQueue.main.async { self?.positionPreview() } }.store(in: &bag)

        let hk = HotKeyCenter.shared
        for (i, code) in HotKeyCenter.digitKeyCodes.enumerated() {
            hk.register(keyCode: code) { [weak self] in self?.closeFlyout(); self?.model.activate(index: i) }
        }
        hk.register(keyCode: HotKeyCenter.space) { [weak self] in self?.toggleStart() }
        hk.register(keyCode: HotKeyCenter.d) { [weak self] in self?.closeFlyout(); self?.model.toggleDesktop() }
    }

    private func configure(_ p: NSPanel) {
        p.isFloatingPanel = true
        p.level = .statusBar
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hidesOnDeactivate = false
        p.isMovable = false
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        p.appearance = model.theme.appearance
    }

    private var screen: NSScreen { NSScreen.screens.first ?? NSScreen.main! }

    func layoutBar() {
        let f = screen.frame
        bar.setFrame(NSRect(x: f.minX, y: f.minY, width: f.width, height: Self.barHeight), display: true)
    }

    private func applyTheme(_ theme: ThemeMode) {
        [bar, flyout, previewPanel].compactMap { $0 }.forEach { $0.appearance = theme.appearance }
    }

    /// Converts a rect in the bar's SwiftUI global space (top-left origin) to screen coordinates.
    func screenRect(fromBar r: CGRect) -> CGRect {
        let f = bar.frame
        return CGRect(x: f.minX + r.minX, y: f.maxY - r.maxY, width: r.width, height: r.height)
    }

    // MARK: Task buttons

    /// With several windows the click opens the window picker (like Windows) instead of activating the app.
    func click(_ item: TaskItem, rect: CGRect) {
        closeFlyout()
        if let app = item.app, !app.isTerminated, WindowService.windowCount(of: app) > 1 {
            if previewSticky && preview.app == app { hidePreview(); return }
            showTimer?.invalidate()
            hideTimer?.invalidate()
            showPreview(app: app, item: item, anchor: screenRect(fromBar: rect))
            previewSticky = true
            previewClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
                MainActor.assumeIsolated { TaskbarController.shared.hidePreview() }
            }
            return
        }
        hidePreview()
        model.click(item)
    }

    // MARK: Flyouts

    enum Anchor { case center(CGFloat), right(CGFloat), left(CGFloat) }

    func toggleFlyout<V: View>(_ kind: String, anchor: Anchor, size: CGSize, @ViewBuilder content: () -> V) {
        if flyoutKind == kind { closeFlyout(); return }
        closeFlyout()
        hidePreview()

        let s = screen.frame
        var x: CGFloat
        switch anchor {
        case .center(let mid): x = mid - size.width / 2
        case .right(let edge): x = edge - size.width
        case .left(let edge): x = edge
        }
        x = min(max(x, s.minX + 12), s.maxX - size.width - 12)
        let height = min(size.height, s.height - Self.barHeight - 40)
        let target = NSRect(x: x, y: s.minY + Self.barHeight + 12, width: size.width, height: height)

        let p = FlyoutPanel(contentRect: target, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        configure(p)
        p.hasShadow = true
        p.contentView = NSHostingView(rootView: content())
        p.setFrame(target.offsetBy(dx: 0, dy: -24), display: false)
        p.alphaValue = 0
        p.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            p.animator().setFrame(target, display: true)
            p.animator().alphaValue = 1
        }
        flyout = p
        flyoutKind = kind

        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
            MainActor.assumeIsolated { TaskbarController.shared.closeFlyout() }
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { MainActor.assumeIsolated { TaskbarController.shared.closeFlyout() }; return nil }
            return event
        }
    }

    func closeFlyout() {
        if let m = outsideClickMonitor { NSEvent.removeMonitor(m) }
        if let m = keyMonitor { NSEvent.removeMonitor(m) }
        outsideClickMonitor = nil
        keyMonitor = nil
        flyout?.orderOut(nil)
        flyout = nil
        flyoutKind = nil
    }

    func toggleStart() {
        let s = screen.frame
        let anchor: Anchor = model.centered ? .center(s.midX) : .left(s.minX + 12)
        catalog.reload()
        files.refreshRecent()
        toggleFlyout("start", anchor: anchor, size: CGSize(width: 640, height: 720)) {
            StartMenuView(model: model, catalog: catalog, files: files)
        }
    }

    // MARK: Hover previews

    func hoverBegan(_ item: TaskItem, rect: CGRect) {
        if previewSticky { return }
        hideTimer?.invalidate()
        guard flyout == nil, let app = item.app, !app.isTerminated else { return }
        let anchor = screenRect(fromBar: rect)
        if previewPanel != nil {
            showPreview(app: app, item: item, anchor: anchor)
            return
        }
        showTimer?.invalidate()
        showTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { _ in
            MainActor.assumeIsolated { TaskbarController.shared.showPreview(app: app, item: item, anchor: anchor) }
        }
    }

    func hoverEnded() {
        showTimer?.invalidate()
        scheduleHide()
    }

    func previewHover(_ inside: Bool) {
        previewHovered = inside
        if inside { hideTimer?.invalidate() } else { scheduleHide() }
    }

    private func scheduleHide() {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { _ in
            MainActor.assumeIsolated {
                let c = TaskbarController.shared
                if !c.previewHovered && !c.previewSticky { c.hidePreview() }
            }
        }
    }

    private func showPreview(app: NSRunningApplication, item: TaskItem, anchor: CGRect) {
        preview.load(app: app, name: item.name, icon: item.icon)
        showPreviewPanel(anchor: anchor)
    }

    func showPreviewPanel(anchor: CGRect) {
        previewAnchor = anchor
        if previewPanel == nil {
            let p = BarPanel(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
            configure(p)
            p.hasShadow = true
            p.contentView = NSHostingView(rootView: PreviewView(model: preview))
            previewPanel = p
        }
        positionPreview()
        previewPanel?.orderFrontRegardless()
    }

    private func positionPreview() {
        guard let p = previewPanel else { return }
        let size = preview.panelSize
        let s = screen.frame
        let x = min(max(previewAnchor.midX - size.width / 2, s.minX + 8), s.maxX - size.width - 8)
        p.setFrame(NSRect(x: x, y: s.minY + Self.barHeight + 8, width: size.width, height: size.height), display: true)
    }

    func hidePreview() {
        if let m = previewClickMonitor { NSEvent.removeMonitor(m) }
        previewClickMonitor = nil
        previewSticky = false
        showTimer?.invalidate()
        hideTimer?.invalidate()
        previewHovered = false
        previewPanel?.orderOut(nil)
        previewPanel = nil
        preview.clear()
    }

    // MARK: Toast

    private var toastPanel: BarPanel?
    private var toastTimer: Timer?

    func showToast(title: String, detail: String, action: @escaping () -> Void) {
        hideToast()
        let size = CGSize(width: 340, height: 64)
        let s = screen.frame
        let p = BarPanel(contentRect: NSRect(x: s.maxX - size.width - 12, y: s.minY + Self.barHeight + 12, width: size.width, height: size.height),
                         styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        configure(p)
        p.hasShadow = true
        p.contentView = NSHostingView(rootView: ToastView(title: title, detail: detail, action: action))
        p.alphaValue = 0
        p.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.15; p.animator().alphaValue = 1 }
        toastPanel = p
        toastTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { _ in
            MainActor.assumeIsolated { TaskbarController.shared.hideToast() }
        }
    }

    func hideToast() {
        toastTimer?.invalidate()
        toastPanel?.orderOut(nil)
        toastPanel = nil
    }

    // MARK: Misc

    func autoHideDock() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "defaults write com.apple.dock autohide -bool true && killall Dock"]
        try? p.run()
    }

    static func openSettings(_ url: String) {
        if let u = URL(string: url) { NSWorkspace.shared.open(u) }
    }
}
