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
        TaskbarController.shared.showToast(
            title: "Screenshot salvato e copiato negli appunti",
            detail: url.lastPathComponent
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
        f.dateFormat = "yyyy-MM-dd 'alle' HH.mm.ss"
        return "Screenshot \(f.string(from: Date())).png"
    }
}

/// Small notification shown above the right end of the bar.
struct ToastView: View {
    let title: String
    let detail: String
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let f = Fluent(scheme)
        HStack(spacing: 12) {
            Image(systemName: "camera.viewfinder").font(.system(size: 20)).foregroundStyle(f.accent)
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
            TaskbarController.shared.hideToast()
            action()
        }
        .help("Clic per aprire lo screenshot")
    }
}
