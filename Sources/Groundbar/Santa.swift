import AppKit
import SwiftUI

/// "Babbo Natale" theme decorations: a night sky with twinkling stars, a glowing moon, and Santa's sleigh
/// flying across the bar every so often, leaving a trail of golden sparkles. Core Animation only (see
/// Decor.swift): the flight is one keyframe animation, so the bar stays near 0% CPU. Never receives clicks.
struct SantaDecor: NSViewRepresentable {
    func makeNSView(context: Context) -> DecorView { DecorView() }
    func updateNSView(_ view: DecorView, context: Context) {}

    final class DecorView: NSView {
        private static let gold = NSColor(red: 0.96, green: 0.78, blue: 0.32, alpha: 1)
        /// One flight takes `flight` seconds and starts again every `cycle` seconds.
        private static let flight: Double = 12
        private static let cycle: Double = 26
        /// `GROUNDBAR_DEBUG_SLEIGH=<fraction of the bar width>` parks the sleigh there without animating
        /// (for `--snapshot` checks; `1` means the middle of the bar).
        private static let debugParked: CGFloat? = ProcessInfo.processInfo.environment["GROUNDBAR_DEBUG_SLEIGH"]
            .flatMap(Double.init).map { $0 >= 1 ? 0.4 : CGFloat($0) }

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

            addStars(to: root, width: w, height: h)

            let moon = Decor.emoji("🌙", size: 17, scale: scale)
            moon.position = CGPoint(x: w * 0.79, y: h / 2)
            Decor.glow(moon, .white, radius: 4)
            moon.add(Decor.repeating("shadowRadius", from: 2, to: 7, duration: 3, phase: 0, additive: false), forKey: "glow")
            root.addSublayer(moon)

            let sleigh = makeSleigh(scale: scale)
            root.addSublayer(sleigh)
            let trail = makeTrail(scale: scale)
            root.addSublayer(trail)

            if let parked = Self.debugParked {
                sleigh.position = CGPoint(x: w * parked, y: h / 2)
                return
            }
            // Parked off-screen between flights; the animation only covers the crossing.
            sleigh.position = CGPoint(x: -200, y: h / 2)
            trail.emitterPosition = CGPoint(x: -200, y: h / 2)

            // Right to left with a gentle up-and-down glide.
            let steps = 24
            let path: [CGPoint] = (0...steps).map { i in
                let t = CGFloat(i) / CGFloat(steps)
                return CGPoint(x: w + 120 - t * (w + 320), y: h / 2 + sin(t * .pi * 6) * 5)
            }
            let start = CACurrentMediaTime() + 3
            sleigh.add(flightAnimation("position", path, start: start), forKey: "flight")
            // The sparkles leave from the back of the sleigh (its right side while flying left).
            let back = sleigh.bounds.width / 2 - 8
            trail.add(flightAnimation("emitterPosition", path.map { CGPoint(x: $0.x + back, y: $0.y - 2) }, start: start), forKey: "flight")
        }

        private func flightAnimation(_ keyPath: String, _ path: [CGPoint], start: CFTimeInterval) -> CAAnimationGroup {
            let move = CAKeyframeAnimation(keyPath: keyPath)
            move.values = path.map { NSValue(point: $0) }
            move.calculationMode = .cubic
            move.duration = Self.flight
            let group = CAAnimationGroup()
            group.animations = [move]
            group.duration = Self.cycle
            group.repeatCount = .infinity
            group.beginTime = start
            return group
        }

        /// Two reindeer pulling the sleigh with Santa on it, as one layer.
        private func makeSleigh(scale: CGFloat) -> CALayer {
            let group = CALayer()
            group.bounds = CGRect(x: 0, y: 0, width: 66, height: 26)
            for (i, x) in [CGFloat(8), 26].enumerated() {
                let deer = Decor.emoji("🦌", size: 14, scale: scale)
                deer.position = CGPoint(x: x, y: 11)
                // The two reindeer trot slightly out of step.
                deer.add(Decor.bob(dy: 1.5, duration: 0.45, phase: Double(i) * 0.5), forKey: "trot")
                group.addSublayer(deer)
            }
            let sled = Decor.emoji("🛷", size: 16, scale: scale)
            sled.position = CGPoint(x: 52, y: 9)
            group.addSublayer(sled)
            let santa = Decor.emoji("🎅", size: 12, scale: scale)
            santa.position = CGPoint(x: 53, y: 17)
            group.addSublayer(santa)
            return group
        }

        private func makeTrail(scale: CGFloat) -> CAEmitterLayer {
            let dot = NSImage(size: NSSize(width: 4, height: 4), flipped: false) { r in
                Self.gold.setFill()
                NSBezierPath(ovalIn: r).fill()
                return true
            }
            let cell = CAEmitterCell()
            cell.contents = dot.cgImage(forProposedRect: nil, context: nil, hints: nil)
            cell.birthRate = 30
            cell.lifetime = 1.3
            cell.velocity = 5
            cell.velocityRange = 4
            cell.emissionRange = .pi * 2
            cell.yAcceleration = -6
            cell.scale = 0.6
            cell.scaleRange = 0.3
            cell.scaleSpeed = -0.3
            cell.alphaSpeed = -0.75

            let emitter = CAEmitterLayer()
            emitter.frame = bounds
            emitter.emitterShape = .point
            emitter.renderMode = .additive
            emitter.contentsScale = scale
            emitter.emitterCells = [cell]
            return emitter
        }

        /// A handful of small stars at fixed, scattered spots, each twinkling at its own pace.
        private func addStars(to root: CALayer, width w: CGFloat, height h: CGFloat) {
            let spots: [(x: CGFloat, y: CGFloat)] = [
                (0.18, 0.75), (0.21, 0.30), (0.27, 0.62), (0.31, 0.20), (0.36, 0.80),
                (0.64, 0.25), (0.67, 0.72), (0.72, 0.40), (0.75, 0.82), (0.83, 0.28), (0.86, 0.70),
            ]
            for (i, s) in spots.enumerated() {
                let star = CALayer()
                let size: CGFloat = i % 3 == 0 ? 2.5 : 1.8
                star.bounds = CGRect(x: 0, y: 0, width: size, height: size)
                star.cornerRadius = size / 2
                star.position = CGPoint(x: w * s.x, y: h * s.y)
                star.backgroundColor = NSColor.white.cgColor
                Decor.glow(star, .white, radius: 2)
                star.add(Decor.repeating("opacity", from: 1, to: 0.2, duration: 1.4 + Double(i % 4) * 0.5,
                                         phase: Double((i * 5) % 9) / 9, additive: false), forKey: "twinkle")
                root.addSublayer(star)
            }
        }
    }
}
