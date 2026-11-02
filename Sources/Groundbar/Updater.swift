import AppKit

/// Checks GitHub for a newer release: at launch, then once a day. It only tells the user;
/// nothing is downloaded or installed automatically.
@MainActor
final class Updater: ObservableObject {
    struct Release: Equatable {
        let version: String
        let url: URL
    }

    enum Status: Equatable {
        case idle, checking, upToDate, available(Release), failed
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var lastCheck: Date?
    @Published var automatic: Bool {
        didSet {
            UserDefaults.standard.set(automatic, forKey: Self.automaticKey)
            if automatic { checkIfDue() }
        }
    }

    static let releasesPage = URL(string: "https://github.com/umb-maker/Groundbar/releases")!
    private static let latestAPI = URL(string: "https://api.github.com/repos/umb-maker/Groundbar/releases/latest")!
    private static let automaticKey = "checkForUpdates"
    private static let lastCheckKey = "lastUpdateCheck"
    private static let notifiedKey = "notifiedVersion"
    private var timer: Timer?

    /// The running version, from the bundle ("dev" for `swift run` builds).
    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    init() {
        let d = UserDefaults.standard
        automatic = d.object(forKey: Self.automaticKey) as? Bool ?? true
        lastCheck = d.object(forKey: Self.lastCheckKey) as? Date
        // A short delay keeps start-up quiet; afterwards look again every few hours whether a day has passed.
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in self?.checkIfDue() }
        timer = Timer.scheduledTimer(withTimeInterval: 4 * 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkIfDue() }
        }
    }

    private func checkIfDue() {
        guard automatic, Self.currentVersion != "dev" else { return }
        if let lastCheck, Date().timeIntervalSince(lastCheck) < 20 * 3600 { return }
        check(userInitiated: false)
    }

    /// Asks GitHub for the latest release. A user-initiated check always reports its result in Settings;
    /// an automatic one shows a notice above the bar only once per new version.
    func check(userInitiated: Bool = true) {
        guard status != .checking else { return }
        status = .checking
        Task { @MainActor in
            var request = URLRequest(url: Self.latestAPI, timeoutInterval: 15)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else {
                status = .failed
                return
            }
            let now = Date()
            lastCheck = now
            UserDefaults.standard.set(now, forKey: Self.lastCheckKey)
            let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            let url = (json["html_url"] as? String).flatMap(URL.init(string:)) ?? Self.releasesPage
            guard Self.isNewer(version, than: Self.currentVersion) else {
                status = .upToDate
                return
            }
            let release = Release(version: version, url: url)
            status = .available(release)
            if userInitiated || UserDefaults.standard.string(forKey: Self.notifiedKey) != version {
                UserDefaults.standard.set(version, forKey: Self.notifiedKey)
                if !userInitiated { notify(release) }
            }
        }
    }

    private func notify(_ release: Release) {
        TaskbarController.shared.showToast(title: L("Groundbar \(release.version) is available"),
                                           detail: L("Click to open the download page"),
                                           symbol: "arrow.down.circle") {
            NSWorkspace.shared.open(release.url)
        }
    }

    /// Compares dotted version numbers ("0.10.1" > "0.9.3"); non-numeric parts count as 0.
    nonisolated static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }
        let y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }
}
