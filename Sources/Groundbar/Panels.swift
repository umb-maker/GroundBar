import AppKit

/// The bar itself never takes keyboard focus, so the app you were using stays in front.
final class BarPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Flyouts (Start, calendar, quick settings) take key focus without activating Groundbar.
final class FlyoutPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

extension NSPanel {
    /// The style every Groundbar panel shares: floating above apps on every Space, never over full-screen apps.
    func configureAsGroundbar(appearance: NSAppearance?) {
        isFloatingPanel = true
        level = .statusBar
        backgroundColor = .clear
        isOpaque = false
        hidesOnDeactivate = false
        isMovable = false
        // No .fullScreenAuxiliary: the bar must not be drawn over full-screen apps (videos, presentations).
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        self.appearance = appearance
    }
}
