import AppKit
import SwiftUI

/// Groundbar's settings window (bar menu › Settings…, or the gear in the Start menu).
@MainActor
enum SettingsWindow {
    private(set) static var window: NSWindow?

    static func show() {
        TaskbarController.shared.closeFlyout()
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let c = TaskbarController.shared
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 790),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = L("Groundbar Settings")
        w.isReleasedWhenClosed = false
        w.appearance = c.model.theme.appearance
        let host = NSHostingView(rootView: SettingsView(model: c.model, ticker: c.crypto, updater: c.updater))
        host.sizingOptions = []
        w.contentView = host
        w.center()
        window = w
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { _ in
            MainActor.assumeIsolated { SettingsWindow.window = nil }
        }
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @ObservedObject var model: TaskbarModel
    @ObservedObject var ticker: CryptoTicker
    @ObservedObject var updater: Updater
    @Local private var openAtLogin = LoginItem.isEnabled

    var body: some View {
        Form {
            Section("General") {
                Toggle("Open at Login", isOn: Binding(get: { openAtLogin }, set: { LoginItem.set($0); openAtLogin = LoginItem.isEnabled }))
                Picker("Theme", selection: $model.theme) {
                    ForEach(ThemeMode.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Center icons", isOn: $model.centered)
                LabeledContent("Dock") {
                    Button("Hide the Dock") { TaskbarController.shared.autoHideDock() }
                }
            }

            Section("Displays") {
                Toggle("Show the bar on all displays", isOn: $model.barOnAllScreens)
                Toggle("Show apps on the display where their windows are", isOn: $model.appsOnOwnScreen)
                    .disabled(!model.barOnAllScreens)
            }

            Section("Taskbar") {
                Toggle("Show the Bitcoin widget", isOn: $model.showCrypto)
                Picker("Currency", selection: $ticker.currency) {
                    Text("Euro (€)").tag("eur")
                    Text("US dollar ($)").tag("usd")
                }
                .disabled(!model.showCrypto)
                Toggle("Show the screenshot buttons", isOn: $model.showScreenshotButtons)
            }

            Section("Keyboard shortcuts") {
                LabeledContent("Open the 1st…9th app on the bar", value: "⌃⌥1 … ⌃⌥9")
                LabeledContent("Open Start", value: L("⌃⌥Space"))
                LabeledContent("Show desktop", value: "⌃⌥D")
            }

            Section("Updates") {
                Toggle("Check for updates automatically", isOn: $updater.automatic)
                LabeledContent("Version", value: Updater.currentVersion)
                HStack {
                    updateStatus
                    Spacer()
                    Button("Check Now") { updater.check() }
                        .disabled(updater.status == .checking)
                }
            }

            Section("About") {
                LabeledContent("Source code") {
                    Link("github.com/umb-maker/Groundbar", destination: URL(string: "https://github.com/umb-maker/Groundbar")!)
                }
                LabeledContent("License", value: "MIT")
                LabeledContent("Permissions") {
                    Button("Setup & Permissions…") { WelcomeWindow.show() }
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
