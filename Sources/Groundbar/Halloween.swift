import AppKit
import SwiftUI

/// Halloween theme decorations: an orange glow on the top edge, a few drifting bats and a glowing pumpkin.
/// Built from Core Animation layers so the motion runs in the window server: a SwiftUI animation would
/// redraw the whole bar on every frame (~8% CPU). Purely visual: it never receives clicks.
struct HalloweenDecor: NSViewRepresentable {
    func makeNSView(context: Context) -> DecorView { DecorView() }
    func updateNSView(_ view: DecorView, context: Context) {}

    final class DecorView: NSView {
        private static let pumpkin = NSColor(red: 1.0, green: 0.52, blue: 0.05, alpha: 1)

        /// Horizontal position (fraction of the bar width), size and phase of each bat, placed in the
        /// empty stretches between the widget, the centred icons and the tray.
        private static let bats: [(x: CGFloat, size: CGFloat, phase: Double)] = [(0.235, 15, 0), (0.275, 11, 0.8), (0.705, 13, 0.4)]

        private var built: CGSize = .zero

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func layout() {
            super.layout()
            guard bounds.size != built, bounds.width > 0, let root = layer else { return }
            built = bounds.size
            root.sublayers?.forEach { $0.removeFromSuperlayer() }
            // A frozen layer tree keeps every decoration in place (the sleigh stays parked off-screen).
            root.speed = Decor.reduceMotion ? 0 : 1
            let w = bounds.width, h = bounds.height
            let scale = window?.backingScaleFactor ?? 2

            // Glowing top edge (AppKit layers are bottom-left origin, so the top is y = h).
            let glow = CAGradientLayer()
            glow.frame = CGRect(x: 0, y: h - 1.5, width: w, height: 1.5)
            glow.startPoint = CGPoint(x: 0, y: 0.5)
            glow.endPoint = CGPoint(x: 1, y: 0.5)
            let p = Self.pumpkin
            glow.colors = [p.withAlphaComponent(0), p.withAlphaComponent(0.9), NSColor.purple.withAlphaComponent(0.8),
                           p.withAlphaComponent(0.9), p.withAlphaComponent(0)].map(\.cgColor)
            glow.shadowColor = p.cgColor
            glow.shadowOpacity = 0.9
            glow.shadowRadius = 4
            glow.shadowOffset = .zero
            root.addSublayer(glow)

            for bat in Self.bats {
                let l = Decor.emoji("🦇", size: bat.size, scale: scale)
                l.position = CGPoint(x: w * bat.x, y: h / 2)
                l.opacity = 0.9
                root.addSublayer(l)
                l.add(Decor.bob(dy: 6, duration: 2.2, phase: bat.phase), forKey: "bob")
                l.add(Decor.sway(dx: 6, duration: 5.5, phase: bat.phase), forKey: "sway")
                l.add(Decor.tilt(duration: 1.6, phase: bat.phase), forKey: "tilt")
            }

            let pumpkin = Decor.emoji("🎃", size: 18, scale: scale)
            pumpkin.position = CGPoint(x: w * 0.79, y: h / 2)
            pumpkin.shadowColor = p.cgColor
            pumpkin.shadowOpacity = 0.9
            pumpkin.shadowRadius = 4
            pumpkin.shadowOffset = .zero
            root.addSublayer(pumpkin)
            let pulse = CABasicAnimation(keyPath: "shadowRadius")
            pulse.fromValue = 2
            pulse.toValue = 7
            pulse.duration = 1.4
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            pumpkin.add(pulse, forKey: "pulse")

            let web = Decor.emoji("🕸️", size: 16, scale: scale)
            web.position = CGPoint(x: w - 18, y: h - 10)
            web.opacity = 0.45
            root.addSublayer(web)
        }
    }
}
