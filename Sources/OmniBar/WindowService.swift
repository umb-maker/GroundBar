import AppKit
import ApplicationServices
import ScreenCaptureKit

struct AppWindow: Identifiable {
    let id: String
    let title: String
    let frame: CGRect          // global, top-left origin (CG/AX coordinates)
    let scWindow: SCWindow?
    let document: URL?         // file shown in the window (AXDocument), when the app exposes it
    let minimized: Bool

    /// File name for document windows, the window title otherwise.
    var displayName: String { document?.lastPathComponent ?? title }
}

/// Window enumeration (ScreenCaptureKit / Accessibility) and window control (Accessibility).
@MainActor
enum WindowService {
    // MARK: Accessibility helpers

    /// Apps already asked to build their accessibility tree (done once per process).
    private static var awakened = Set<pid_t>()
    private static var lastHasWindows: [pid_t: Bool] = [:]

    static func axWindows(pid: pid_t) -> [AXUIElement] {
        let app = AXUIElementCreateApplication(pid)
        // The bar polls every app: never let a hung app block it for the default 6 s.
        AXUIElementSetMessagingTimeout(app, 0.25)
        var value: CFTypeRef?
        var error = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value)
        if (error != .success || (value as? [AXUIElement])?.isEmpty != false), awakened.insert(pid).inserted {
            // Some apps (e.g. Microsoft Office) only build their accessibility tree once an assistive client asks for it.
            AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
            error = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value)
        }
        guard error == .success, let windows = value as? [AXUIElement] else { return [] }
        // Real document windows are AXStandardWindow; some apps (Microsoft Word) report minimised
        // documents as AXDialog, so a minimised window always counts.
        return windows.filter {
            string($0, kAXSubroleAttribute) == kAXStandardWindowSubrole as String || bool($0, kAXMinimizedAttribute) == true
        }
    }

    /// Called on every poll with the files shown in the app's windows (feeds the recent-documents history).
    static var onDocuments: ((NSRunningApplication, [URL]) -> Void)?

    /// Whether the app has at least one window (minimised included). Without Accessibility we cannot
    /// tell, so every running app counts as having one.
    static func hasWindows(_ app: NSRunningApplication) -> Bool {
        guard AXIsProcessTrusted() else { return true }
        let windows = axWindows(pid: app.processIdentifier)
        let documents = windows.compactMap { string($0, kAXDocumentAttribute).flatMap { URL(string: $0) } }.filter(\.isFileURL)
        onDocuments?(app, documents)
        let result = !windows.isEmpty
        if lastHasWindows[app.processIdentifier] != result {
            lastHasWindows[app.processIdentifier] = result
            Log.write("hasWindows(\(app.localizedName ?? "?")) = \(result)")
            logAX(pid: app.processIdentifier, name: app.localizedName ?? "?")
        }
        return result
    }

    /// Diagnostics for apps whose windows Accessibility does not report.
    static func logAX(pid: pid_t, name: String) {
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value)
        let raw = value as? [AXUIElement] ?? []
        let details = raw.map { "[\(string($0, kAXRoleAttribute) ?? "-")/\(string($0, kAXSubroleAttribute) ?? "-") \"\(string($0, kAXTitleAttribute) ?? "")\" min=\(bool($0, kAXMinimizedAttribute).map { "\($0)" } ?? "-")]" }
        Log.write("ax(\(name)): error=\(error.rawValue) raw=\(raw.count) \(details.joined(separator: " "))")
        let cg = (CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? [])
            .filter { ($0[kCGWindowOwnerPID as String] as? pid_t) == pid && ($0[kCGWindowLayer as String] as? Int) == 0 }
            .map { w -> String in
                let b = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
                return "[\"\(w[kCGWindowName as String] as? String ?? "nil")\" \(b["Width"] ?? 0)x\(b["Height"] ?? 0) on=\(w[kCGWindowIsOnscreen as String] as? Bool ?? false) a=\(w[kCGWindowAlpha as String] ?? 0)]"
            }
        Log.write("cg(\(name)): \(cg.count) \(cg.joined(separator: " "))")
    }

    static func attribute(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, name as CFString, &value) == .success ? value : nil
    }

    static func string(_ el: AXUIElement, _ name: String) -> String? { attribute(el, name) as? String }

    static func bool(_ el: AXUIElement, _ name: String) -> Bool? { (attribute(el, name) as? NSNumber)?.boolValue }

    static func frame(_ el: AXUIElement) -> CGRect? {
        guard let p = attribute(el, kAXPositionAttribute), let s = attribute(el, kAXSizeAttribute) else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &point), AXValueGetValue(s as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
    }

    private static func match(_ window: AppWindow, pid: pid_t) -> AXUIElement? {
        let candidates = axWindows(pid: pid)
        func close(_ a: CGRect, _ b: CGRect) -> Bool { abs(a.minX - b.minX) < 4 && abs(a.minY - b.minY) < 4 && abs(a.width - b.width) < 4 }
        return candidates.first { string($0, kAXTitleAttribute) == window.title && frame($0).map { close($0, window.frame) } == true }
            ?? candidates.first { string($0, kAXTitleAttribute) == window.title }
            ?? candidates.first { frame($0).map { close($0, window.frame) } == true }
    }

    // MARK: Actions

    /// Brings an app to the front, restoring a minimised window or asking it to reopen one if it has none.
    static func activate(_ app: NSRunningApplication) {
        guard AXIsProcessTrusted() else { reopen(app); return }
        let windows = axWindows(pid: app.processIdentifier)
        if windows.isEmpty { reopen(app); return }
        if windows.allSatisfy({ bool($0, kAXMinimizedAttribute) == true }), let first = windows.first {
            AXUIElementSetAttributeValue(first, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            AXUIElementPerformAction(first, kAXRaiseAction as CFString)
        }
        setFrontmost(app)
    }

    static func focus(_ window: AppWindow, of app: NSRunningApplication) {
        if app.isHidden { app.unhide() }
        if let el = match(window, pid: app.processIdentifier) {
            AXUIElementSetAttributeValue(el, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            AXUIElementSetAttributeValue(el, kAXMainAttribute as CFString, kCFBooleanTrue)
            AXUIElementPerformAction(el, kAXRaiseAction as CFString)
        }
        setFrontmost(app)
    }

    static func close(_ window: AppWindow, of app: NSRunningApplication) {
        guard let el = match(window, pid: app.processIdentifier),
              let button = attribute(el, kAXCloseButtonAttribute) else { return }
        AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString)
    }

    private static func setFrontmost(_ app: NSRunningApplication) {
        let el = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetAttributeValue(el, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        app.activate()
    }

    private static func reopen(_ app: NSRunningApplication) {
        guard let url = app.bundleURL else { app.activate(); return }
        TaskbarModel.launch(url)
    }

    // MARK: Enumeration

    /// The app's real windows. Accessibility is the source of truth (it includes minimised windows and the
    /// open document); ScreenCaptureKit windows are matched to them for thumbnails.
    static func windows(of app: NSRunningApplication) async -> [AppWindow] {
        let pid = app.processIdentifier
        let ax = axWindows(pid: pid).map { el in
            (title: string(el, kAXTitleAttribute) ?? "",
             frame: frame(el) ?? .zero,
             document: string(el, kAXDocumentAttribute).flatMap { URL(string: $0) },
             minimized: bool(el, kAXMinimizedAttribute) ?? false)
        }

        var captured: [SCWindow] = []
        if CGPreflightScreenCaptureAccess(),
           let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false) {
            captured = content.windows.filter {
                $0.owningApplication?.processID == pid && $0.windowLayer == 0 && $0.frame.width >= 80 && $0.frame.height >= 60
            }
        }

        Log.write("windows(\(app.localizedName ?? "?")): ax=0 sc=\(captured.count) axTrusted=\(AXIsProcessTrusted()) screen=\(CGPreflightScreenCaptureAccess())")
        if ax.isEmpty {
            logAX(pid: pid, name: app.localizedName ?? "?")
            Log.write("sc(\(app.localizedName ?? "?")): " + captured.map { "[\($0.title ?? "nil") \(Int($0.frame.width))x\(Int($0.frame.height)) onScreen=\($0.isOnScreen)]" }.joined(separator: " "))
            return captured.compactMap { w in
                guard let title = w.title, !title.isEmpty else { return nil }
                return AppWindow(id: "sc\(w.windowID)", title: title, frame: w.frame, scWindow: w, document: nil, minimized: !w.isOnScreen)
            }
        }

        Log.write("windows(\(app.localizedName ?? "?")): ax=\(ax.count) sc=\(captured.count) axTrusted=\(AXIsProcessTrusted()) screen=\(CGPreflightScreenCaptureAccess())")

        var unused = captured
        return ax.enumerated().map { i, w in
            let index = unused.firstIndex { $0.title == w.title && abs($0.frame.minX - w.frame.minX) < 4 && abs($0.frame.minY - w.frame.minY) < 4 }
                ?? unused.firstIndex { $0.title == w.title }
            let match = index.map { unused.remove(at: $0) }
            let title = w.title.isEmpty ? (w.document?.lastPathComponent ?? app.localizedName ?? "") : w.title
            return AppWindow(id: match.map { "sc\($0.windowID)" } ?? "ax\(i)", title: title, frame: w.frame,
                             scWindow: match, document: w.document, minimized: w.minimized)
        }
    }

    /// Number of standard windows, cheap enough to call on every click.
    static func windowCount(of app: NSRunningApplication) -> Int {
        AXIsProcessTrusted() ? axWindows(pid: app.processIdentifier).count : 0
    }

    static func thumbnail(_ window: SCWindow, maxSize: CGSize) async -> NSImage? {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let cfg = SCStreamConfiguration()
        let scale = min(maxSize.width / window.frame.width, maxSize.height / window.frame.height) * 2
        cfg.width = max(1, Int(window.frame.width * scale))
        cfg.height = max(1, Int(window.frame.height * scale))
        cfg.showsCursor = false
        cfg.ignoreShadowsSingleWindow = true
        guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }
}
