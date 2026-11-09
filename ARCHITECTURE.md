# Architecture

Groundbar is one SwiftPM executable target (`Sources/Groundbar`), an AppKit agent app (`LSUIElement`)
that draws SwiftUI views inside borderless panels. It builds with the Command Line Tools alone.

## Layers

Dependencies point down. Views read stores; presenters own panels; services talk to the system.

| Layer | Files | Job |
| --- | --- | --- |
| App | `main.swift`, `AppDelegate.swift` | Launch, `--snapshot` mode, welcome window |
| Composition root | `TaskbarController.swift` | Owns the stores and presenters, one bar per display, hotkeys, task-button clicks, theme changes |
| Presenters | `FlyoutPresenter.swift`, `PreviewPresenter.swift`, `Toast.swift`, `FullScreen.swift`, `Panels.swift` | Panels above the bar and when they show or hide |
| Views | `TaskbarView`, `StartMenuView`, `Flyouts` (calendar, quick settings), `PreviewView`, `Settings`, `Welcome`, seasonal decor (`Halloween`, `Christmas`, `Santa`, `Decor`) | SwiftUI and Core Animation |
| Stores | `TaskbarModel`, `AppCatalog`, `FileIndex`, `CryptoTicker` (`Crypto.swift`), `SystemStatus`, `Updater`, `PreviewModel` | `ObservableObject`s on the main actor |
| Services | `WindowService` (Accessibility, window scan off the main thread), `ScreenCapture`, `HotKeys`, `Log`, `Theme`, `Localization`, `Assets` | System APIs |
| Debug | `Snapshot.swift` (`--snapshot`, `Demo`) | Repeatable pictures of every surface |

## The presenters

Each presenter owns one kind of panel and everything that decides when it shows. They get the display
to use and the appearance as closures from `TaskbarController`, so they never reach back into it.

- `FlyoutPresenter`: Start, calendar, quick settings and Bitcoin. One at a time; closes on an outside
  click, Escape, or the same toggle again. `flyouts.toggle(kind, anchor:size:content:)`, `flyouts.close()`.
- `PreviewPresenter`: the window list over a task button. Hover delay (0.45 s), hide delay (0.3 s),
  sticky picker on click. Owns `PreviewModel`.
- `ToastPresenter`: the notice above the right end of the bar, six seconds or a click.
- `FullScreenWatcher`: reports which displays the front app fills; the controller hides those bars.

Views and features reach the app through `TaskbarController.shared` (for example
`TaskbarController.shared.flyouts.close()`).

## Threads

Everything UI is `@MainActor`. Accessibility scans (`WindowScanner`), the full-screen window-list check,
system status reads and network requests run off the main thread and report back on it.

## Proving a refactor changed nothing

There is no test target (XCTest and Swift Testing need Xcode). Demo mode (`GROUNDBAR_DEMO=1`) uses fixed
apps, files, prices and dates, and `--snapshot` ignores the mouse and the front app, so the pictures are
the same on every run. Before and after a refactor:

```sh
swift build && scripts/snapshot-hashes.sh /tmp/before > before.txt
swift build && scripts/snapshot-hashes.sh /tmp/after > after.txt && diff before.txt after.txt
```

Snapshots do not cover timing (hover delays, the six-second toast) or event monitors (outside click,
Escape): check those by hand.
