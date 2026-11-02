import AppKit

struct AppEntry: Identifiable, Hashable {
    var id: String { url.path }
    let name: String
    let url: URL
    let bundleID: String?
}

/// Installed applications, for the Start menu and its search.
@MainActor
final class AppCatalog: ObservableObject {
    @Published private(set) var apps: [AppEntry] = [] {
        didSet { rebuildRecent() }
    }
    /// Recently used apps, newest first, for the Start menu.
    @Published private(set) var recentApps: [AppEntry] = []
    private var icons: [String: NSImage] = [:]

    /// Bundle ids (or paths) of apps brought to the front in OmniBar, newest first.
    private var used: [String]
    /// Apps Spotlight saw launched in the last 30 days, to fill the list before OmniBar has its own history.
    private var spotlight: [String] = []
    private var spotlightQuery: NSMetadataQuery?
    private var observer: NSObjectProtocol?

    static let recentLimit = 18
    private static let usedKey = "recentApps"

    nonisolated private static let roots: [String] = [
        "/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities",
        NSHomeDirectory() + "/Applications",
    ]

    init() {
        used = UserDefaults.standard.stringArray(forKey: Self.usedKey) ?? []
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            MainActor.assumeIsolated { self?.noteUsed(app) }
        }
        loadSpotlight()
    }

    func reload() {
        Task.detached(priority: .utility) {
            let list = Self.scan()
            await MainActor.run { self.apps = list }
        }
    }

    // MARK: Recent apps

    private func noteUsed(_ app: NSRunningApplication) {
        guard app.activationPolicy == .regular, app.processIdentifier != getpid(),
              let id = app.bundleIdentifier ?? app.bundleURL?.path, used.first != id else { return }
        used.removeAll { $0 == id }
        used.insert(id, at: 0)
        used = Array(used.prefix(50))
        UserDefaults.standard.set(used, forKey: Self.usedKey)
        rebuildRecent()
    }

    private func loadSpotlight() {
        let since = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        let q = NSMetadataQuery()
        q.predicate = NSPredicate(format: "kMDItemContentType == 'com.apple.application-bundle' AND kMDItemLastUsedDate >= %@", since as NSDate)
        q.searchScopes = [NSMetadataQueryLocalComputerScope]
        q.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemLastUsedDateKey, ascending: false)]
        var token: NSObjectProtocol?
        token = NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: q, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                q.stop()
                if let token { NotificationCenter.default.removeObserver(token) }
                self?.spotlight = q.results.compactMap { ($0 as? NSMetadataItem)?.value(forAttribute: "kMDItemCFBundleIdentifier") as? String }
                self?.spotlightQuery = nil
                self?.rebuildRecent()
            }
        }
        spotlightQuery = q
        q.start()
    }

    private func rebuildRecent() {
        let own = Bundle.main.bundleIdentifier
        var seen = Set<String>()
        var list: [AppEntry] = []
        for id in used + spotlight where id != own {
            guard let entry = entry(forID: id), seen.insert(entry.id).inserted else { continue }
            list.append(entry)
            if list.count >= Self.recentLimit { break }
        }
        if list != recentApps { recentApps = list }
    }

    nonisolated static func scan() -> [AppEntry] {
        let fm = FileManager.default
        var seen = Set<String>()
        var result: [AppEntry] = []

        func add(_ url: URL) {
            let url = url.standardizedFileURL
            guard url.pathExtension == "app", !url.lastPathComponent.hasPrefix("."), seen.insert(url.path).inserted else { return }
            let bundle = Bundle(url: url.resolvingSymlinksInPath())
            if bundle?.object(forInfoDictionaryKey: "LSUIElement") as? Bool == true { return }
            let name = (bundle?.localizedInfoDictionary?["CFBundleDisplayName"] as? String)
                ?? TaskbarModel.displayName(url)
            result.append(AppEntry(name: name, url: url, bundleID: bundle?.bundleIdentifier))
        }

        for root in roots {
            let rootURL = URL(fileURLWithPath: root)
            guard let children = try? fm.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil, options: []) else { continue }
            for child in children {
                if child.pathExtension == "app" {
                    add(child)
                } else if !child.lastPathComponent.hasPrefix("."), let nested = try? fm.contentsOfDirectory(at: child, includingPropertiesForKeys: nil, options: []) {
                    nested.filter { $0.pathExtension == "app" }.forEach(add)
                }
            }
        }
        add(URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"))
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func icon(_ entry: AppEntry) -> NSImage {
        if let i = icons[entry.id] { return i }
        let i = NSWorkspace.shared.icon(forFile: entry.url.resolvingSymlinksInPath().path)
        icons[entry.id] = i
        return i
    }

    func entry(forID id: String) -> AppEntry? {
        apps.first { $0.bundleID == id || $0.url.path == id }
    }

    /// Prefix matches first, then word-prefix matches, then substring matches.
    func search(_ query: String) -> [AppEntry] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        func rank(_ e: AppEntry) -> Int? {
            let n = e.name.lowercased()
            if n.hasPrefix(q) { return 0 }
            if n.split(whereSeparator: { $0 == " " || $0 == "-" }).contains(where: { $0.hasPrefix(q) }) { return 1 }
            if n.contains(q) { return 2 }
            return nil
        }
        var ranked: [(entry: AppEntry, rank: Int)] = []
        for e in apps { if let r = rank(e) { ranked.append((e, r)) } }
        ranked.sort { a, b in a.rank != b.rank ? a.rank < b.rank : a.entry.name.count < b.entry.name.count }
        return ranked.map { $0.entry }
    }
}
