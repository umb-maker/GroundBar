import AppKit
import SwiftUI

/// The panels that open above the bar (Start, calendar, quick settings, Bitcoin): one at a time, closed
/// by a click outside, by Escape, or by toggling the same one again.
@MainActor
final class FlyoutPresenter {
    /// Where a flyout sits along the bar, in screen coordinates: centered on, ending at or starting at x.
    enum Anchor { case center(CGFloat), right(CGFloat), left(CGFloat) }

    /// The kind passed to `toggle` for the flyout on screen, or nil.
    private(set) var openKind: String?
    /// The flyout on screen (for the theme).
    private(set) var panel: FlyoutPanel?

    private let screen: () -> NSScreen
    private let appearance: () -> NSAppearance?
    private let willOpen: () -> Void
    private var outsideClickMonitor: Any?
    private var keyMonitor: Any?

    /// `screen` is the display to open on, read at each `toggle`; `willOpen` runs before a flyout opens
    /// (it hides the window list).
    init(screen: @escaping () -> NSScreen, appearance: @escaping () -> NSAppearance?, willOpen: @escaping () -> Void) {
        self.screen = screen
        self.appearance = appearance
        self.willOpen = willOpen
    }

    /// Opens `content` in a flyout, or closes it when a flyout of the same kind is open. The height is
    /// capped to the display.
    func toggle<V: View>(_ kind: String, anchor: Anchor, size: CGSize, @ViewBuilder content: () -> V) {
        if openKind == kind { close(); return }
        close()
        willOpen()

        let s = screen().frame
        var x: CGFloat
        switch anchor {
        case .center(let mid): x = mid - size.width / 2
        case .right(let edge): x = edge - size.width
        case .left(let edge): x = edge
        }
        x = min(max(x, s.minX + 12), s.maxX - size.width - 12)
        let bar = TaskbarController.barHeight
        let height = min(size.height, s.height - bar - 40)
        let target = NSRect(x: x, y: s.minY + bar + 12, width: size.width, height: height)

        let p = FlyoutPanel(contentRect: target, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        p.configureAsGroundbar(appearance: appearance())
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
        panel = p
        openKind = kind

        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { MainActor.assumeIsolated { self?.close() }; return nil }
            return event
        }
    }

    func close() {
        if let m = outsideClickMonitor { NSEvent.removeMonitor(m) }
        if let m = keyMonitor { NSEvent.removeMonitor(m) }
        outsideClickMonitor = nil
        keyMonitor = nil
        panel?.orderOut(nil)
        panel = nil
        openKind = nil
    }
}
