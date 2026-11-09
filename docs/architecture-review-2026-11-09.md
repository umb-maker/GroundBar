# Architecture review — 2026-11-09

Check-in after the 0.2–0.4 features (themes, Start menu, previews, updater, settings, multiple displays).
Survey only: no code was changed for this review.

## Survey

- 25 Swift files, 4,249 lines, one executable target (`Groundbar`). No `ARCHITECTURE.md`, ADRs or fix log yet.
- No file passes 600 lines. One type passes 400: `TaskbarController` (421 lines).
- Most-changed files in 30 days (OmniBar and Groundbar paths combined): `TaskbarController` (7), `TaskbarView` (5),
  `StartMenuView` (5), `Snapshot` (5), `TaskbarModel` (4), `Theme` (3), `Flyouts` (3).
- `TaskbarController.shared` is referenced 49 times from 12 files, including the model, views and services.
- No test target is possible with the Command Line Tools alone: neither `XCTest` nor `Testing` is available, so
  `swift test` does not run. Today the only proof of behavior is building, `--snapshot` PNGs and manual checks.
- Demo and snapshot hooks (`Demo.active`, `Snapshot`) live in the app target, with `Demo` checks inside four feature files.
- Accessibility reads still run on the main thread when hovering an icon (`WindowService.windows(of:)`) and for
  the click actions (focus, close, activate). The periodic scan moved off the main thread in 0.4.1.
- No drifted copies (`private struct` names are unique). The global-frame tracking `GeometryReader` is repeated four times.

## Split the taskbar controller by job  [Strong]

Files: `Sources/Groundbar/TaskbarController.swift` (421 lines, 8 `MARK` sections)
Signal: a type over 400 lines; the most-changed file; a hub referenced from 12 files.
Problem: one class owns the per-display bars, full-screen detection, task-button clicks, flyouts and their event
monitors, hover previews and their three timers, the toast, and helpers. Changing preview timing means reading
past full-screen and flyout code, and every feature reaches it through `TaskbarController.shared`.
Proposal: keep `TaskbarController` as the composition root (bars per display, wiring), and move each job into a
deep module of its own file:

```swift
@MainActor final class FlyoutPresenter {          // panels above the bar, outside-click and Escape monitors
    var openKind: String? { get }
    func toggle<V: View>(_ kind: String, anchor: Anchor, on screen: NSScreen, size: CGSize, @ViewBuilder _ content: () -> V)
    func close()
}
@MainActor final class PreviewPresenter {         // hover delay, sticky picker, panel placement
    func hoverBegan(_ item: TaskItem, anchor: CGRect); func hoverEnded(); func showPicker(for item: TaskItem, anchor: CGRect); func hide()
}
@MainActor final class FullScreenWatcher {        // reports which displays the front app fills
    var onChange: (Set<CGDirectDisplayID>) -> Void
    func start(displays: @escaping () -> [CGDirectDisplayID])
}
@MainActor final class ToastPresenter { func show(title: String, detail: String, symbol: String, action: @escaping () -> Void) }
```

Benefits: locality (a preview or full-screen change touches one ~100-line file); the controller shrinks to about
150 lines; each presenter can be driven from `--snapshot` on its own.
Proof of same behavior: golden `--snapshot` PNGs in demo mode (bar, Start, quick settings, Bitcoin, window list,
welcome, every Settings tab) compared byte for byte before and after each step, plus a manual checklist
(hover delay, sticky picker, Escape, outside click, full screen, toast).
Plan: 1) `ToastPresenter` 2) `FullScreenWatcher` 3) `FlyoutPresenter` 4) `PreviewPresenter` — one commit each,
the app builds and the PNGs match after every step.

## Pure logic out of the main-actor stores, with a self-test  [Strong]

Files: `AppCatalog.swift` (search ranking), `FileIndex.swift` (recent-file merge), `Updater.swift` (version
compare), `TaskbarView.swift` (per-display filter), `TaskbarController.swift` (display-cover check),
`TaskbarModel.swift` (regular-app cache, item building)
Signal: a dependency cannot be replaced in a test; pure logic inside `@MainActor` types; no test target possible.
Problem: the rules that decide what the bar shows are only checked by eye. A change to the search ranking or to
the multi-display filter can break silently.
Proposal: a `GroundbarCore` library target with plain functions on plain values, and a `groundbar-selftest`
executable that asserts them (an executable runs with the Command Line Tools, unlike `swift test`):

```swift
public enum AppSearch { public static func rank(_ names: [String], query: String) -> [Int] }
public enum RecentFiles { public static func merge(history: [Entry], spotlight: [Entry], limit: Int) -> [Entry] }
public enum Versions { public static func isNewer(_ a: String, than b: String) -> Bool }
public enum BarFilter { public static func visible(_ items: [Item], display: UInt32, perDisplay: Bool) -> [Int] }
```

Benefits: leverage (each rule tested once, used by every caller); `swift run groundbar-selftest` before every
release; makes the controller split above safer.
Proof of same behavior: write the self-test against today's code first, then move the logic; the same assertions pass.
Plan: 1) add the targets and the self-test with today's functions 2) move one rule per commit.

## One way to read windows  [Worth exploring]

Files: `WindowService.swift` (203 lines), `PreviewView.swift`
Signal: slow work on the main thread.
Problem: the periodic scan reads windows off the main thread, but the hover list (`windows(of:)`) and the click
actions still call Accessibility on it, so a slow app can stall a hover.
Proposal: route every read through `WindowScanner` (async) and run the actions on its queue.
Benefits: hovering stays smooth; one module owns Accessibility.

## Demo data behind a seam  [Worth exploring]

Files: `Snapshot.swift`, plus `Demo.active` checks in `AppCatalog`, `FileIndex`, `TaskbarModel`, `StartMenuView`
Signal: test hooks in the app target.
Problem: feature code branches on `Demo.active`; adding a data source means adding another branch.
Proposal: `AppSource` and `FileSource` protocols with a live adapter and a demo adapter, picked at launch. Two
adapters make it a real seam, which the self-test above can use too.

## A frame-tracking modifier  [Speculative]

Files: `TaskbarView.swift` (3 copies), `Crypto.swift` (1)
Proposal: `.trackGlobalFrame($frame)` instead of four `GeometryReader` blocks. Small, cosmetic.

## Considered, not recommended

- Splitting files under 300 lines by type: they are already one feature each.
- A protocol for the Bitcoin price provider: one provider, no second adapter in sight.
- Moving to a SwiftUI `App` with a `Settings` scene: Groundbar is an agent app built on panels; the change is large
  and gains little now that Settings uses toolbar tabs.

## Top recommendation

**Split the taskbar controller by job.** It is the largest and most-changed type and the hub of the app. Do the
self-test target right after (or first, if you prefer safety over speed): together they make the next features
cheaper to add and safer to change.
