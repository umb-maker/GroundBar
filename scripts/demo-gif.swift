// Builds the README demo GIF from Groundbar's own --snapshot renders (no screen recording involved).
// Usage: swift scripts/demo-gif.swift <input folder> <output.gif>
//
// The input folder holds @2x PNGs rendered with GROUNDBAR_DEMO=1 (sample apps and files) in English:
//   bar-dark.png bar-halloween.png bar-christmas.png bar-santa.png (bar layer renders, sleigh-free for Santa)
//   sleigh.png (the sleigh cropped from a Santa render), start.png preview.png btc.png quick.png
import AppKit
import ImageIO
import UniformTypeIdentifiers

let input = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])
func load(_ name: String) -> NSImage { NSImage(contentsOf: input.appendingPathComponent(name))! }

// Canvas: a 1440x900 pt screen at 2/3 scale. Inputs are @2x, so 1 input pixel = 1/3 canvas pixel.
let W: CGFloat = 960, H: CGFloat = 600, k: CGFloat = 1.0 / 3.0
let barH: CGFloat = 96 * k

let bars = ["dark": load("bar-dark.png"), "halloween": load("bar-halloween.png"),
            "christmas": load("bar-christmas.png"), "santa": load("bar-santa.png")]
let sleigh = load("sleigh.png")
let start = load("start.png"), preview = load("preview.png"), btc = load("btc.png"), quick = load("quick.png")

/// Fixed random grain (same in every frame, so it doesn't flicker).
let grain: NSImage = {
    var rng = SystemRandomNumberGenerator()
    let img = NSImage(size: NSSize(width: W, height: H))
    img.lockFocus()
    for _ in 0..<Int(W * H / 3) {
        let v = CGFloat(Double(rng.next() % 1000) / 1000)
        NSColor(white: v > 0.5 ? 1 : 0, alpha: 0.05).setFill()
        NSRect(x: CGFloat(rng.next() % UInt64(W)), y: CGFloat(rng.next() % UInt64(H)), width: 1, height: 1).fill()
    }
    img.unlockFocus()
    return img
}()

struct Panel {
    let image: NSImage
    let x: CGFloat           // left edge on the canvas
    var progress: CGFloat    // 0 = hidden, 1 = fully shown (slides up and fades in)
}

func size(_ image: NSImage) -> CGSize {
    let rep = image.representations.first!
    return CGSize(width: CGFloat(rep.pixelsWide) * k, height: CGFloat(rep.pixelsHigh) * k)
}

func frame(bar: String, caption: String, panels: [Panel] = [], sleighX: CGFloat? = nil) -> CGImage {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high

    // Wallpaper: a gentle gradient plus fine grain, so the GIF's 256 colours don't show bands.
    NSGradient(colors: [NSColor(red: 0.16, green: 0.25, blue: 0.43, alpha: 1), NSColor(red: 0.30, green: 0.22, blue: 0.45, alpha: 1)])!
        .draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -35)
    grain.draw(in: NSRect(x: 0, y: 0, width: W, height: H))

    // Caption, top-left.
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.4)
    shadow.shadowBlurRadius = 8
    NSAttributedString(string: caption, attributes: [
        .font: NSFont.systemFont(ofSize: 30, weight: .bold), .foregroundColor: NSColor.white, .shadow: shadow,
    ]).draw(at: NSPoint(x: 36, y: H - 68))

    // Panels above the bar.
    for p in panels where p.progress > 0 {
        let s = size(p.image)
        let t = 1 - pow(1 - p.progress, 3)  // ease-out
        let rect = NSRect(x: p.x, y: barH + 8 - (1 - t) * 24, width: s.width, height: s.height)
        NSGraphicsContext.saveGraphicsState()
        let sh = NSShadow()
        sh.shadowColor = NSColor.black.withAlphaComponent(0.45 * t)
        sh.shadowBlurRadius = 18
        sh.shadowOffset = NSSize(width: 0, height: -6)
        sh.set()
        p.image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: t)
        NSGraphicsContext.restoreGraphicsState()
    }

    // The bar along the bottom edge, and the flying sleigh on top of it.
    bars[bar]!.draw(in: NSRect(x: 0, y: 0, width: W, height: barH))
    if let x = sleighX {
        let s = size(sleigh)
        sleigh.draw(in: NSRect(x: x, y: 0, width: s.width, height: s.height))
        // In the app the sleigh flies behind the icons: draw the centred icon group again on top of it.
        let icons = NSRect(x: 336, y: 0, width: 292, height: barH)
        bars[bar]!.draw(in: icons, from: NSRect(x: icons.minX / k, y: 0, width: icons.width / k, height: 96),
                        operation: .sourceOver, fraction: 1)
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.cgImage!
}

var frames: [(CGImage, Double)] = []
func hold(_ image: CGImage, _ seconds: Double) { frames.append((image, seconds)) }
/// A panel sliding in over a few frames, then held.
func reveal(_ caption: String, _ image: NSImage, x: CGFloat, holdFor seconds: Double) {
    for step in 1...4 { hold(frame(bar: "dark", caption: caption, panels: [Panel(image: image, x: x, progress: CGFloat(step) / 4)]), 0.05) }
    hold(frame(bar: "dark", caption: caption, panels: [Panel(image: image, x: x, progress: 1)]), seconds)
}

hold(frame(bar: "dark", caption: "Groundbar · a Windows-style taskbar for macOS"), 1.8)
reveal("Start menu: recent apps, files, search", start, x: (W - size(start).width) / 2, holdFor: 2.6)
reveal("Every open document, one click away", preview, x: W * 0.44, holdFor: 2.4)
reveal("Bitcoin widget", btc, x: 6, holdFor: 2.0)
reveal("Quick settings", quick, x: W - size(quick).width - 8, holdFor: 1.6)
hold(frame(bar: "halloween", caption: "Seasonal themes 🎃"), 1.3)
hold(frame(bar: "christmas", caption: "Seasonal themes 🎄"), 1.3)
// Santa's sleigh crosses the bar right to left, leaving before the Bitcoin widget (it flies behind it in the app).
let steps = 22
for i in 0...steps {
    let x = W + 10 - CGFloat(i) / CGFloat(steps) * (W - 150)
    hold(frame(bar: "santa", caption: "Seasonal themes 🎅", sleighX: x), 0.08)
}
hold(frame(bar: "santa", caption: "Seasonal themes 🎅"), 0.6)

let dest = CGImageDestinationCreateWithURL(output as CFURL, UTType.gif.identifier as CFString, frames.count, nil)!
CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
for (image, delay) in frames {
    CGImageDestinationAddImage(dest, image, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay,
                                                                           kCGImagePropertyGIFUnclampedDelayTime: delay]] as CFDictionary)
}
guard CGImageDestinationFinalize(dest) else { fatalError("could not write \(output.path)") }
let total = frames.reduce(0) { $0 + $1.1 }
print("ok: \(frames.count) frames, \(String(format: "%.1f", total)) s")
