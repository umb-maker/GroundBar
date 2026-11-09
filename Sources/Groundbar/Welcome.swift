import AppKit
import ApplicationServices
import ServiceManagement
import SwiftUI

/// Open at login through ServiceManagement (shown in System Settings › General › Login Items).
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            Log.write("login item: \(error.localizedDescription)")
        }
    }

    static var binding: Binding<Bool> { Binding(get: { isEnabled }, set: { set($0) }) }
}

/// Live state of the two privacy permissions Groundbar needs.
@MainActor
final class PermissionState: ObservableObject {
    @Published private(set) var accessibility = AXIsProcessTrusted()
    @Published private(set) var screenRecording = CGPreflightScreenCaptureAccess()
    private var timer: Timer?

    var allGranted: Bool { accessibility && screenRecording }

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer?.tolerance = 0.3
    }

    func refresh() {
        let ax = AXIsProcessTrusted(), screen = CGPreflightScreenCaptureAccess()
        if ax != accessibility { accessibility = ax }
        if screen != screenRecording { screenRecording = screen }
    }

    /// Adds Groundbar to the Accessibility list (with the system prompt) and opens that pane.
    func requestAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
        TaskbarController.openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    /// Adds Groundbar to the Screen Recording list (with the system prompt) and opens that pane.
    func requestScreenRecording() {
        _ = CGRequestScreenCaptureAccess()
        TaskbarController.openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    }

    func stop() { timer?.invalidate() }
}

/// First-run window: explains the permissions, shows whether they are granted, offers a couple of options.
@MainActor
enum WelcomeWindow {
    private(set) static var window: NSWindow?
    private static var permissions: PermissionState?
    private static let shownKey = "welcomeShown"

    /// Shown on the first launch, and on every launch while a permission is missing.
    static func showIfNeeded() {
        let missing = !AXIsProcessTrusted() || !CGPreflightScreenCaptureAccess()
        if !UserDefaults.standard.bool(forKey: shownKey) || missing { show() }
    }

    static func show() {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let state = PermissionState()
        permissions = state
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 600),
                         styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isReleasedWhenClosed = false
        w.appearance = TaskbarController.shared.model.theme.appearance
        let host = NSHostingView(rootView: WelcomeView(permissions: state, model: TaskbarController.shared.model))
        host.sizingOptions = []  // the window keeps its size; the view fills it, title bar included
        w.contentView = host
        w.center()
        window = w
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { _ in
            MainActor.assumeIsolated { WelcomeWindow.didClose() }
        }
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    static func close() { window?.close() }

    private static func didClose() {
        UserDefaults.standard.set(true, forKey: shownKey)
        permissions?.stop()
        permissions = nil
        window = nil
    }
}

struct WelcomeView: View {
    @ObservedObject var permissions: PermissionState
    @ObservedObject var model: TaskbarModel
    @Local private var openAtLogin = LoginItem.isEnabled
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let f = Fluent(scheme)
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 84, height: 84)
                Text("Welcome to Groundbar").font(.system(size: 24, weight: .bold))
                Text("A Windows-style taskbar for your Mac. To list your windows and documents, Groundbar needs two macOS permissions.")
                    .font(.system(size: 13)).foregroundStyle(f.secondary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 48).padding(.horizontal, 40)

            VStack(spacing: 10) {
                permissionRow(f, symbol: "hand.raised.fill", title: "Accessibility",
                              detail: "Lists your open windows and documents, brings them to the front and closes them.",
                              granted: permissions.accessibility, action: permissions.requestAccessibility)
                permissionRow(f, symbol: "rectangle.dashed.badge.record", title: "Screen Recording",
                              detail: "Reads window titles and takes the screenshots you ask for.",
                              granted: permissions.screenRecording, action: permissions.requestScreenRecording)
                if !permissions.screenRecording {
                    Text("After allowing Screen Recording, macOS may ask you to quit and reopen Groundbar.")
                        .font(.system(size: 11)).foregroundStyle(f.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, 32).padding(.top, 22)

            VStack(alignment: .leading, spacing: 10) {
                Toggle("Open at Login", isOn: Binding(get: { openAtLogin }, set: { LoginItem.set($0); openAtLogin = LoginItem.isEnabled }))
                HStack {
                    Text("The Dock can cover the bar: hide it automatically.").font(.system(size: 12)).foregroundStyle(f.secondary)
                    Spacer()
                    Button("Hide the Dock") { TaskbarController.shared.autoHideDock() }
                }
            }
            .toggleStyle(.switch)
            .padding(.horizontal, 36).padding(.top, 18)

            Spacer(minLength: 12)

            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "lock.shield").foregroundStyle(f.secondary)
                Text("Nothing about you leaves your Mac: Groundbar only fetches the Bitcoin price from CoinGecko and checks GitHub for updates.")
                    .font(.system(size: 11)).foregroundStyle(f.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button(permissions.allGranted ? "Get Started" : "Later") { WelcomeWindow.close() }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
            }
            .padding(.horizontal, 32).padding(.vertical, 18)
            .background(f.cardTint.opacity(0.5))
        }
        .foregroundStyle(f.text)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The title bar is transparent: let the background run under it too.
        .background(ZStack { VisualEffect(material: .windowBackground); f.flyoutTint }.ignoresSafeArea())
        .ignoresSafeArea()
    }

    private func permissionRow(_ f: Fluent, symbol: String, title: LocalizedStringKey, detail: LocalizedStringKey,
                               granted: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 20)).foregroundStyle(f.accent).frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundStyle(f.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if granted {
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.green)
            } else {
                Button("Allow…", action: action).controlSize(.regular)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(f.cardTint))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(f.stroke))
    }
}
