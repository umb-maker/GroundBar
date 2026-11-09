import AppKit
import Combine
import SwiftUI

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
    let updater = Updater()

    private init() {
        model.onDocuments = { app, documents in
            TaskbarController.shared.files.observe(app: app, documents: documents)
        }
    }
    let preview = PreviewModel()
    private(set) lazy var toast = ToastPresenter(screen: { [unowned self] in screen }, appearance: { [unowned self] in model.theme.appearance })

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
        layoutBars()

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { TaskbarController.shared.layoutBars() }
        }
        model.$theme.sink { [weak self] theme in self?.applyTheme(theme) }.store(in: &bag)
        model.$barOnAllScreens.dropFirst().sink { [weak self] _ in DispatchQueue.main.async { self?.layoutBars() } }.store(in: &bag)
        preview.$windows.sink { [weak self] _ in DispatchQueue.main.async { self?.positionPreview() } }.store(in: &bag)

        let hk = HotKeyCenter.shared
        for (i, code) in HotKeyCenter.digitKeyCodes.enumerated() {
            hk.register(keyCode: code) { [weak self] in self?.closeFlyout(); self?.model.activate(index: i) }
        }
        hk.register(keyCode: HotKeyCenter.space) { [weak self] in self?.toggleStart() }
        hk.register(keyCode: HotKeyCenter.d) { [weak self] in self?.closeFlyout(); self?.model.toggleDesktop() }

        fullScreen.start(displays: { [unowned self] in Array(bars.keys) })
    }

    // MARK: Displays

    /// One bar per display (or only the main one, per Settings), keyed by display id.
    private var bars: [CGDirectDisplayID: BarPanel] = [:]

    static func displayID(of screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? CGMainDisplayID()
    }

    /// Creates, moves or removes bars to match the connected displays; called at launch, when displays
    /// change and when the "all displays" setting changes.
    func layoutBars() {
        let wanted = model.barOnAllScreens ? NSScreen.screens : Array(NSScreen.screens.prefix(1))
        let ids = Set(wanted.map(Self.displayID))
        for (id, panel) in bars where !ids.contains(id) {
            panel.orderOut(nil)
            bars[id] = nil
            hiddenForFullScreen.remove(id)
        }
        for screen in wanted {
            let id = Self.displayID(of: screen)
            let panel = bars[id] ?? makeBar(display: id)
            bars[id] = panel
            let f = screen.frame
            panel.setFrame(NSRect(x: f.minX, y: f.minY, width: f.width, height: Self.barHeight), display: true)
            if !hiddenForFullScreen.contains(id) { panel.orderFrontRegardless() }
        }
    }

    private func makeBar(display: CGDirectDisplayID) -> BarPanel {
        let panel = BarPanel(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        configure(panel)
        panel.hasShadow = false
        panel.contentView = NSHostingView(rootView: TaskbarView(model: model, status: status, display: display))
        return panel
    }

    /// The display the user is working on: the bar under the mouse, where clicks and hovers happen
    /// (hotkeys follow the mouse too). Flyouts, previews and notices open there.
    private var screen: NSScreen {
        let mouse = NSEvent.mouseLocation
        let withBar = NSScreen.screens.filter { bars[Self.displayID(of: $0)] != nil }
        return withBar.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.screens.first ?? NSScreen.main!
    }

    // MARK: Full screen

    /// Displays whose bar is hidden because the frontmost app fills them.
    private var hiddenForFullScreen = Set<CGDirectDisplayID>()
    private lazy var fullScreen = FullScreenWatcher { [unowned self] covered in apply(covered: covered) }

    private func apply(covered: Set<CGDirectDisplayID>) {
        for (id, panel) in bars {
            let hide = covered.contains(id)
            guard hide != hiddenForFullScreen.contains(id) else { continue }
            if hide {
                hiddenForFullScreen.insert(id)
                closeFlyout()
                hidePreview()
                panel.orderOut(nil)
            } else {
                hiddenForFullScreen.remove(id)
                panel.orderFrontRegardless()
            }
        }
    }

    private func configure(_ p: NSPanel) {
        p.configureAsGroundbar(appearance: model.theme.appearance)
    }

    private func applyTheme(_ theme: ThemeMode) {
        (Array(bars.values) + [flyout, previewPanel].compactMap { $0 }).forEach { $0.appearance = theme.appearance }
    }

    /// Converts a rect in a bar's SwiftUI global space (top-left origin) to screen coordinates,
    /// for the bar under the mouse.
    func screenRect(fromBar r: CGRect) -> CGRect {
        let f = screen.frame
        return CGRect(x: f.minX + r.minX, y: f.minY + Self.barHeight - r.maxY, width: r.width, height: r.height)
    }

    // MARK: Task buttons

    /// With several windows the click opens the window picker (like Windows) instead of activating the app.
    func click(_ item: TaskItem, rect: CGRect) {
        closeFlyout()
        if let app = item.app, !app.isTerminated, model.windowCount(app) > 1 {
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
        // With Reduce Motion the flyout fades in place instead of sliding up.
        p.setFrame(Decor.reduceMotion ? target : target.offsetBy(dx: 0, dy: -24), display: false)
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
