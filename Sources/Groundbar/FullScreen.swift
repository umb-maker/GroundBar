import AppKit

/// Reports which displays the frontmost app fills, so their bars can step aside. Native full screen
/// already lives in its own Space (where the bar isn't shown); this also covers apps that just make a
/// screen-sized window, like a video in a browser.
@MainActor
final class FullScreenWatcher {
    /// Called on the main thread after every check with the displays the front app fills, and the
    /// displays where one of its windows reaches under the bar.
    private let onChange: (_ covered: Set<CGDirectDisplayID>, _ underBar: Set<CGDirectDisplayID>) -> Void
    private let barHeight: CGFloat
    private var displays: () -> [CGDirectDisplayID] = { [] }
    private var timer: Timer?
    private var checking = false

    init(barHeight: CGFloat, onChange: @escaping (_ covered: Set<CGDirectDisplayID>, _ underBar: Set<CGDirectDisplayID>) -> Void) {
        self.barHeight = barHeight
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
        let barHeight = barHeight
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let frames = Self.windowFrames(of: front)
            let covered = Self.displaysCovered(by: frames, among: displays)
            let underBar = Self.displaysWithWindowUnderBar(frames, among: displays, barHeight: barHeight)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.checking = false
                    self.onChange(covered, underBar)
                }
            }
        }
    }

    /// The on-screen normal windows of an app, in global coordinates with a top-left origin (the same
    /// space as `CGDisplayBounds`). Safe on any thread.
    nonisolated private static func windowFrames(of pid: pid_t) -> [CGRect] {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.compactMap { w -> CGRect? in
            guard (w[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  (w[kCGWindowLayer as String] as? Int) == 0,
                  let bounds = w[kCGWindowBounds as String] as? NSDictionary else { return nil }
            return CGRect(dictionaryRepresentation: bounds)
        }
    }

    /// Displays filled edge to edge by one of the windows.
    nonisolated private static func displaysCovered(by frames: [CGRect], among displays: [CGDirectDisplayID]) -> Set<CGDirectDisplayID> {
        Set(displays.filter { id in
            let d = CGDisplayBounds(id)
            return frames.contains { r in
                r.minX <= d.minX + 1 && r.minY <= d.minY + 1 && r.maxX >= d.maxX - 1 && r.maxY >= d.maxY - 1
            }
        })
    }

    /// Displays where one of the windows reaches into the strip the bar occupies (more than a sliver).
    nonisolated private static func displaysWithWindowUnderBar(_ frames: [CGRect], among displays: [CGDirectDisplayID],
                                                               barHeight: CGFloat) -> Set<CGDirectDisplayID> {
        Set(displays.filter { id in
            let d = CGDisplayBounds(id)
            let bar = CGRect(x: d.minX, y: d.maxY - barHeight, width: d.width, height: barHeight)
            return frames.contains { r in
                let overlap = r.intersection(bar)
                return !overlap.isNull && overlap.height >= 8 && overlap.width >= 80
            }
        })
    }
}
