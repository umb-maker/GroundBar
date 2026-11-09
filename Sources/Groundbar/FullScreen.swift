import AppKit

/// Reports which displays the frontmost app fills, so their bars can step aside. Native full screen
/// already lives in its own Space (where the bar isn't shown); this also covers apps that just make a
/// screen-sized window, like a video in a browser.
@MainActor
final class FullScreenWatcher {
    /// Called on the main thread with the displays the front app covers, after every check.
    private let onChange: (Set<CGDirectDisplayID>) -> Void
    private var displays: () -> [CGDirectDisplayID] = { [] }
    private var timer: Timer?
    private var checking = false

    init(onChange: @escaping (Set<CGDirectDisplayID>) -> Void) {
        self.onChange = onChange
    }

    /// Checks when the Space or the front app changes, and once a second. `displays` lists the displays
    /// that have a bar, read at each check.
    func start(displays: @escaping () -> [CGDirectDisplayID]) {
        self.displays = displays
        let nc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    MainActor.assumeIsolated { self?.check() }
                }
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        timer?.tolerance = 0.3
    }

    /// Reads the window list off the main thread, then reports.
    private func check() {
        guard !checking, !Snapshot.running else { return }
        // Groundbar itself in front (a flyout or Settings): keep the bars as they are.
        guard let front = NSWorkspace.shared.frontmostApplication?.processIdentifier, front != getpid() else { return }
        checking = true
        let displays = displays()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let covered = Self.displaysCovered(by: front, among: displays)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.checking = false
                    self.onChange(covered)
                }
            }
        }
    }

    /// Displays filled by an on-screen window of the given app (window bounds and display bounds are
    /// both in global coordinates with a top-left origin). Safe on any thread.
    nonisolated private static func displaysCovered(by pid: pid_t, among displays: [CGDirectDisplayID]) -> Set<CGDirectDisplayID> {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let frames = windows.compactMap { w -> CGRect? in
            guard (w[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  (w[kCGWindowLayer as String] as? Int) == 0,
                  let bounds = w[kCGWindowBounds as String] as? NSDictionary else { return nil }
            return CGRect(dictionaryRepresentation: bounds)
        }
        return Set(displays.filter { id in
            let d = CGDisplayBounds(id)
            return frames.contains { r in
                r.minX <= d.minX + 1 && r.minY <= d.minY + 1 && r.maxX >= d.maxX - 1 && r.maxY >= d.maxY - 1
            }
        })
    }
}
