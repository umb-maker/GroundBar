# Groundbar

**English** · [Italiano](README.it.md)

A Windows-style taskbar for macOS: a bottom bar with a Start menu of recent apps, a list of each app's open documents, recent files, a Bitcoin widget and themes. Native Swift/SwiftUI + AppKit, public APIs only, no third-party dependencies.

![Groundbar demo: Start menu, document list, Bitcoin widget, seasonal themes](docs/images/demo.gif)

Available in **English** and **Italian**: Groundbar follows the language set in macOS.

*Groundbar was called OmniBar up to version 0.2.0.*

## Features

- **Start menu**: recently used apps, *Recommended* recent files, *All apps*, and search across apps **and files** (Return opens, ↑↓ to select), plus a power menu.
- **Pinned and running apps** in one bar, with an active-app indicator. Apps that aren't pinned only show up while they have open windows.
- **Per-app document list**: hover or click an icon to see every open document of that app, minimised ones included. Click one to bring it to the front, or close it with ✕.
- **Recent documents** (jump lists) in each app's right-click menu, e.g. Word, Excel or a PDF reader.
- **Pin folders and files** by dragging them onto the bar.
- **Screenshots** of a region or of the whole screen, saved to disk and copied to the clipboard.
- **Bitcoin widget**: price in euro, 24-hour change and sparkline. Click it for a chart from 24 hours to 1 year (data from CoinGecko).
- **Quick settings**: network, volume, battery, theme.
- **Show desktop** strip on the right edge.
- **Themes**: System, Light, Dark, **Halloween** 🎃, **Christmas** 🎄 (falling snow, twinkling lights) and **Santa** 🎅 (a night sky with Santa's sleigh flying across the bar).
- **Global shortcuts**: ⌃⌥1…9 opens the n-th app, ⌃⌥Space opens Start, ⌃⌥D shows the desktop.
- **Launch at login**, from the bar's right-click menu.
- **Settings window**: theme, icon layout, Bitcoin widget and currency (EUR/USD), screenshot buttons, shortcuts, updates.
- **Update notices**: Groundbar checks GitHub once a day and tells you when a new version is out (it never installs anything by itself).

| Document list | Bitcoin | Quick settings |
|---|---|---|
| ![](docs/images/window-list.png) | ![](docs/images/btc.png) | ![](docs/images/quick-settings.png) |

## Requirements

macOS 14 (Sonoma) or later, on Apple silicon or Intel.

## Installation

### From a release
1. Download `Groundbar.zip` from [Releases](../../releases), unzip it and move `Groundbar.app` to **Applications**.
2. The app isn't notarised by Apple, so macOS blocks it on first launch. Open **System Settings › Privacy & Security** and click **Open Anyway**.

### From source
Apple's Command Line Tools are enough (`xcode-select --install`); Xcode is not required.

```sh
./scripts/bundle.sh            # builds build/Groundbar.app
./scripts/bundle.sh universal  # Apple silicon + Intel
open build/Groundbar.app
```

## Permissions

On first launch, a welcome window explains each permission, opens the right settings pane and shows when it is granted. Reopen it any time from the bar's right-click menu › *Setup & Permissions…*. The permissions live in **System Settings › Privacy & Security**.

| Permission | What it's for |
|---|---|
| **Accessibility** | Listing open windows and documents, bringing them to the front, restoring and closing them |
| **Screen Recording** | Window titles and screenshots |
| **Automation › System Events** | Sleep, Restart, Shut Down and Log Out from the Start menu (asked on first use) |

With ad-hoc signing, macOS may ask for the permissions again after every rebuild. To avoid that, sign with a stable identity: set `GROUNDBAR_SIGN_IDENTITY`, or create `scripts/signing.local` containing `GROUNDBAR_SIGN_IDENTITY="Your identity"`.

## Privacy & security

- **No telemetry, no accounts.** Groundbar makes two kinds of network request, both over HTTPS and carrying no information about you: the public CoinGecko API for the Bitcoin price (off if you hide the widget), and GitHub's public API once a day to check for a new release (off in Settings › Updates).
- **Permissions are used locally only.** Accessibility lists, raises and closes windows and reads which document each window shows; Screen Recording provides window titles and screenshots. Nothing leaves your Mac.
- **What Groundbar stores on your Mac:**
  - settings and the lists of recent apps and recent documents (file paths), in `~/Library/Preferences/app.groundbar.Groundbar.plist`;
  - screenshots, in the folder macOS uses for screenshots;
  - a small diagnostic log, `~/Library/Logs/Groundbar.log`: start-up and errors only, never window titles or file names, capped at 1 MB.
- **Commands it runs:** `screencapture` for screenshots, `pmset displaysleepnow` to lock the screen, System Events for Sleep, Restart, Shut Down and Log Out, and `defaults write com.apple.dock autohide` + `killall Dock` only when you choose *Automatically Hide the Dock*.
- **No third-party dependencies**, and the source code is open.
- **Verify your download.** The app is not notarised by Apple, so each release lists the SHA-256 checksum of `Groundbar.zip`. Compare it with `shasum -a 256 Groundbar.zip`.
- **Remove everything:** quit Groundbar, delete the app, then run `defaults delete app.groundbar.Groundbar` and delete `~/Library/Logs/Groundbar*.log`.

## Known limitations

- macOS doesn't let an app reserve space at the edge of the screen, so maximised windows can extend under the bar. Hiding the Dock automatically helps (right-click the bar › *Automatically Hide the Dock*).
- Tabs inside one window (e.g. several PDFs in tabs) appear as a single document.
- Only windows on the current Space are listed.
- Other apps' menu bar icons don't appear in the tray.
- The bar is shown on the main display only.
- To read the windows of some apps (e.g. Microsoft Office), Groundbar turns on their accessibility interface; in rare cases this can slow down window animations in those apps.

## Development

- `.build/debug/Groundbar --snapshot <folder>` saves PNGs of the bar and its panels, then quits. `GROUNDBAR_DEMO=1` swaps in sample apps and files, `GROUNDBAR_SNAPSHOT_STEPS=bar,start` limits the steps.
- `scripts/demo-gif.swift` builds the README demo GIF from those renders.
- `scripts/social-preview.swift` renders the repository's social preview image; `scripts/app-icon.swift` renders the app icon (then build `Resources/AppIcon.icns` with `sips` and `iconutil`).
- Only public macOS APIs are used: NSWorkspace, Accessibility, ScreenCaptureKit, Spotlight (NSMetadataQuery), CoreAudio, IOKit, Carbon (global hotkeys) and ServiceManagement.

## License

[MIT](LICENSE) © 2026 csvnm
