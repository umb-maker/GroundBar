import AppKit

/// Checks GitHub for a newer release: at launch, then once a day, and tells the user. The update is
/// installed only when the user asks for it (the notice or Settings).
@MainActor
final class Updater: ObservableObject {
    struct Release: Equatable {
        let version: String
        let url: URL
        /// `Groundbar.zip` and the SHA-256 GitHub computed for it; without both, updating opens `url`.
        var asset: URL? = nil
        var sha256: String? = nil
    }

    enum Status: Equatable {
        case idle, checking, upToDate, available(Release), installing, failed
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
        lastCheck = Demo.active ? nil : d.object(forKey: Self.lastCheckKey) as? Date
        guard !Demo.active else { return }
        // A short delay keeps start-up quiet; afterwards look again every few hours whether a day has passed.
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in self?.checkIfDue() }
        timer = Timer.scheduledTimer(withTimeInterval: 4 * 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkIfDue() }
        }
        timer?.tolerance = 600
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
            let url = (json["html_url"] as? String).flatMap(URL.init(string:)).flatMap { Self.isReleaseLink($0) ? $0 : nil } ?? Self.releasesPage
            guard Self.isNewer(version, than: Self.currentVersion) else {
                status = .upToDate
                return
            }
            let zip = (json["assets"] as? [[String: Any]])?.first { $0["name"] as? String == "Groundbar.zip" }
            let asset = (zip?["browser_download_url"] as? String).flatMap(URL.init(string:)).flatMap { Self.isReleaseLink($0) ? $0 : nil }
            let digest = (zip?["digest"] as? String).flatMap { $0.hasPrefix("sha256:") ? String($0.dropFirst(7)) : nil }
            let release = Release(version: version, url: url, asset: asset, sha256: digest)
            status = .available(release)
            if userInitiated || UserDefaults.standard.string(forKey: Self.notifiedKey) != version {
                UserDefaults.standard.set(version, forKey: Self.notifiedKey)
                if !userInitiated { notify(release) }
            }
        }
    }

    private func notify(_ release: Release) {
        TaskbarController.shared.toast.show(title: L("Groundbar \(release.version) is available"),
                                           detail: L("Click to update and restart"),
                                           symbol: "arrow.down.circle") { [weak self] in
            self?.install(release)
        }
    }

    /// Downloads, checks and installs `release`, then relaunches. Opens the release page instead when
    /// the running copy can't be replaced, and after any failure.
    func install(_ release: Release) {
        Log.write("update: install \(release.version) requested")
        guard status != .installing else { return }
        guard let asset = release.asset, let sha256 = release.sha256, UpdateInstaller.canReplace else {
            Log.write("update: opening the release page (asset \(release.asset != nil), digest \(release.sha256 != nil), replaceable \(UpdateInstaller.canReplace))")
            NSWorkspace.shared.open(release.url)
            return
        }
        status = .installing
        let bundleID = Bundle.main.bundleIdentifier ?? ""
        Task { @MainActor in
            do {
                let app = try await Task.detached {
                    try await UpdateInstaller.prepare(asset: asset, sha256: sha256, version: release.version, bundleID: bundleID)
                }.value
                try UpdateInstaller.replaceAndRelaunch(with: app)
            } catch {
                Log.write("update to \(release.version) failed: \(error)")
                status = .available(release)
                TaskbarController.shared.toast.show(title: L("Couldn't install the update"),
                                                   detail: L("Click to open the download page"),
                                                   symbol: "exclamationmark.triangle") {
                    NSWorkspace.shared.open(release.url)
                }
            }
        }
    }

    /// Only a page of Groundbar's own repository on github.com, over HTTPS, is opened from an update notice.
    nonisolated static func isReleaseLink(_ url: URL) -> Bool {
        // GitHub owner and repository names ignore case (the API now answers with "GroundBar").
        url.scheme == "https" && url.host == "github.com" && url.path.lowercased().hasPrefix("/umb-maker/groundbar/")
            && url.user == nil && url.port == nil
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
