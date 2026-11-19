import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct TaskbarView: View {
    @ObservedObject var model: TaskbarModel
    @ObservedObject var status: SystemStatus
    /// The display this bar sits on.
    let display: CGDirectDisplayID
    @Environment(\.colorScheme) private var scheme
    @Local private var dropTargeted = false

    /// Items shown on this bar, with their index in the full list (used by the ⌃⌥1…9 shortcuts).
    /// Pinned apps are on every bar; with "apps on their own display" the others only on the display
    /// of their windows.
    private var visibleItems: [(index: Int, item: TaskItem)] {
        let perDisplay = model.barOnAllScreens && model.appsOnOwnScreen && NSScreen.screens.count > 1
        return model.items.enumerated().map { ($0.offset, $0.element) }.filter { _, item in
            !perDisplay || item.pinned || item.displays.isEmpty || item.displays.contains(display)
        }
    }

    var body: some View {
        let f = Fluent(scheme)
        ZStack {
            ThemedMaterial(material: .hudWindow)
            f.barTint
            Rectangle().fill(f.stroke).frame(height: 1).frame(maxHeight: .infinity, alignment: .top)
            if model.theme == .halloween { HalloweenDecor() }
            if model.theme == .christmas { ChristmasDecor() }
            if model.theme == .santa { SantaDecor() }
            Color.clear.contentShape(Rectangle()).contextMenu { BarMenu(model: model) }

            HStack(spacing: 4) {
                if model.centered { Spacer(minLength: 0) }
                StartButton()
                ForEach(visibleItems, id: \.item.id) { entry in
                    TaskButton(item: entry.item, index: entry.index, model: model)
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, model.centered ? 0 : 12)
            .animation(.easeOut(duration: 0.15), value: model.items.map(\.id))

            // Widget area on the left, as in Windows 11 (moves to the right when icons are left-aligned).
            if model.centered && model.showCrypto {
                HStack {
                    CryptoWidget(ticker: TaskbarController.shared.crypto)
                    Spacer()
                }
                .padding(.leading, 8)
            }

            HStack(spacing: 2) {
                Spacer()
                if !model.centered && model.showCrypto { CryptoWidget(ticker: TaskbarController.shared.crypto) }
                if model.showScreenshotButtons {
                    BarIconButton(symbol: "rectangle.dashed", help: "Screenshot of part of the screen") {
                        ScreenCapture.capture(region: true)
                    }
                    BarIconButton(symbol: "display", help: "Screenshot of the whole screen") {
                        ScreenCapture.capture(region: false)
                    }
                }
                TrayButton(status: status)
                ShowDesktopStrip(model: model)
            }
        }
        .frame(height: TaskbarController.barHeight)
        // Rebuild every view on a theme change: Fluent reads the Halloween flag at init.
        .id(model.theme)
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Fluent(scheme).accent, lineWidth: 2).opacity(dropTargeted ? 1 : 0))
        // Drop folders, files or apps to pin them.
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in TaskbarController.shared.model.pin(url) }
                }
            }
            return true
        }
    }
}

// MARK: - Buttons

private struct StartButton: View {
    var body: some View {
        Button { TaskbarController.shared.toggleStart() } label: {
            Group {
                if let icon = Assets.startIcon {
                    Image(nsImage: icon).resizable().interpolation(.high).clipShape(Circle()).frame(width: 28, height: 28)
                } else {
                    StartGlyph().frame(width: 22, height: 22)
                }
            }
            .frame(width: 44, height: 40)
        }
        .buttonStyle(FluentButtonStyle())
        .barTooltip(L("Start (⌃⌥Space)"))
        .accessibilityLabel("Start")
    }
}

/// Four rounded tiles with a blue gradient.
struct StartGlyph: View {
    var body: some View {
        GeometryReader { g in
            let gap = g.size.width * 0.08
            let side = (g.size.width - gap) / 2
            let tiles = [CGPoint(x: 0, y: 0), CGPoint(x: side + gap, y: 0), CGPoint(x: 0, y: side + gap), CGPoint(x: side + gap, y: side + gap)]
            ZStack(alignment: .topLeading) {
                ForEach(0..<4, id: \.self) { i in
                    RoundedRectangle(cornerRadius: side * 0.12)
                        .fill(LinearGradient(colors: [Color(red: 0.16, green: 0.71, blue: 1.0), Color(red: 0.0, green: 0.42, blue: 0.86)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: side, height: side)
                        .offset(x: tiles[i].x, y: tiles[i].y)
                }
            }
        }
    }
}

private struct BarIconButton: View {
    let symbol: String
    let help: String.LocalizationValue
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 17)).foregroundStyle(Fluent(scheme).text).frame(width: 44, height: 40)
        }
        .buttonStyle(FluentButtonStyle())
        .barTooltip(L(help))
        .accessibilityLabel(L(help))
    }
}

