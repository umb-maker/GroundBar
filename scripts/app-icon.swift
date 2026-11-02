// Draws OmniBar's 1024x1024 app icon: the Omega coin on a night-blue rounded square (macOS icon grid).
// Usage: swift scripts/app-icon.swift <coin image> <output.png> [x y size]
//   x y size: square crop of the coin in the source image, in pixels from the top-left
//   (defaults match the original artwork, a 2000x2000 image).
import AppKit

let args = CommandLine.arguments
let source = NSImage(contentsOf: URL(fileURLWithPath: args[1]))!
let out = URL(fileURLWithPath: args[2])
let crop = args.count >= 6 ? args[3...5].map { CGFloat(Double($0)!) } : [1020, 1064, 776]
let srcSize = source.representations.first.map { CGSize(width: $0.pixelsWide, height: $0.pixelsHigh) } ?? source.size

let N: CGFloat = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(N), pixelsHigh: Int(N), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: N, height: N)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current?.imageInterpolation = .high

// Rounded square of the macOS icon grid (824 pt inside 1024, ~185 pt corners), with a soft shadow.
let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let shape = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
shadow.shadowBlurRadius = 24
shadow.shadowOffset = NSSize(width: 0, height: -10)
shadow.set()
NSColor(red: 0.05, green: 0.09, blue: 0.13, alpha: 1).setFill()
shape.fill()
NSGraphicsContext.restoreGraphicsState()

NSGraphicsContext.saveGraphicsState()
shape.addClip()
// Night-blue background, lighter in the middle, with a warm glow behind the coin.
let center = NSPoint(x: N / 2, y: N / 2)
NSGradient(colors: [NSColor(red: 0.11, green: 0.19, blue: 0.25, alpha: 1), NSColor(red: 0.04, green: 0.07, blue: 0.10, alpha: 1)])!
    .draw(fromCenter: center, radius: 0, toCenter: center, radius: 600, options: [.drawsAfterEndingLocation])
NSGradient(colors: [NSColor(red: 1, green: 0.45, blue: 0.05, alpha: 0.45), NSColor(red: 1, green: 0.45, blue: 0.05, alpha: 0)])!
    .draw(fromCenter: center, radius: 250, toCenter: center, radius: 420, options: [])

// The coin, clipped round (source rect is bottom-left based in AppKit).
let coin = NSRect(x: (N - 640) / 2, y: (N - 640) / 2, width: 640, height: 640)
let from = NSRect(x: crop[0], y: srcSize.height - crop[1] - crop[2], width: crop[2], height: crop[2])
NSGraphicsContext.saveGraphicsState()
NSBezierPath(ovalIn: coin).addClip()
source.draw(in: coin, from: from, operation: .sourceOver, fraction: 1)
NSGraphicsContext.restoreGraphicsState()

// Subtle top highlight on the tile edge.
NSColor.white.withAlphaComponent(0.08).setStroke()
let rim = NSBezierPath(roundedRect: tile.insetBy(dx: 1.5, dy: 1.5), xRadius: 184, yRadius: 184)
rim.lineWidth = 3
rim.stroke()
NSGraphicsContext.restoreGraphicsState()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: out)
print("ok \(rep.pixelsWide)x\(rep.pixelsHigh)")
