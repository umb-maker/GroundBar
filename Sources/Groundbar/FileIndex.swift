import AppKit

struct FileEntry: Identifiable, Hashable {
    var id: String { url.path }
    let url: URL
    let lastUsed: Date?
    /// Bundle id of the app that opens this file by default (used for per-app recent lists).
    let opener: String?

    var name: String { url.lastPathComponent }
}

/// Recently used files and file-name search, both from the Spotlight index (kMDItemLastUsedDate).
@MainActor
final class FileIndex: ObservableObject {
    @Published private(set) var recent: [FileEntry] = []
    @Published private(set) var searchResults: [FileEntry] = []

    private var recentQuery: NSMetadataQuery?
    private var searchQuery: NSMetadataQuery?
    private var searchDebounce: Timer?
    private var openerByExtension: [String: String] = [:]
    private var icons: [String: NSImage] = [:]
    private var timer: Timer?

    /// Documents seen in app windows (via AXDocument), newest first. Spotlight misses many of them:
    /// apps such as Word do not update kMDItemLastUsedDate, and mail attachments are not indexed.
    private struct HistoryItem: Codable {
        let path: String
        let app: String?
        let date: Date
    }
    private var history: [HistoryItem] = []
    private var spotlight: [FileEntry] = []
    private var openByApp: [pid_t: Set<String>] = [:]

    static let recentLimit = 40
    static let searchLimit = 15
    private static let historyLimit = 100
    private static let historyKey = "recentDocuments"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.historyKey),
           let saved = try? JSONDecoder().decode([HistoryItem].self, from: data) {
            history = saved
        }
        rebuild()
        refreshRecent()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshRecent() }
        }
    }

    // MARK: Recent

    func refreshRecent() {
        guard recentQuery == nil else { return }
        let since = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        let q = makeQuery(NSPredicate(format: "kMDItemLastUsedDate >= %@", since as NSDate))
        recentQuery = q
        observeOnce(q) { [weak self] entries in
            self?.spotlight = entries
            self?.recentQuery = nil
            self?.rebuild()
        }
        q.start()
    }

    /// Records documents that just appeared in an app's windows.
    func observe(app: NSRunningApplication, documents: [URL]) {
        let now = Set(documents.map(\.path))
        let before = openByApp[app.processIdentifier] ?? []
        openByApp[app.processIdentifier] = now
        let opened = now.subtracting(before)
        guard !opened.isEmpty else { return }
        for path in opened {
            history.removeAll { $0.path == path }
            history.insert(HistoryItem(path: path, app: app.bundleIdentifier, date: Date()), at: 0)
        }
        history = Array(history.prefix(Self.historyLimit))
        if let data = try? JSONEncoder().encode(history) { UserDefaults.standard.set(data, forKey: Self.historyKey) }
        rebuild()
    }

    /// Merges the window history with Spotlight's recent files, newest first.
    private func rebuild() {
        if Demo.active { recent = Demo.files; return }
        let fm = FileManager.default
        var seen = Set<String>()
        var merged: [FileEntry] = []
        let fromHistory = history.map { FileEntry(url: URL(fileURLWithPath: $0.path), lastUsed: $0.date, opener: $0.app) }
        for entry in (fromHistory + spotlight).sorted(by: { ($0.lastUsed ?? .distantPast) > ($1.lastUsed ?? .distantPast) }) {
            guard seen.insert(entry.id).inserted, fm.fileExists(atPath: entry.id) else { continue }
            merged.append(entry)
            if merged.count >= Self.recentLimit { break }
        }
        if merged != recent { recent = merged }
    }

    /// The latest documents that open by default in the app with this bundle id.
    func recent(forApp bundleID: String?, limit: Int = 10) -> [FileEntry] {
        guard let bundleID else { return [] }
        return Array(recent.filter { $0.opener == bundleID }.prefix(limit))
    }

    // MARK: Search

    func search(_ text: String) {
        searchDebounce?.invalidate()
        searchQuery?.stop()
        searchQuery = nil
        let term = text.trimmingCharacters(in: .whitespaces)
        guard term.count >= 2 else { searchResults = []; return }
        searchDebounce = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.startSearch(term) }
        }
    }

    private func startSearch(_ term: String) {
        let q = makeQuery(NSPredicate(format: "kMDItemDisplayName LIKE[cd] %@", "*\(term)*"))
        searchQuery = q
        observeOnce(q) { [weak self] entries in
            guard let self, self.searchQuery === q else { return }
            self.searchResults = Array(entries.prefix(Self.searchLimit))
            self.searchQuery = nil
        }
        q.start()
    }

    // MARK: Helpers

    /// Files with content (documents, PDFs, images…), not apps or folders.
    private static let documentsOnly = NSPredicate(format:
        "kMDItemContentTypeTree == 'public.content' AND kMDItemContentType != 'com.apple.application-bundle' AND kMDItemContentType != 'public.folder'")

    private func makeQuery(_ predicate: NSPredicate) -> NSMetadataQuery {
        let q = NSMetadataQuery()
        q.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [predicate, Self.documentsOnly])
        q.searchScopes = [NSMetadataQueryUserHomeScope]
        q.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemLastUsedDateKey, ascending: false)]
        return q
    }

    private func observeOnce(_ q: NSMetadataQuery, _ done: @escaping ([FileEntry]) -> Void) {
        var token: NSObjectProtocol?
        token = NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: q, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                q.stop()
                if let token { NotificationCenter.default.removeObserver(token) }
                done(self?.entries(from: q) ?? [])
            }
        }
    }

    private func entries(from q: NSMetadataQuery) -> [FileEntry] {
        let home = NSHomeDirectory()
        var result: [FileEntry] = []
        for case let item as NSMetadataItem in q.results {
            guard let path = item.value(forAttribute: NSMetadataItemPathKey) as? String,
                  !path.hasPrefix(home + "/Library/"), !path.contains("/."),
                  FileManager.default.fileExists(atPath: path) else { continue }
            let url = URL(fileURLWithPath: path)
            result.append(FileEntry(url: url, lastUsed: item.value(forAttribute: NSMetadataItemLastUsedDateKey) as? Date,
                                    opener: opener(for: url)))
            if result.count >= Self.recentLimit { break }
        }
        return result
    }

    private func opener(for url: URL) -> String? {
        let ext = url.pathExtension.lowercased()
        if let cached = openerByExtension[ext] { return cached }
        let id = NSWorkspace.shared.urlForApplication(toOpen: url).flatMap { Bundle(url: $0)?.bundleIdentifier }
        openerByExtension[ext] = id ?? ""
        return id
    }

    func icon(_ entry: FileEntry) -> NSImage {
        if let i = icons[entry.id] { return i }
        let i = PreviewModel.fileIcon(entry.url)
        icons[entry.id] = i
        return i
    }

    static func open(_ entry: FileEntry) {
        NSWorkspace.shared.open(entry.url)
    }

    static func relative(_ date: Date?) -> String {
        guard let date else { return "" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f.localizedString(for: date, relativeTo: Date())
    }
}
