# OmniBar

**English** · [Italiano](README.it.md)

A Windows-style taskbar for macOS: a bottom bar with a Start menu, a list of each app's open documents, recent files, a Bitcoin widget and themes. Native Swift/SwiftUI + AppKit, public APIs only, no third-party dependencies.

![OmniBar, dark theme](docs/images/bar-dark.png)
![OmniBar, Halloween theme](docs/images/bar-halloween.png)

> **Note:** the user interface is currently in Italian. An English localisation is planned.

## Features

- **Start menu**: pinned apps, *Recommended* recent files, *All apps*, and search across apps **and files** (Return opens, ↑↓ to select), plus a power menu.
- **Pinned and running apps** in one bar, with an active-app indicator. Apps that aren't pinned only show up while they have open windows.
- **Per-app document list**: hover or click an icon to see every open document of that app, minimised ones included. Click one to bring it to the front, or close it with ✕.
- **Recent documents** (jump lists) in each app's right-click menu, e.g. Word, Excel or a PDF reader.
- **Pin folders and files** by dragging them onto the bar.
- **Screenshots** of a region or of the whole screen, saved to disk and copied to the clipboard.
- **Bitcoin widget**: price in euro, 24-hour change and sparkline. Click it for a chart from 24 hours to 1 year (data from CoinGecko).
- **Quick settings**: network, volume, battery, theme.
- **Show desktop** strip on the right edge.
- **Themes**: System, Light, Dark and **Halloween** 🎃.
- **Global shortcuts**: ⌃⌥1…9 opens the n-th app, ⌃⌥Space opens Start, ⌃⌥D shows the desktop.
- **Launch at login**, from the bar's right-click menu.

| Document list | Bitcoin | Quick settings |
|---|---|---|
| ![](docs/images/window-list.png) | ![](docs/images/btc.png) | ![](docs/images/quick-settings.png) |

## Requirements

macOS 14 (Sonoma) or later, on Apple silicon or Intel.

## Installation

### From a release
1. Download `OmniBar.zip` from [Releases](../../releases), unzip it and move `OmniBar.app` to **Applications**.
2. The app isn't notarised by Apple, so macOS blocks it on first launch. Open **System Settings › Privacy & Security** and click **Open Anyway**.

### From source
Apple's Command Line Tools are enough (`xcode-select --install`); Xcode is not required.

```sh
./scripts/bundle.sh            # builds build/OmniBar.app
./scripts/bundle.sh universal  # Apple silicon + Intel
open build/OmniBar.app
```

## Permissions

Grant them in **System Settings › Privacy & Security**.

| Permission | What it's for |
|---|---|
| **Accessibility** | Listing open windows and documents, bringing them to the front, restoring and closing them |
| **Screen Recording** | Window titles and screenshots |
| **Automation › System Events** | Sleep, Restart, Shut Down and Log Out from the Start menu (asked on first use) |

With ad-hoc signing, macOS may ask for the permissions again after every rebuild. To avoid that, sign with a stable identity: set `OMNIBAR_SIGN_IDENTITY`, or create `scripts/signing.local` containing `OMNIBAR_SIGN_IDENTITY="Your identity"`.

## Known limitations

- macOS doesn't let an app reserve space at the edge of the screen, so maximised windows can extend under the bar. Hiding the Dock automatically helps (right-click the bar › *Nascondi automaticamente il Dock*).
- Tabs inside one window (e.g. several PDFs in tabs) appear as a single document.
- Only windows on the current Space are listed.
- Other apps' menu bar icons don't appear in the tray.
- The bar is shown on the main display only.

## Development

- `.build/debug/OmniBar --snapshot <folder>` saves PNGs of the bar and its panels, then quits.
- Diagnostic logs go to `~/Library/Logs/OmniBar.log`.
- `scripts/social-preview.swift` renders the repository's social preview image.
- Only public macOS APIs are used: NSWorkspace, Accessibility, ScreenCaptureKit, Spotlight (NSMetadataQuery), CoreAudio, IOKit, Carbon (global hotkeys) and ServiceManagement.

OmniBar is inspired by taskbars such as uBar and the Windows 11 taskbar, but contains none of their code.

## License

[MIT](LICENSE) © 2026 csvnm