/// The red unread count on a task button, as on the Dock.
private struct BadgeView: View {
    let text: String

    var body: some View {
        // A badge that is only a dot (some apps set a space) shows as a small dot.
        let label = text.trimmingCharacters(in: .whitespaces)
        Text(label.count > 3 ? "…" : label)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, label.isEmpty ? 0 : 4)
            .frame(minWidth: label.isEmpty ? 8 : 15, minHeight: label.isEmpty ? 8 : 15)
            .background(Capsule().fill(Color(red: 0.93, green: 0.2, blue: 0.2)))
            .accessibilityLabel(label)
    }
}

/// Reordering pinned icons by dragging: the icon under the pointer makes room as the dragged one passes
/// over it. A plain gesture, not system drag and drop: the bar is never the key window, and SwiftUI's
/// drag never starts there.
@MainActor
enum PinDrag {
    /// The pinned item being dragged.
    static var dragging: String?
    static var endedAt = Date.distantPast
    /// Each task button's frame in its bar window (top-left origin).
    /// shortcut: one map for all bars, so with bars on displays of different widths the last bar drawn wins; key it by display if that matters.
    static var frames: [String: CGRect] = [:]

    /// A click right after a drag is the drag's own mouse-up: ignore it.
    static var clickAllowed: Bool { dragging == nil && Date().timeIntervalSince(endedAt) > 0.3 }

    static func moved(_ id: String, to x: CGFloat, model: TaskbarModel) {
        if dragging == nil {
            dragging = id
            TaskbarController.shared.tooltip.hide()
            TaskbarController.shared.previews.hide()
        }
        if let target = frames.first(where: { $0.key != id && x >= $0.value.minX && x < $0.value.maxX })?.key {
            model.movePin(id, to: target)  // does nothing unless the target is pinned too
        }
    }

    /// Windows' middle click on a task button opens a new window of that app. SwiftUI has no middle
    /// click, so a monitor on the bar's own events finds the button under the pointer.
    static func watchMiddleClicks(model: TaskbarModel) {
        NSEvent.addLocalMonitorForEvents(matching: .otherMouseUp) { event in
            guard event.buttonNumber == 2, TaskbarController.shared.isBar(event.window),
                  let id = frames.first(where: { event.locationInWindow.x >= $0.value.minX && event.locationInWindow.x < $0.value.maxX })?.key,
                  let item = model.items.first(where: { $0.id == id }) else { return event }
            TaskbarModel.newWindow(item)
            return nil
        }
    }

    static func ended() {
        dragging = nil
        endedAt = Date()
    }
}

