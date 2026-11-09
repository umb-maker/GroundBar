import AppKit
import SwiftUI

/// Settings tabs, in Apple's order: General, Appearance, the features, Shortcuts, Permissions, About.
enum SettingsTab: Int, CaseIterable {
    case general, appearance, taskbar, shortcuts, permissions, about

    var title: String {
        switch self {
        case .general: L("General")
        case .appearance: L("Appearance")
        case .taskbar: L("Taskbar")
        case .shortcuts: L("Shortcuts")
        case .permissions: L("Permissions")
        case .about: L("About")
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintpalette"
        case .taskbar: "dock.rectangle"
        case .shortcuts: "keyboard"
        case .permissions: "lock.shield"
        case .about: "info.circle"
        }
    }
}

/// Groundbar's settings window (bar menu › Settings…, or the gear in the Start menu): toolbar tabs like
/// the system's own Settings windows, each tab as tall as its content. Groundbar is an AppKit agent app
/// without a SwiftUI `App`, so this is an `NSTabViewController` instead of a `Settings` scene.
@MainActor
enum SettingsWindow {
    private(set) static var window: NSWindow?
    private static let tabKey = "settingsTab"

    static func show() {
        TaskbarController.shared.closeFlyout()
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let c = TaskbarController.shared
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        for tab in SettingsTab.allCases {
            let host = NSHostingController(rootView: SettingsPage(tab: tab, model: c.model, ticker: c.crypto, updater: c.updater))
            host.sizingOptions = .preferredContentSize  // the window follows each tab's height
            let item = NSTabViewItem(viewController: host)
            item.label = tab.title
            item.image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: tab.title)
            tabs.addTabViewItem(item)
        }
        // Reopen on the tab used last.
        tabs.selectedTabViewItemIndex = min(UserDefaults.standard.integer(forKey: tabKey), SettingsTab.allCases.count - 1)

        let w = NSWindow(contentViewController: tabs)
        w.styleMask = [.titled, .closable]
        w.toolbarStyle = .preference
        w.isReleasedWhenClosed = false
        w.appearance = c.model.theme.appearance
        w.center()
        window = w
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { _ in
            MainActor.assumeIsolated {
                UserDefaults.standard.set(tabs.selectedTabViewItemIndex, forKey: tabKey)
                SettingsWindow.window = nil
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        // Open calm: no focus ring on any control.
        w.makeFirstResponder(nil)
    }

    /// Shows a given tab (used by `--snapshot`).
    static func select(_ tab: SettingsTab) {
        show()
        (window?.contentViewController as? NSTabViewController)?.selectedTabViewItemIndex = tab.rawValue
    }
}

/// One tab: a grouped form, 520 pt wide, as tall as its content.
struct SettingsPage: View {
    let tab: SettingsTab
    @ObservedObject var model: TaskbarModel
    @ObservedObject var ticker: CryptoTicker
    @ObservedObject var updater: Updater

