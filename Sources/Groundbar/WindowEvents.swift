import AppKit
import ApplicationServices

/// Tells when an app opens, closes, minimises, moves or resizes a window, so the bar rescans then
/// instead of asking every app for its windows every second and a half. Asking wakes each app up, so
/// polling cost energy in every running app, not only in Groundbar. A slow poll in `TaskbarModel`
/// still catches what no notification reports (a window moved to another Space).
@MainActor
final class WindowEvents {
    private let onEvent: () -> Void
    private var observers: [pid_t: AXObserver] = [:]
    private var pending = false

    /// `onEvent` runs on the main thread, at most once per burst of notifications.
    init(onEvent: @escaping () -> Void) {
        self.onEvent = onEvent
    }

    /// Observes exactly these processes: new ones are added, ended ones dropped.
    func watch(_ pids: [pid_t]) {
        let wanted = Set(pids)
        for pid in observers.keys where !wanted.contains(pid) { stop(pid) }
        for pid in wanted where observers[pid] == nil { start(pid) }
    }

    private static let notifications = [
        kAXWindowCreatedNotification, kAXUIElementDestroyedNotification, kAXWindowMiniaturizedNotification,
        kAXWindowDeminiaturizedNotification, kAXWindowMovedNotification, kAXWindowResizedNotification,
        kAXFocusedWindowChangedNotification,
    ]

    private func start(_ pid: pid_t) {
        var observer: AXObserver?
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            let events = Unmanaged<WindowEvents>.fromOpaque(refcon).takeUnretainedValue()
            MainActor.assumeIsolated { events.received() }
        }
        guard AXObserverCreate(pid, callback, &observer) == .success, let observer else { return }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        // Registered on the app, these arrive for all its windows; a window closing also moves the focus.
        for name in Self.notifications { AXObserverAddNotification(observer, app, name as CFString, refcon) }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        observers[pid] = observer
    }

    private func stop(_ pid: pid_t) {
        guard let observer = observers.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }

    /// Coalesces a burst (a window dragged sends dozens of moves) into one call.
    private func received() {
        guard !pending else { return }
        pending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            MainActor.assumeIsolated {
                self?.pending = false
                self?.onEvent()
            }
        }
    }
}
