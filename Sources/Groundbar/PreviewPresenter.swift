import AppKit
import Combine
import SwiftUI

/// The window list above a task button: shown after a short hover, kept while the pointer is over it,
/// or opened by a click as a sticky picker that stays until the next click anywhere.
@MainActor
final class PreviewPresenter {
    let model = PreviewModel()
    /// The list on screen (for the theme).
    private(set) var panel: BarPanel?

    private let screen: () -> NSScreen
    private let appearance: () -> NSAppearance?
    private let canShow: () -> Bool
    private var anchor: CGRect = .zero
    private var pointerInside = false
    private var sticky = false
    private var clickMonitor: Any?
    private var showTimer: Timer?
    private var hideTimer: Timer?
    private var bag: Set<AnyCancellable> = []

    /// `screen` is the display to show on; `canShow` is false while something else (a flyout) has priority
    /// over a hover.
    init(screen: @escaping () -> NSScreen, appearance: @escaping () -> NSAppearance?, canShow: @escaping () -> Bool) {
        self.screen = screen
        self.appearance = appearance
        self.canShow = canShow
        // The list grows as windows load: follow its size.
        model.$windows.sink { [weak self] _ in DispatchQueue.main.async { self?.position() } }.store(in: &bag)
    }

    /// The pointer entered a task button; `anchor` is the button in screen coordinates.
    func hoverBegan(_ item: TaskItem, anchor: CGRect) {
        if sticky { return }
        hideTimer?.invalidate()
        guard canShow(), let app = item.app, !app.isTerminated else { return }
        // Moving between buttons with a list open switches at once; otherwise wait a moment.
        if panel != nil {
            show(app: app, item: item, anchor: anchor)
            return
        }
        showTimer?.invalidate()
        showTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.show(app: app, item: item, anchor: anchor) }
        }
    }

    func hoverEnded() {
        showTimer?.invalidate()
        scheduleHide()
    }

    /// The pointer entered or left the list itself.
    func pointerInside(_ inside: Bool) {
        pointerInside = inside
        if inside { hideTimer?.invalidate() } else { scheduleHide() }
    }

    /// Opens the list for `app` as a picker that stays until the next click; a second click on the same
    /// button closes it.
    func togglePicker(app: NSRunningApplication, item: TaskItem, anchor: CGRect) {
        if sticky && model.app == app { hide(); return }
        showTimer?.invalidate()
        hideTimer?.invalidate()
        show(app: app, item: item, anchor: anchor)
        sticky = true
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
    }

    /// Shows the panel for whatever `model` holds (the snapshot demo loads it directly).
    func showPanel(anchor: CGRect) {
        self.anchor = anchor
        if panel == nil {
            let p = BarPanel(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
            p.configureAsGroundbar(appearance: appearance())
            p.hasShadow = true
            p.contentView = NSHostingView(rootView: PreviewView(model: model))
            panel = p
        }
        position()
        panel?.orderFrontRegardless()
    }

    func hide() {
        if let m = clickMonitor { NSEvent.removeMonitor(m) }
        clickMonitor = nil
        sticky = false
        showTimer?.invalidate()
        hideTimer?.invalidate()
        pointerInside = false
        panel?.orderOut(nil)
        panel = nil
        model.clear()
    }

    private func show(app: NSRunningApplication, item: TaskItem, anchor: CGRect) {
        model.load(app: app, name: item.name, icon: item.icon)
        showPanel(anchor: anchor)
    }

    private func scheduleHide() {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if !self.pointerInside && !self.sticky { self.hide() }
            }
        }
    }

    /// Centers the list over its button, kept inside the display.
    private func position() {
        guard let p = panel else { return }
        let size = model.panelSize
        let s = screen().frame
        let x = min(max(anchor.midX - size.width / 2, s.minX + 8), s.maxX - size.width - 8)
        p.setFrame(NSRect(x: x, y: s.minY + TaskbarController.barHeight + 8, width: size.width, height: size.height), display: true)
    }
}