private struct TaskButton: View {
    let item: TaskItem
    let index: Int
    @ObservedObject var model: TaskbarModel
    @ObservedObject private var files = TaskbarController.shared.files
    @Local private var hovering = false
    @Local private var frame: CGRect = .zero
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let f = Fluent(scheme)
        Button { if PinDrag.clickAllowed { TaskbarController.shared.click(item, rect: frame) } } label: {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(item.isActive ? f.activeBg : (hovering ? f.hover : Color.clear))
                Image(nsImage: item.icon).resizable().interpolation(.high)
                    .frame(width: 28, height: 28)
                    .frame(maxHeight: .infinity)
                if item.isRunning && item.hasWindows {
                    Capsule().fill(item.isActive ? f.accent : f.secondary)
                        .frame(width: item.isActive ? 16 : 6, height: 3)
                        .padding(.bottom, 1)
                }
            }
            .frame(width: 44, height: 40)
            .overlay(alignment: .topTrailing) {
                if let badge = item.badge { BadgeView(text: badge).padding(.top, 3).padding(.trailing, 4) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: item.isActive)
        .background(GeometryReader { g in
            Color.clear
                .onAppear { frame = g.frame(in: .global); PinDrag.frames[item.id] = frame }
                .onChange(of: g.frame(in: .global)) { _, new in frame = new; PinDrag.frames[item.id] = new }
                .onDisappear { PinDrag.frames[item.id] = nil }
        })
        .onHover { inside in
            hovering = inside
            let c = TaskbarController.shared
            if inside { c.previews.hoverBegan(item, anchor: c.screenRect(fromBar: frame)) } else { c.previews.hoverEnded() }
        }
        .barTooltip(item.isRunning ? "" : item.name + (index < 9 ? "  (⌃⌥\(index + 1))" : ""))
        // Drag a pinned icon onto another to change the order, as on Windows.
        .simultaneousGesture(DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { v in if item.pinned { PinDrag.moved(item.id, to: v.location.x, model: model) } }
            .onEnded { _ in PinDrag.ended() })
        .contextMenu {
            Text(item.name)
            Divider()
            if let url = item.url {
                Button(item.isRunning ? "New Window" : "Open") { item.isRunning ? TaskbarModel.newWindow(item) : TaskbarModel.launch(url) }
            }
            Button(item.pinned ? "Unpin from taskbar" : "Pin to taskbar") {
                model.setPinned(item, !item.pinned)
            }
            let recent = files.recent(forApp: item.id.hasPrefix("/") ? nil : item.id)
            if !recent.isEmpty {
                Divider()
                Section("Recent") {
                    ForEach(recent) { entry in
                        Button { FileIndex.open(entry) } label: {
                            Label { Text(entry.name) } icon: { Image(nsImage: files.icon(entry)) }
                        }
                    }
                }
            }
            if let app = item.app, item.isRunning {
                Divider()
                Button("Quit") { app.terminate() }
            }
        }
    }
}

// MARK: - Tray

private struct TrayButton: View {
    @ObservedObject var status: SystemStatus
    @Local private var frame: CGRect = .zero
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let f = Fluent(scheme)
        Button {
            status.refresh()
            let r = TaskbarController.shared.screenRect(fromBar: frame)
            TaskbarController.shared.flyouts.toggle("quick", anchor: .right(r.maxX + 120), size: CGSize(width: 360, height: 220)) {
                QuickSettingsView(status: status, model: TaskbarController.shared.model)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: status.networkSymbol)
                Image(systemName: status.volumeSymbol).frame(width: 18)
            }
            .font(.system(size: 13))
            .foregroundStyle(f.text)
            .padding(.horizontal, 10)
            .frame(height: 40)
        }
        .buttonStyle(FluentButtonStyle())
        .background(GeometryReader { g in
            Color.clear.onAppear { frame = g.frame(in: .global) }.onChange(of: g.frame(in: .global)) { _, n in frame = n }
        })
        .barTooltip(L("Quick settings"))
        .accessibilityLabel("Quick settings")
    }
}

private struct ShowDesktopStrip: View {
    @ObservedObject var model: TaskbarModel
    @Local private var hovering = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let f = Fluent(scheme)
        HStack(spacing: 0) {
            Rectangle().fill(f.stroke.opacity(hovering ? 3 : 1.5)).frame(width: 1, height: 20)
            Rectangle().fill(hovering ? f.hover : Color.clear).frame(width: 9)
        }
        .frame(height: TaskbarController.barHeight)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            TaskbarController.shared.flyouts.close()
            model.toggleDesktop()
        }
        .barTooltip(L("Show desktop (⌃⌥D)"))
        .accessibilityLabel("Show desktop")
        .accessibilityAddTraits(.isButton)
        .padding(.leading, 4)
    }
}

// MARK: - Bar context menu

struct BarMenu: View {
    @ObservedObject var model: TaskbarModel

    var body: some View {
        Picker("Theme", selection: $model.theme) {
            ForEach(ThemeMode.allCases) { Text($0.label).tag($0) }
        }
        Toggle("Center icons", isOn: $model.centered)
        Toggle("Open at Login", isOn: LoginItem.binding)
        Divider()
        Button("Automatically Hide the Dock") { TaskbarController.shared.autoHideDock() }
        Button("Setup & Permissions…") { WelcomeWindow.show() }
        Button("Settings…") { SettingsWindow.show() }
        Divider()
        Button("Quit Groundbar") { NSApp.terminate(nil) }
    }
}
