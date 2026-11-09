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
    /// Displays showing the app's windows (empty when unknown, e.g. without Accessibility).
    var displays: Set<CGDirectDisplayID> = []

    var isRunning: Bool { app.map { !$0.isTerminated } ?? false }

    static func == (a: TaskItem, b: TaskItem) -> Bool {
        a.id == b.id && a.app?.processIdentifier == b.app?.processIdentifier
            && a.pinned == b.pinned && a.isActive == b.isActive && a.hasWindows == b.hasWindows && a.displays == b.displays
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
    @Published var barOnAllScreens: Bool {
        didSet { UserDefaults.standard.set(barOnAllScreens, forKey: "barOnAllScreens") }
    }
    /// With a bar on every display, each bar lists the apps whose windows are on that display.
    @Published var appsOnOwnScreen: Bool {
        didSet { UserDefaults.standard.set(appsOnOwnScreen, forKey: "appsOnOwnScreen") }
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
    /// Latest background window scan per process (see `WindowScanner`).
    private var scans: [pid_t: WindowScan] = [:]
    private var scanning = false
    private var policyCache: [pid_t: Bool] = [:]
    private var policyCacheDate = Date.distantPast
    /// Called after each scan with the files shown in each app's windows (feeds the recent-documents history).
    var onDocuments: ((NSRunningApplication, [URL]) -> Void)?

    static let defaultPins = ["com.apple.finder", "com.apple.Safari", "com.apple.mail", "com.apple.iCal", "com.apple.systempreferences"]

    init() {
        let d = UserDefaults.standard
        pinnedIDs = d.stringArray(forKey: "pinned") ?? Self.defaultPins
        theme = ThemeMode(rawValue: d.string(forKey: "theme") ?? "") ?? .system
        centered = d.object(forKey: "centered") as? Bool ?? true
        showCrypto = d.object(forKey: "showCrypto") as? Bool ?? true
        barOnAllScreens = d.object(forKey: "barOnAllScreens") as? Bool ?? true
        appsOnOwnScreen = d.object(forKey: "appsOnOwnScreen") as? Bool ?? true
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
            MainActor.assumeIsolated { self?.scanWindows() }
        }
        pollTimer?.tolerance = 0.3
        scanWindows()
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
        scanWindows()
    }

    /// Reads every running app's windows on a background queue, then refreshes the bar from the results.
    /// Without Accessibility there is nothing to read: every app counts as having windows.
    private func scanWindows() {
        guard AXIsProcessTrusted(), !Demo.active, !scanning else { return }
        scanning = true
        let apps = regularApps()
        WindowScanner.scan(apps.map(\.processIdentifier)) { [weak self] results in
            guard let self else { return }
            self.scanning = false
            self.scans = results
            for app in apps { if let docs = results[app.processIdentifier]?.documents { self.onDocuments?(app, docs) } }
            self.refresh()
        }
    }

    /// Running apps with a Dock presence (activation policy "regular"), other than Groundbar.
    /// `activationPolicy` asks another process each time and there are hundreds of processes, so the
    /// policy is cached per process and re-read every 30 seconds (an app can turn regular after launch).
    private func regularApps() -> [NSRunningApplication] {
        if Date().timeIntervalSince(policyCacheDate) > 30 {
            policyCache = [:]
            policyCacheDate = Date()
        }
        let own = getpid()
        return NSWorkspace.shared.runningApplications.filter { app in
            let pid = app.processIdentifier
            guard pid != own else { return false }
            if let regular = policyCache[pid] { return regular }
            let regular = app.activationPolicy == .regular
            policyCache[pid] = regular
            return regular
        }
    }

    /// Whether the app has a window (minimised included), from the latest scan. Unknown apps (just launched,
    /// or no Accessibility) count as having one, so their button doesn't flicker.
    private func hasWindows(_ app: NSRunningApplication) -> Bool {
        guard AXIsProcessTrusted() else { return true }
        return (scans[app.processIdentifier]?.windowCount ?? 1) > 0
    }

    /// Number of windows from the latest scan (0 when unknown).
    func windowCount(_ app: NSRunningApplication) -> Int { scans[app.processIdentifier]?.windowCount ?? 0 }

    // MARK: Items

    static func key(for app: NSRunningApplication) -> String {
        app.bundleIdentifier ?? app.bundleURL?.path ?? "pid:\(app.processIdentifier)"
    }

    func refresh() {
        let ws = NSWorkspace.shared
        // Demo snapshots show the sample pins only, not what happens to be running.
        let running = Demo.active ? [] : regularApps()
        let front = ws.frontmostApplication?.processIdentifier
        let activePID = (front == getpid() || front == nil) ? lastActivePID : front

        var result: [TaskItem] = []
        var used = Set<pid_t>()
        for id in Demo.active ? Demo.pins : pinnedIDs {
            let app = running.first { Self.key(for: $0) == id }
            if let app { used.insert(app.processIdentifier) }
            let url = app?.bundleURL ?? ws.urlForApplication(withBundleIdentifier: id)
                ?? (id.hasPrefix("/") ? URL(fileURLWithPath: id) : nil)
            guard let url, FileManager.default.fileExists(atPath: url.path) else { continue }
            result.append(makeItem(id: id, url: url, app: app, pinned: true, activePID: activePID))
        }
        // Like Windows, an app that is not pinned only has a button while it has windows.
        for app in running where !Demo.active && !used.contains(app.processIdentifier) && hasWindows(app) {
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
        let windows = app.map { pinned ? hasWindows($0) : true } ?? false
        return TaskItem(id: id, name: name, icon: icon, url: url, app: app, pinned: pinned, isActive: active, hasWindows: windows,
                        displays: app.map { scans[$0.processIdentifier]?.displays ?? [] } ?? [])
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
