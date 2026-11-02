import AppKit
import SwiftUI

/// Christmas theme decorations: gently falling snow, twinkling lights along the top edge, a tree with a
/// pulsing star, a snowman and a present. Core Animation layers only (see Decor.swift); never receives clicks.
struct ChristmasDecor: NSViewRepresentable {
    func makeNSView(context: Context) -> DecorView { DecorView() }
    func updateNSView(_ view: DecorView, context: Context) {}

    final class DecorView: NSView {
        private static let gold = NSColor(red: 0.96, green: 0.78, blue: 0.32, alpha: 1)
        private static let lightColors: [NSColor] = [
            NSColor(red: 0.95, green: 0.22, blue: 0.24, alpha: 1), NSColor(red: 0.20, green: 0.80, blue: 0.40, alpha: 1),
            NSColor(red: 0.96, green: 0.78, blue: 0.32, alpha: 1), NSColor(red: 0.35, green: 0.62, blue: 1.00, alpha: 1),
        ]

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
            let w = bounds.width, h = bounds.height
            let scale = window?.backingScaleFactor ?? 2

            root.addSublayer(snow(width: w, height: h, scale: scale))

            // String of lights along the top edge (AppKit layers: the top is y = h).
            let wire = CALayer()
            wire.frame = CGRect(x: 0, y: h - 1, width: w, height: 1)
            wire.backgroundColor = Self.gold.withAlphaComponent(0.35).cgColor
            root.addSublayer(wire)
            let spacing: CGFloat = 36
            for i in 0..<Int(w / spacing) {
                let color = Self.lightColors[i % Self.lightColors.count]
                let bulb = CALayer()
                bulb.bounds = CGRect(x: 0, y: 0, width: 4, height: 4)
                bulb.cornerRadius = 2
                bulb.position = CGPoint(x: spacing / 2 + CGFloat(i) * spacing, y: h - 3)
                bulb.backgroundColor = color.cgColor
                Decor.glow(bulb, color, radius: 3)
                // Each bulb twinkles at its own pace, so the string never blinks in unison.
                let twinkle = Decor.repeating("opacity", from: 1, to: 0.25, duration: 0.9 + Double(i % 5) * 0.23,
                                              phase: Double((i * 7) % 11) / 11, additive: false)
                bulb.add(twinkle, forKey: "twinkle")
                root.addSublayer(bulb)
            }

            // Placed in the empty stretches between the widget, the centred icons and the tray.
            let snowman = Decor.emoji("⛄", size: 17, scale: scale)
            snowman.position = CGPoint(x: w * 0.25, y: h / 2 - 1)
            snowman.add(Decor.tilt(0.06, duration: 2.4, phase: 0), forKey: "tilt")
            root.addSublayer(snowman)

            let gift = Decor.emoji("🎁", size: 15, scale: scale)
            gift.position = CGPoint(x: w * 0.705, y: h / 2 - 1)
            gift.add(Decor.bob(dy: 2, duration: 1.8, phase: 0.3), forKey: "bob")
            root.addSublayer(gift)

            let tree = Decor.emoji("🎄", size: 20, scale: scale)
            tree.position = CGPoint(x: w * 0.79, y: h / 2)
            Decor.glow(tree, Self.gold, radius: 3)
            tree.add(Decor.repeating("shadowRadius", from: 1.5, to: 7, duration: 1.6, phase: 0, additive: false), forKey: "star")
            root.addSublayer(tree)
        }

        /// Snowflakes drifting down across the whole bar.
        private func snow(width w: CGFloat, height h: CGFloat, scale: CGFloat) -> CAEmitterLayer {
            let flake = NSImage(size: NSSize(width: 6, height: 6), flipped: false) { r in
                NSColor.white.setFill()
                NSBezierPath(ovalIn: r).fill()
                return true
            }
            let cell = CAEmitterCell()
            cell.contents = flake.cgImage(forProposedRect: nil, context: nil, hints: nil)
            cell.birthRate = 7
            cell.lifetime = 7
            cell.velocity = 9
            cell.velocityRange = 4
            cell.emissionLongitude = -.pi / 2  // straight down
            cell.emissionRange = .pi / 7
            cell.xAcceleration = 1.5
            cell.scale = 0.45
            cell.scaleRange = 0.3
            cell.alphaRange = 0.4
            cell.alphaSpeed = -0.08
            cell.spin = 0.4
            cell.spinRange = 0.8

            let emitter = CAEmitterLayer()
            emitter.frame = CGRect(x: 0, y: 0, width: w, height: h)
            emitter.emitterShape = .line
            emitter.emitterPosition = CGPoint(x: w / 2, y: h + 3)
            emitter.emitterSize = CGSize(width: w, height: 1)
            emitter.contentsScale = scale
            emitter.emitterCells = [cell]
            emitter.masksToBounds = true
            // Start with snow already on screen instead of an empty bar filling up.
            emitter.beginTime = CACurrentMediaTime() - 8
            return emitter
        }
    }
}
