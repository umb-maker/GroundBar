import AppKit
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            Log.write("start: axTrusted=\(AXIsProcessTrusted()) screen=\(CGPreflightScreenCaptureAccess())")
            TaskbarController.shared.start()
            let args = CommandLine.arguments
            if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
                Snapshot.run(to: args[i + 1])
            } else {
                // Permissions are requested from the welcome window, with an explanation, not at launch.
                WelcomeWindow.showIfNeeded()
            }
        }
    }
}
