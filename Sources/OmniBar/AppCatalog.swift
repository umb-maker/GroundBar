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
    @Published private(set) var apps: [AppEntry] = []
    private var icons: [String: NSImage] = [:]

    nonisolated private static let roots: [String] = [
        "/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities",
        NSHomeDirectory() + "/Applications",
    ]

    func reload() {
        Task.detached(priority: .utility) {
            let list = Self.scan()
            await MainActor.run { self.apps = list }
        }
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
