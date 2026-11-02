import AppKit
import Combine

struct TaskItem: Identifiable, Equatable {
    let id: String          // bundle identifier, or the bundle path for apps without one
    let name: String
    let icon: NSImage
    let url: URL?
    var app: NSRunningApplication?
    var pinned: Bool
    var isActive: Bool
    var hasWindows: Bool

    var isRunning: Bool { app.map { !$0.isTerminated } ?? false }

    static func == (a: TaskItem, b: TaskItem) -> Bool {
        a.id == b.id && a.app?.processIdentifier == b.app?.processIdentifier
            && a.pinned == b.pinned && a.isActive == b.isActive && a.hasWindows == b.hasWindows
    }
}

/// Pinned + running apps, active app tracking, and the app-level actions of the bar.
@MainActor
final class TaskbarModel: ObservableObject {
    @Published private(set) var items: [TaskItem] = []
    @Published var theme: ThemeMode {
        didSet {
            UserDefaults.standard.set(theme.rawValue, forKey: "theme")
            Fluent.theme = theme
        }
    }
    @Published var centered: Bool {
        didSet { UserDefaults.standard.set(centered, forKey: "centered") }
    }
    @Published var showCrypto: Bool {
        didSet {
            UserDefaults.standard.set(showCrypto, forKey: "showCrypto")
            if showCrypto && !oldValue { TaskbarController.shared.crypto.refresh() }
        }
    }
    @Published var showScreenshotButtons: Bool {
        didSet { UserDefaults.standard.set(showScreenshotButtons, forKey: "showScreenshotButtons") }
    }

    private var pinnedIDs: [String]
    private var iconCache: [String: NSImage] = [:]
    private var lastActivePID: pid_t?
    private var hiddenForDesktop: [NSRunningApplication] = []
    private var desktopToggledAt = Date.distantPast
    private var observers: [NSObjectProtocol] = []
    private var pollTimer: Timer?

    static let defaultPins = ["com.apple.finder", "com.apple.Safari", "com.apple.mail", "com.apple.iCal", "com.apple.systempreferences"]

