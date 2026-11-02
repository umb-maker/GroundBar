// Renders the GitHub social preview (1280x640) for Groundbar.
// Usage: swift scripts/social-preview.swift . social.png  (then resize to 1280x640: sips -z 640 1280 social.png)
import AppKit

let args = CommandLine.arguments
let repo = URL(fileURLWithPath: args[1])
let out = URL(fileURLWithPath: args[2])
func img(_ p: String) -> NSImage { NSImage(contentsOf: repo.appendingPathComponent(p))! }

let W: CGFloat = 1280, H: CGFloat = 640, S: CGFloat = 2
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W * S), pixelsHigh: Int(H * S), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: W, height: H)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current?.imageInterpolation = .high

// Background: deep navy (the Omega coin's backdrop) to dark violet.
NSGradient(colors: [NSColor(red: 0.06, green: 0.11, blue: 0.15, alpha: 1), NSColor(red: 0.09, green: 0.05, blue: 0.14, alpha: 1)])!
    .draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -25)
// Soft orange glow behind the coin.
let glow = NSGradient(colors: [NSColor(red: 1, green: 0.5, blue: 0.05, alpha: 0.35), NSColor(red: 1, green: 0.5, blue: 0.05, alpha: 0)])!
glow.draw(fromCenter: NSPoint(x: 165, y: 455), radius: 0, toCenter: NSPoint(x: 165, y: 455), radius: 190, options: [])

func shadowed(_ draw: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let sh = NSShadow()
    sh.shadowColor = NSColor.black.withAlphaComponent(0.55)
    sh.shadowBlurRadius = 24
    sh.shadowOffset = NSSize(width: 0, height: -8)
    sh.set()
    draw()
    NSGraphicsContext.restoreGraphicsState()
}

// Omega coin, clipped round.
let coin = NSRect(x: 80, y: 370, width: 170, height: 170)
NSGraphicsContext.saveGraphicsState()
NSBezierPath(ovalIn: coin).addClip()
img("Resources/StartIcon.png").draw(in: coin)
NSGraphicsContext.restoreGraphicsState()

func text(_ s: String, _ font: NSFont, _ color: NSColor, at p: NSPoint) {
    NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color]).draw(at: p)
}
let ivory = NSColor(red: 1, green: 0.94, blue: 0.86, alpha: 1)
let orange = NSColor(red: 1, green: 0.55, blue: 0.12, alpha: 1)
text("Groundbar", .systemFont(ofSize: 92, weight: .heavy), .white, at: NSPoint(x: 282, y: 418))
text("A Windows-style taskbar for macOS", .systemFont(ofSize: 34, weight: .medium), ivory.withAlphaComponent(0.85), at: NSPoint(x: 86, y: 300))

let features = ["Start menu with app & file search", "Per-app document list", "Recent files & jump lists",
                "Bitcoin widget · Light, dark & seasonal themes"]
for (i, f) in features.enumerated() {
    let y = 246 - CGFloat(i) * 40
    NSColor(red: 1, green: 0.55, blue: 0.12, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: 90, y: y + 9, width: 10, height: 10)).fill()
    text(f, .systemFont(ofSize: 24, weight: .regular), ivory.withAlphaComponent(0.8), at: NSPoint(x: 112, y: y))
}
text("Native Swift · Open source (MIT)", .systemFont(ofSize: 18, weight: .semibold), orange, at: NSPoint(x: 90, y: 92))

// Screenshots on the right: the document list over the Bitcoin chart.
func card(_ image: NSImage, _ rect: NSRect) {
    shadowed {
        let path = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        image.draw(in: rect)
        NSGraphicsContext.restoreGraphicsState()
    }
}
card(img("docs/images/btc.png"), NSRect(x: 900, y: 300, width: 330, height: 278))
card(img("docs/images/window-list.png"), NSRect(x: 700, y: 150, width: 300, height: 278))

// The bar itself along the bottom edge.
let bar = img("docs/images/bar-halloween.png")
let barH = W * bar.size.height / bar.size.width
shadowed { bar.draw(in: NSRect(x: 0, y: 0, width: W, height: barH)) }

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: out)
print("ok \(rep.pixelsWide)x\(rep.pixelsHigh)")
