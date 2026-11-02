import AppKit

/// Debug aid: `OmniBar --snapshot <dir>` writes PNGs of the bar and flyouts, then quits.
@MainActor
enum Snapshot {
    static func run(to dir: String) {
        let c = TaskbarController.shared
        let steps: [(String, () -> Void)] = [
            ("bar", {}),
            ("start", { c.toggleStart() }),
            ("calendar", { c.closeFlyout(); c.toggleFlyout("calendar", anchor: .right(.greatestFiniteMagnitude), size: CGSize(width: 340, height: 440)) { CalendarFlyout() } }),
            ("quick", { c.closeFlyout(); c.toggleFlyout("quick", anchor: .right(.greatestFiniteMagnitude), size: CGSize(width: 360, height: 220)) { QuickSettingsView(status: c.status, model: c.model) } }),
            ("btc", { c.closeFlyout(); c.toggleFlyout("btc", anchor: .left(8), size: CGSize(width: 380, height: 340)) { CryptoFlyout(ticker: c.crypto) } }),
            ("welcome", { c.closeFlyout(); c.hidePreview(); WelcomeWindow.show() }),
            ("settings", { WelcomeWindow.close(); c.updater.check(); SettingsWindow.show() }),
            ("preview", { c.closeFlyout(); c.showDemoPreview() }),
        ]
        func step(_ i: Int) {
            guard i < steps.count else { NSApp.terminate(nil); return }
            steps[i].1()
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                let windows = NSApp.windows.filter { $0.isVisible && $0.frame.width > 0 }
                let target = steps[i].0 == "bar" ? windows.first { $0 is BarPanel && $0.frame.height == TaskbarController.barHeight }
                    : steps[i].0 == "preview" ? windows.first { $0 is BarPanel && $0.frame.height != TaskbarController.barHeight }
                    : steps[i].0 == "welcome" ? WelcomeWindow.window
                    : steps[i].0 == "settings" ? SettingsWindow.window
                    : windows.first { $0 is FlyoutPanel }
                if let view = target?.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(dir)/\(steps[i].0).png"))
                }
                // cacheDisplay skips Core Animation sublayers (Halloween decorations): also render the layer tree.
                if steps[i].0 == "bar", let view = target?.contentView, let layer = view.layer,
                   let ctx = CGContext(data: nil, width: Int(view.bounds.width * 2), height: Int(view.bounds.height * 2), bitsPerComponent: 8,
                                       bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                    ctx.scaleBy(x: 2, y: 2)
                    layer.render(in: ctx)
                    if let image = ctx.makeImage() {
                        try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?
                            .write(to: URL(fileURLWithPath: "\(dir)/bar-layers.png"))
                    }
                }
                step(i + 1)
            }
        }
        step(0)
    }
}

extension TaskbarController {
    /// Debug: opens the window picker with sample documents.
    func showDemoPreview() {
        let names = ["Quarterly report.docx", "Budget 2026.xlsx", "Signed contract.pdf", "Meeting minutes.docx",
                     "October invoices.xlsx", "User manual.pdf", "Customer letter.docx"]
        let docs = names.enumerated().map { i, n in
            AppWindow(id: "demo\(i)", title: n, frame: .zero, scWindow: nil,
                      document: URL(fileURLWithPath: "/tmp/\(n)"), minimized: i == 3)
        }
        let icon = NSWorkspace.shared.icon(forFile: "/System/Applications/TextEdit.app")
        preview.loadStatic(docs, name: "Microsoft Word", icon: icon)
        showPreviewPanel(anchor: CGRect(x: 700, y: 0, width: 44, height: 40))
    }
}
