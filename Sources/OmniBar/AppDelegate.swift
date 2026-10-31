import AppKit
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            // Accessibility: needed to raise/minimise/close windows and read their titles.
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(opts)
            // Screen Recording: needed for window thumbnails.
            if !CGPreflightScreenCaptureAccess() { _ = CGRequestScreenCaptureAccess() }
            Log.write("start: axTrusted=\(AXIsProcessTrusted()) screen=\(CGPreflightScreenCaptureAccess())")
            TaskbarController.shared.start()
            let args = CommandLine.arguments
            if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count { Snapshot.run(to: args[i + 1]) }
        }
    }
}
