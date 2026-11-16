import AppKit

/// When the bar steps out of the way (Settings › Taskbar).
enum AutoHideMode: String, CaseIterable, Identifiable {
    /// Always on screen.
    case never
    /// Hidden until the pointer reaches the bottom edge of the screen, like Windows' "automatically hide
    /// the taskbar".
    case always
    /// Hidden only while a window of the front app reaches under it.
    case overlap

    var id: String { rawValue }

    var label: String {
        switch self {
        case .never: L("Never")
        case .always: L("Always")
        case .overlap: L("When a window covers it")
        }
    }
}

/// Decides, per display, whether the bar is tucked away, and brings it back when the pointer touches the
/// bottom edge of the screen. macOS gives a third-party bar no way to reserve screen space the way the
/// Dock does, so a zoomed window reaches under the bar; this is how the bar gets out of its way.
@MainActor
final class BarAutoHider {
    var mode: AutoHideMode {
        didSet {
            guard mode != oldValue else { return }
            revealed.removeAll()
            updateEdgeMonitor()
            onChange()
        }
    }

    private let isBusy: () -> Bool
    private let onChange: () -> Void
    /// Each display's bar, in screen coordinates.
    private var barFrames: [CGDirectDisplayID: NSRect] = [:]
    /// Displays where a window of the front app reaches under the bar.
    private var overlapping = Set<CGDirectDisplayID>()
    /// Displays whose bar the pointer brought back; it stays until the pointer leaves it.
    private var revealed = Set<CGDirectDisplayID>()
    private var edgeMonitors: [Any] = []
    private var leaveTimer: Timer?

    /// `isBusy` is true while something that belongs to the bar is open (a flyout, a window list): the bar
    /// stays. `onChange` runs whenever the answer of `isConcealed` may have changed.
    init(mode: AutoHideMode, isBusy: @escaping () -> Bool, onChange: @escaping () -> Void) {
        self.mode = mode
        self.isBusy = isBusy
        self.onChange = onChange
    }

    /// True while the bar of this display should be out of sight.
    func isConcealed(_ display: CGDirectDisplayID) -> Bool {
        guard !revealed.contains(display) else { return false }
        switch mode {
        case .never: return false
        case .always: return true
        case .overlap: return overlapping.contains(display)
        }
    }

    /// The bars' frames, whenever displays change.
    func layout(barFrames: [CGDirectDisplayID: NSRect]) {
        self.barFrames = barFrames
        revealed.formIntersection(barFrames.keys)
        updateEdgeMonitor()
    }

    /// From the window check: the displays where the front app's window reaches under the bar.
    func setOverlapping(_ displays: Set<CGDirectDisplayID>) {
        guard displays != overlapping else { return }
        overlapping = displays
        if mode == .overlap { onChange() }
    }

    /// Brings the bar of a display back (the pointer at the bottom edge, or a flyout about to open there).
    func reveal(_ display: CGDirectDisplayID) {
        guard mode != .never, barFrames[display] != nil else { return }
        if revealed.insert(display).inserted { onChange() }
        watchPointer()
    }

    // MARK: Pointer

    /// While a bar is revealed, looks twice a second whether the pointer has left it. A tracking area on
    /// the bar would not do: the pointer also leaves the bar to reach a flyout or a window list.
    private func watchPointer() {
        guard leaveTimer == nil else { return }
        leaveTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkPointer() }
        }
        leaveTimer?.tolerance = 0.1
    }

    private func checkPointer() {
        if !isBusy() {
            let mouse = NSEvent.mouseLocation
            let left = revealed.filter { id in
                // A little slack above the bar, so brushing its top edge does not hide it.
                guard let bar = barFrames[id] else { return true }
                return !NSMouseInRect(mouse, bar.insetBy(dx: 0, dy: -6), false)
            }
            if !left.isEmpty {
                revealed.subtract(left)
                onChange()
            }
        }
        if revealed.isEmpty {
            leaveTimer?.invalidate()
            leaveTimer = nil
        }
    }

    // MARK: Bottom edge

    /// Watches pointer movement only while auto-hide is on. Mouse-move monitors need no permission, and
    /// the handler is a single comparison per display.
    private func updateEdgeMonitor() {
        let wanted = mode != .never && !barFrames.isEmpty
        if wanted, edgeMonitors.isEmpty {
            let handler: (NSEvent) -> Void = { [weak self] _ in MainActor.assumeIsolated { self?.pointerMoved() } }
            if let m = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: handler) { edgeMonitors.append(m) }
            if let m = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { handler($0); return $0 }) {
                edgeMonitors.append(m)
            }
        } else if !wanted {
            edgeMonitors.forEach(NSEvent.removeMonitor)
            edgeMonitors = []
        }
    }

    /// The pointer on the last two points of a display brings that display's bar back.
    private func pointerMoved() {
        let mouse = NSEvent.mouseLocation
        for (id, bar) in barFrames where !revealed.contains(id) {
            if mouse.x >= bar.minX, mouse.x < bar.maxX, mouse.y >= bar.minY - 1, mouse.y <= bar.minY + 2 { reveal(id) }
        }
    }
}
