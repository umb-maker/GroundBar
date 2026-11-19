import AppKit
import SwiftUI

/// A short label above a bar button while the pointer rests on it. The system tooltip (`.help`) never
/// shows here: macOS only draws it for the active app, and the bar never activates Groundbar.
@MainActor
final class TooltipPresenter {
    private let screen: () -> NSScreen
    private let appearance: () -> NSAppearance?
    private var panel: BarPanel?
    private var timer: Timer?
    private var clickMonitor: Any?

    init(screen: @escaping () -> NSScreen, appearance: @escaping () -> NSAppearance?) {
        self.screen = screen
        self.appearance = appearance
    }

    /// Shows `text` centered over `anchor` (screen coordinates) after the usual tooltip delay.
    func show(_ text: String, anchor: CGRect) {
        hide()
        // A click on the button (opening Start, say) takes the label away.
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.hide() }
            return event
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.present(text, anchor: anchor) }
        }
    }

    func hide() {
        if let m = clickMonitor { NSEvent.removeMonitor(m) }
        clickMonitor = nil
        timer?.invalidate()
        timer = nil
        panel?.orderOut(nil)
        panel = nil
    }

    private func present(_ text: String, anchor: CGRect) {
        let view = NSHostingView(rootView: TooltipView(text: text))
        let size = view.fittingSize
        let s = screen().frame
        let x = min(max(anchor.midX - size.width / 2, s.minX + 4), s.maxX - size.width - 4)
        let p = BarPanel(contentRect: NSRect(x: x, y: s.minY + TaskbarController.barHeight + 6, width: size.width, height: size.height),
                         styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        p.configureAsGroundbar(appearance: appearance())
        p.hasShadow = true
        p.ignoresMouseEvents = true
        p.contentView = view
        p.orderFrontRegardless()
        panel = p
    }
}

extension View {
    /// The bar's own tooltip (see `TooltipPresenter`); an empty text shows none.
    func barTooltip(_ text: String) -> some View { modifier(BarTooltip(text: text)) }
}

private struct BarTooltip: ViewModifier {
    let text: String
    @Local private var frame: CGRect = .zero

    func body(content: Content) -> some View {
        content
            .background(GeometryReader { g in
                Color.clear.onAppear { frame = g.frame(in: .global) }.onChange(of: g.frame(in: .global)) { _, n in frame = n }
            })
            .onHover { inside in
                let c = TaskbarController.shared
                if inside && !text.isEmpty { c.tooltip.show(text, anchor: c.screenRect(fromBar: frame)) } else { c.tooltip.hide() }
            }
    }
}

private struct TooltipView: View {
    let text: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Fluent(scheme).text)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .flyoutChrome()
            .fixedSize()
    }
}
