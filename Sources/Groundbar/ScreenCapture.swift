import AppKit
import SwiftUI

/// Screenshots through the system `screencapture` tool: saved where macOS saves screenshots and copied to the clipboard.
@MainActor
enum ScreenCapture {
    static func capture(region: Bool) {
        let c = TaskbarController.shared
        c.closeFlyout()
        c.hidePreview()
        let url = folder().appendingPathComponent(fileName())
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        // -i: interactive selection (Space switches to window mode, Esc cancels).
        p.arguments = region ? ["-i", url.path] : [url.path]
        p.terminationHandler = { _ in
            Task { @MainActor in finished(url) }
        }
        // Let the button's pressed state clear before the screen is grabbed.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            do { try p.run() } catch { Log.write("screencapture: \(error.localizedDescription)") }
        }
    }

    private static func finished(_ url: URL) {
        // No file means the selection was cancelled.
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        if let image = NSImage(contentsOf: url) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([image])
        }
        TaskbarController.shared.toast.show(
            title: L("Screenshot saved and copied to the clipboard"),
            detail: url.lastPathComponent,
            symbol: "camera.viewfinder"
        ) {
            NSWorkspace.shared.open(url)
        }
    }

    /// The folder set in the Screenshot app (com.apple.screencapture "location"), or the Desktop.
    private static func folder() -> URL {
        let fm = FileManager.default
        if let path = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location") {
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue { return url }
        }
        return fm.urls(for: .desktopDirectory, in: .userDomainMask).first ?? fm.homeDirectoryForCurrentUser
    }

    private static func fileName() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd '\(L("at"))' HH.mm.ss"
        return "Screenshot \(f.string(from: Date())).png"
    }
}