    init() {
        let d = UserDefaults.standard
        pinnedIDs = d.stringArray(forKey: "pinned") ?? Self.defaultPins
        theme = ThemeMode(rawValue: d.string(forKey: "theme") ?? "") ?? .system
        centered = d.object(forKey: "centered") as? Bool ?? true
        showCrypto = d.object(forKey: "showCrypto") as? Bool ?? true
        showScreenshotButtons = d.object(forKey: "showScreenshotButtons") as? Bool ?? true
        Fluent.theme = theme

        let nc = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didActivateApplicationNotification, NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification,
        ]
        for name in names {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated { self?.workspaceChanged(note) }
            })
        }
        lastActivePID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        refresh()
        // Windows open and close without any workspace notification, so poll for them.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    private func workspaceChanged(_ note: Notification) {
        if note.name == NSWorkspace.didActivateApplicationNotification,
           let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
           app.processIdentifier != getpid() {
            lastActivePID = app.processIdentifier
            // Hiding everything activates Finder: ignore activations caused by the toggle itself.
            if !hiddenForDesktop.isEmpty, Date().timeIntervalSince(desktopToggledAt) > 1.5 { hiddenForDesktop = [] }
        }
        refresh()
    }

    // MARK: Items

    static func key(for app: NSRunningApplication) -> String {
        app.bundleIdentifier ?? app.bundleURL?.path ?? "pid:\(app.processIdentifier)"
    }

    func refresh() {
        let ws = NSWorkspace.shared
        let running = ws.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != getpid() && !$0.isTerminated
        }
        let front = ws.frontmostApplication?.processIdentifier
        let activePID = (front == getpid() || front == nil) ? lastActivePID : front

        var result: [TaskItem] = []
        var used = Set<pid_t>()
        for id in pinnedIDs {
            let app = running.first { Self.key(for: $0) == id }
            if let app { used.insert(app.processIdentifier) }
            let url = app?.bundleURL ?? ws.urlForApplication(withBundleIdentifier: id)
                ?? (id.hasPrefix("/") ? URL(fileURLWithPath: id) : nil)
            guard let url, FileManager.default.fileExists(atPath: url.path) else { continue }
            result.append(makeItem(id: id, url: url, app: app, pinned: true, activePID: activePID))
        }
        // Like Windows, an app that is not pinned only has a button while it has windows.
        for app in running where !used.contains(app.processIdentifier) && WindowService.hasWindows(app) {
            result.append(makeItem(id: Self.key(for: app), url: app.bundleURL, app: app, pinned: false, activePID: activePID))
        }
        if result != items { items = result }
    }

    private func makeItem(id: String, url: URL?, app: NSRunningApplication?, pinned: Bool, activePID: pid_t?) -> TaskItem {
        let icon: NSImage
        if let cached = iconCache[id] {
            icon = cached
        } else {
            icon = app?.icon ?? url.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSImage()
            iconCache[id] = icon
        }
        let name = app?.localizedName ?? url.map { Self.displayName($0) } ?? id
        let active = app != nil && app?.processIdentifier == activePID && app?.isHidden == false
        let windows = app.map { pinned ? WindowService.hasWindows($0) : true } ?? false
        return TaskItem(id: id, name: name, icon: icon, url: url, app: app, pinned: pinned, isActive: active, hasWindows: windows)
    }

    nonisolated static func displayName(_ url: URL) -> String {
        let n = FileManager.default.displayName(atPath: url.path)
        return n.hasSuffix(".app") ? String(n.dropLast(4)) : n
    }

    // MARK: Pinning

    func setPinned(_ item: TaskItem, _ pinned: Bool) {
        pinnedIDs.removeAll { $0 == item.id }
        if pinned { pinnedIDs.append(item.id) }
        UserDefaults.standard.set(pinnedIDs, forKey: "pinned")
        refresh()
    }

    func pinToBar(_ entry: AppEntry) {
        let id = entry.bundleID ?? entry.url.path
        guard !pinnedIDs.contains(id) else { return }
        pinnedIDs.append(id)
        UserDefaults.standard.set(pinnedIDs, forKey: "pinned")
        refresh()
    }

    /// Pins anything dropped on the bar: an app (by bundle id when it has one), a folder or a file (by path).
    func pin(_ url: URL) {
        let url = url.standardizedFileURL
        let id = url.pathExtension == "app" ? (Bundle(url: url)?.bundleIdentifier ?? url.path) : url.path
        guard !pinnedIDs.contains(id) else { return }
        pinnedIDs.append(id)
        UserDefaults.standard.set(pinnedIDs, forKey: "pinned")
        refresh()
    }

    func isPinnedToBar(_ entry: AppEntry) -> Bool { pinnedIDs.contains(entry.bundleID ?? entry.url.path) }

    // MARK: Actions

    /// Windows-like click: launch if not running, minimise (hide) if already in front, otherwise bring to front.
    func click(_ item: TaskItem) {
        guard let app = item.app, !app.isTerminated else {
            if let url = item.url { Self.launch(url) }
            return
        }
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        if front == app.processIdentifier && !app.isHidden {
            app.hide()
        } else {
            if app.isHidden { app.unhide() }
            WindowService.activate(app)
        }
    }

    nonisolated static func launch(_ url: URL) {
        guard url.pathExtension == "app" else {
            // Pinned folders and documents open in their default app (folders in Finder).
            NSWorkspace.shared.open(url)
            return
        }
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: cfg)
    }

    /// "Show desktop": hide every app, a second click brings them back.
    func toggleDesktop() {
        desktopToggledAt = Date()
        if !hiddenForDesktop.isEmpty {
            let apps = hiddenForDesktop
            hiddenForDesktop = []
            apps.filter { !$0.isTerminated }.forEach { $0.unhide() }
            return
        }
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !$0.isHidden && $0.processIdentifier != getpid()
        }
        apps.forEach { $0.hide() }
        hiddenForDesktop = apps
    }

    func activate(index: Int) {
        guard items.indices.contains(index) else { return }
        click(items[index])
    }
}