    var body: some View {
        Group {
            switch tab {
            case .general: GeneralSettings()
            case .appearance: AppearanceSettings(model: model)
            case .taskbar: TaskbarSettings(model: model, ticker: ticker)
            case .shortcuts: ShortcutSettings()
            case .permissions: PermissionSettings()
            case .about: AboutSettings(updater: updater)
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
        .frame(width: 520)
        .fitsContent()
    }
}

private struct GeneralSettings: View {
    @Local private var openAtLogin = LoginItem.isEnabled

    var body: some View {
        Form {
            Section {
                Toggle("Open Groundbar at login", isOn: Binding(get: { openAtLogin }, set: { LoginItem.set($0); openAtLogin = LoginItem.isEnabled }))
                    .controlSize(.mini)
            }
            Section {
                LabeledContent("The Dock") {
                    Button("Hide Automatically") { TaskbarController.shared.autoHideDock() }
                }
            } footer: {
                Text("The Dock can cover the bar. This turns on the same option as System Settings › Desktop & Dock.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct AppearanceSettings: View {
    @ObservedObject var model: TaskbarModel

    var body: some View {
        Form {
            Section {
                Picker("Theme", selection: $model.theme) {
                    ForEach(ThemeMode.allCases) { Text($0.label).tag($0) }
                }
            } footer: {
                Text("System follows the Mac's light or dark mode and accent color. Seasonal themes bring their own colors and a light animation.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Section {
                Toggle("Center the icons on the bar", isOn: $model.centered).controlSize(.mini)
            }
        }
    }
}

private struct TaskbarSettings: View {
    @ObservedObject var model: TaskbarModel
    @ObservedObject var ticker: CryptoTicker

    var body: some View {
        Form {
            Section("Displays") {
                Toggle("Show the bar on every display", isOn: $model.barOnAllScreens).controlSize(.mini)
                Toggle("Show each app on the display where its windows are", isOn: $model.appsOnOwnScreen)
                    .controlSize(.mini)
                    .disabled(!model.barOnAllScreens)
            }
            Section {
                Toggle("Show the Bitcoin price", isOn: $model.showCrypto).controlSize(.mini)
                Picker("Currency", selection: $ticker.currency) {
                    Text("Euro (€)").tag("eur")
                    Text("US dollar ($)").tag("usd")
                }
                .pickerStyle(.radioGroup)
                .disabled(!model.showCrypto)
                Toggle("Show the screenshot buttons", isOn: $model.showScreenshotButtons).controlSize(.mini)
            } header: {
                Text("On the bar")
            } footer: {
                Text("Bitcoin prices come from CoinGecko. While the price is hidden, Groundbar sends no requests to CoinGecko.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct ShortcutSettings: View {
    var body: some View {
        Form {
            Section {
                LabeledContent("Open the 1st…9th app on the bar", value: "⌃⌥1 … ⌃⌥9")
                LabeledContent("Open Start", value: L("⌃⌥Space"))
                LabeledContent("Show desktop", value: "⌃⌥D")
            } footer: {
                Text("⌃⌥ stands in for the Windows key: most Mac apps already use ⌘ with a number.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct PermissionSettings: View {
    @StateObject private var permissions = PermissionState()

    var body: some View {
        Form {
            Section {
                row("Accessibility", detail: "Lists your open windows and documents, brings them to the front and closes them.",
                    granted: permissions.accessibility, action: permissions.requestAccessibility)
                row("Screen Recording", detail: "Reads window titles and takes the screenshots you ask for.",
                    granted: permissions.screenRecording, action: permissions.requestScreenRecording)
            } footer: {
                Text("Groundbar uses these permissions only on your Mac.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onDisappear { permissions.stop() }
    }

    private func row(_ title: LocalizedStringKey, detail: LocalizedStringKey, granted: Bool, action: @escaping () -> Void) -> some View {
        LabeledContent {
            if granted {
                Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Button("Open Settings…", action: action)
            }
        } label: {
            Text(title)
            Text(detail)
        }
    }
}

private struct AboutSettings: View {
    @ObservedObject var updater: Updater

    var body: some View {
        Form {
            Section("Updates") {
                Toggle("Check for updates automatically", isOn: $updater.automatic).controlSize(.mini)
                LabeledContent("Version", value: Updater.currentVersion)
                HStack {
                    updateStatus
                    Spacer()
                    Button("Check Now") { updater.check() }
                        .disabled(updater.status == .checking)
                }
            }
            Section("Groundbar") {
                LabeledContent("Source code") {
                    Link("github.com/umb-maker/Groundbar", destination: URL(string: "https://github.com/umb-maker/Groundbar")!)
                }
                LabeledContent("License", value: "MIT")
            }
        }
    }

    @ViewBuilder
    private var updateStatus: some View {
        switch updater.status {
        case .idle:
            if let last = updater.lastCheck {
                Text("Last checked \(last.formatted(date: .abbreviated, time: .shortened))").foregroundStyle(.secondary)
            } else {
                Text("Never checked").foregroundStyle(.secondary)
            }
        case .checking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Checking…").foregroundStyle(.secondary)
            }
        case .upToDate:
            Label("Groundbar is up to date", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .available(let release):
            Button {
                NSWorkspace.shared.open(release.url)
            } label: {
                Label("Download Groundbar \(release.version)", systemImage: "arrow.down.circle.fill")
            }
            .buttonStyle(.link)
        case .failed:
            Label("Couldn't reach GitHub", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
        }
    }
}

extension View {
    /// A scrolling container (grouped Form) as tall as its content, up to `max`; it scrolls only beyond that.
    func fitsContent(max: CGFloat = 640) -> some View { modifier(FitsContent(max: max)) }
}

private struct FitsContent: ViewModifier {
    var max: CGFloat
    @Local private var height: CGFloat? = nil

    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content
                // Only the content's own height: the insets change as the window resizes,
                // which would start a resize loop.
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentSize.height.rounded(.up)
                } action: { _, new in
                    if abs(new - (height ?? 0)) >= 1 { height = new }
                }
                .frame(height: height.map { min($0, max) })
                .scrollBounceBehavior(.basedOnSize)
        } else {
            content.frame(height: 420)
        }
    }
}
