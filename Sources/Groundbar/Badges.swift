import AppKit
import ApplicationServices

/// The badges apps put on their Dock icon (unread mail, messages), read from the Dock's accessibility
/// tree: macOS has no public API that tells another app's badge.
enum DockBadges {
    /// Badge text per app bundle path. Runs on `WindowScanner`'s queue: Accessibility calls wait on the Dock.
    nonisolated static func read() -> [String: String] {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return [:] }
        let app = AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.25)
        let lists = children(of: app).filter { WindowService.string($0, kAXRoleAttribute) == kAXListRole as String }
        var badges: [String: String] = [:]
        for item in lists.flatMap(children(of:)) {
            guard let label = WindowService.string(item, "AXStatusLabel"), !label.isEmpty,
                  let url = WindowService.attribute(item, kAXURLAttribute) as? URL else { continue }
            badges[url.standardizedFileURL.path] = label
        }
        return badges
    }

    nonisolated private static func children(of element: AXUIElement) -> [AXUIElement] {
        WindowService.attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }
}
