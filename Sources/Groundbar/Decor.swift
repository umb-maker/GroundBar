import AppKit

/// Shared Core Animation helpers for the seasonal decorations (see Halloween.swift, Christmas.swift).
/// The animations run in the window server, so the bar stays near 0% CPU.
enum Decor {
    /// System Settings › Accessibility › Display › Reduce motion: decorations then stand still.
    static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    static func emoji(_ emoji: String, size: CGFloat, scale: CGFloat) -> CALayer {
        let text = NSAttributedString(string: emoji, attributes: [.font: NSFont.systemFont(ofSize: size)])
        let box = text.size()
        let image = NSImage(size: box, flipped: false) { _ in text.draw(at: .zero); return true }
        let l = CALayer()
        l.bounds = CGRect(origin: .zero, size: box)
        l.contentsScale = scale
        l.contents = image.layerContents(forContentsScale: scale)
        return l
    }

    static func repeating(_ keyPath: String, from: Double, to: Double, duration: Double, phase: Double,
                          additive: Bool = true) -> CABasicAnimation {
        let a = CABasicAnimation(keyPath: keyPath)
        a.fromValue = from
        a.toValue = to
        a.duration = duration
        a.autoreverses = true
        a.repeatCount = .infinity
        a.timeOffset = phase * duration
        a.isAdditive = additive
        a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        return a
    }

    static func bob(dy: Double, duration: Double, phase: Double) -> CABasicAnimation {
        repeating("position.y", from: -dy, to: dy, duration: duration, phase: phase)
    }

    static func sway(dx: Double, duration: Double, phase: Double) -> CABasicAnimation {
        repeating("position.x", from: -dx, to: dx, duration: duration, phase: phase)
    }

    static func tilt(_ radians: Double = 0.14, duration: Double, phase: Double) -> CABasicAnimation {
        repeating("transform.rotation.z", from: -radians, to: radians, duration: duration, phase: phase)
    }

    /// Soft glow of a given colour around a layer's content.
    static func glow(_ layer: CALayer, _ color: NSColor, radius: CGFloat) {
        layer.shadowColor = color.cgColor
        layer.shadowOpacity = 0.9
        layer.shadowRadius = radius
        layer.shadowOffset = .zero
    }
}
