import AppKit
import SwiftUI

/// The notice above the right end of the bar (screenshot saved, update available): one at a time,
/// gone after six seconds or a click.
@MainActor
final class ToastPresenter {
    private let screen: () -> NSScreen
    private let appearance: () -> NSAppearance?
    private var panel: BarPanel?
    private var timer: Timer?

    /// `screen` is the display to show on (the one the user is working on), read at each `show`.
    init(screen: @escaping () -> NSScreen, appearance: @escaping () -> NSAppearance?) {
        self.screen = screen
        self.appearance = appearance
    }

    /// Replaces any notice on screen. A click on it runs `action`.
    func show(title: String, detail: String, symbol: String, action: @escaping () -> Void) {
        hide()
        let size = CGSize(width: 340, height: 64)
        let s = screen().frame
        let p = BarPanel(contentRect: NSRect(x: s.maxX - size.width - 12, y: s.minY + TaskbarController.barHeight + 12,
                                             width: size.width, height: size.height),
                         styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        p.configureAsGroundbar(appearance: appearance())
        p.hasShadow = true
        p.contentView = NSHostingView(rootView: ToastView(title: title, detail: detail, symbol: symbol, action: action))
        p.alphaValue = 0
        p.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.15; p.animator().alphaValue = 1 }
        panel = p
        timer = Timer.scheduledTimer(withTimeInterval: 6, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
    }

    func hide() {
        timer?.invalidate()
        panel?.orderOut(nil)
        panel = nil
    }
}

/// Small notification shown above the right end of the bar.
struct ToastView: View {
    let title: String
    let detail: String
    let symbol: String
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let f = Fluent(scheme)
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 20)).foregroundStyle(f.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(detail).font(.system(size: 11)).foregroundStyle(f.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(f.text)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .flyoutChrome()
        .contentShape(Rectangle())
        .onTapGesture {
            TaskbarController.shared.toast.hide()
            action()
        }
    }
}
