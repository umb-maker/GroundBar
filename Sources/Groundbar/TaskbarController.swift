import AppKit
import Combine
import SwiftUI

/// The composition root: owns the stores, one bar per display, the hotkeys and the task-button clicks,
/// and hands flyouts, window lists, notices and full-screen detection to their presenters.
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

    // The panels above the bar, each in its own file. They open on the display under the mouse.
    private(set) lazy var flyouts: FlyoutPresenter = FlyoutPresenter(
        screen: { [unowned self] in screen }, appearance: { [unowned self] in model.theme.appearance },
        willOpen: { [unowned self] in previews.hide(); autoHide.reveal(Self.displayID(of: screen)) })
    private(set) lazy var previews: PreviewPresenter = PreviewPresenter(
        screen: { [unowned self] in screen }, appearance: { [unowned self] in model.theme.appearance },
        canShow: { [unowned self] in flyouts.openKind == nil })
    private(set) lazy var toast: ToastPresenter = ToastPresenter(
        screen: { [unowned self] in screen }, appearance: { [unowned self] in model.theme.appearance })
    private(set) lazy var tooltip: TooltipPresenter = TooltipPresenter(
        screen: { [unowned self] in screen }, appearance: { [unowned self] in model.theme.appearance })

    private init() {
        model.onDocuments = { app, documents in
            TaskbarController.shared.files.observe(app: app, documents: documents)
        }
    }

    private var bag: Set<AnyCancellable> = []

    // MARK: Setup

    func start() {
        catalog.reload()
        layoutBars()

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { TaskbarController.shared.layoutBars() }
        }
        model.$theme.sink { [weak self] theme in self?.applyTheme(theme) }.store(in: &bag)
        model.$autoHide.dropFirst().sink { [weak self] mode in self?.autoHide.mode = mode }.store(in: &bag)
        model.$barOnAllScreens.dropFirst().sink { [weak self] _ in DispatchQueue.main.async { self?.layoutBars() } }.store(in: &bag)

        let hk = HotKeyCenter.shared
        for (i, code) in HotKeyCenter.digitKeyCodes.enumerated() {
            hk.register(keyCode: code) { [weak self] in self?.flyouts.close(); self?.model.activate(index: i) }
        }
        hk.register(keyCode: HotKeyCenter.space) { [weak self] in self?.toggleStart() }
        hk.register(keyCode: HotKeyCenter.d) { [weak self] in self?.flyouts.close(); self?.model.toggleDesktop() }

        fullScreen.start(displays: { [unowned self] in Array(bars.keys) })
        model.onWindowEvent = { [unowned self] in fullScreen.check() }
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
            shownBars.remove(id)
        }
        barFrames = [:]
        for screen in wanted {
            let id = Self.displayID(of: screen)
            let panel = bars[id] ?? makeBar(display: id)
            bars[id] = panel
            let f = screen.frame
            let frame = NSRect(x: f.minX, y: f.minY, width: f.width, height: Self.barHeight)
            barFrames[id] = frame
            panel.setFrame(frame, display: true)
        }
        autoHide.layout(barFrames: barFrames)
        refreshVisibility()
    }

    // MARK: Showing and hiding

    /// Each bar's place on its display, in screen coordinates.
    private var barFrames: [CGDirectDisplayID: NSRect] = [:]
    /// Displays whose bar is on screen now.
    private var shownBars = Set<CGDirectDisplayID>()
    private lazy var autoHide: BarAutoHider = BarAutoHider(
        mode: model.autoHide,
        isBusy: { [unowned self] in flyouts.openKind != nil || previews.panel != nil },
        onChange: { [unowned self] in refreshVisibility() })

    /// Shows or hides each bar: out of sight while the front app fills its display, or while auto-hide
    /// has tucked it away.
    private func refreshVisibility() {
        for (id, panel) in bars {
            let show = !hiddenForFullScreen.contains(id) && !autoHide.isConcealed(id)
            guard show != shownBars.contains(id), let frame = barFrames[id] else { continue }
            // A short slide with the fade; with Reduce Motion only the fade.
            let away = Decor.reduceMotion ? frame : frame.offsetBy(dx: 0, dy: -16)
            if show {
                shownBars.insert(id)
                panel.setFrame(away, display: false)
                panel.alphaValue = 0
                panel.orderFrontRegardless()
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.15
                    panel.animator().setFrame(frame, display: true)
                    panel.animator().alphaValue = 1
                }
            } else {
                shownBars.remove(id)
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.15
                    panel.animator().setFrame(away, display: true)
                    panel.animator().alphaValue = 0
                }, completionHandler: { [weak self] in
                    MainActor.assumeIsolated {
                        guard let self, !self.shownBars.contains(id) else { return }
                        panel.orderOut(nil)
                    }
                })
            }
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
    private lazy var fullScreen = FullScreenWatcher(barHeight: Self.barHeight) { [unowned self] covered, underBar in
        apply(covered: covered)
        autoHide.setOverlapping(underBar)
    }

    private func apply(covered: Set<CGDirectDisplayID>) {
        for id in bars.keys {
            let hide = covered.contains(id)
            guard hide != hiddenForFullScreen.contains(id) else { continue }
            if hide {
                hiddenForFullScreen.insert(id)
                flyouts.close()
                previews.hide()
            } else {
                hiddenForFullScreen.remove(id)
            }
        }
        refreshVisibility()
    }

    private func configure(_ p: NSPanel) {
        p.configureAsGroundbar(appearance: model.theme.appearance)
    }

    private func applyTheme(_ theme: ThemeMode) {
        (Array(bars.values) + [flyouts.panel, previews.panel].compactMap { $0 }).forEach { $0.appearance = theme.appearance }
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
        flyouts.close()
        if let app = item.app, !app.isTerminated, model.windowCount(app) > 1 {
            previews.togglePicker(app: app, item: item, anchor: screenRect(fromBar: rect))
            return
        }
        previews.hide()
        model.click(item)
    }

    // MARK: Start

    func toggleStart() {
        let s = screen.frame
        let anchor: FlyoutPresenter.Anchor = model.centered ? .center(s.midX) : .left(s.minX + 12)
        catalog.reload()
        files.refreshRecent()
        flyouts.toggle("start", anchor: anchor, size: CGSize(width: 640, height: 720)) {
            StartMenuView(model: model, catalog: catalog, files: files)
        }
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
