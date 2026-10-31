import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

struct TaskbarView: View {
    @ObservedObject var model: TaskbarModel
    @ObservedObject var status: SystemStatus
    @Environment(\.colorScheme) private var scheme
    @Local private var dropTargeted = false

    var body: some View {
        let f = Fluent(scheme)
        ZStack {
            VisualEffect(material: .hudWindow)
            f.barTint
            Rectangle().fill(f.stroke).frame(height: 1).frame(maxHeight: .infinity, alignment: .top)
            if model.theme == .halloween { HalloweenDecor() }
            Color.clear.contentShape(Rectangle()).contextMenu { BarMenu(model: model) }

            HStack(spacing: 4) {
                if model.centered { Spacer(minLength: 0) }
                StartButton()
                ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                    TaskButton(item: item, index: index, model: model)
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, model.centered ? 0 : 12)
            .animation(.easeOut(duration: 0.15), value: model.items.map(\.id))

            // Widget area on the left, as in Windows 11 (moves to the right when icons are left-aligned).
            if model.centered {
                HStack {
                    CryptoWidget(ticker: TaskbarController.shared.crypto)
                    Spacer()
                }
                .padding(.leading, 8)
            }

            HStack(spacing: 2) {
                Spacer()
                if !model.centered { CryptoWidget(ticker: TaskbarController.shared.crypto) }
                BarIconButton(symbol: "rectangle.dashed", help: "Screenshot di una porzione dello schermo") {
                    ScreenCapture.capture(region: true)
                }
                BarIconButton(symbol: "display", help: "Screenshot di tutto lo schermo") {
                    ScreenCapture.capture(region: false)
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
        .help("Start (⌃⌥Spazio)")
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
    let help: String
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 17)).foregroundStyle(Fluent(scheme).text).frame(width: 44, height: 40)
        }
        .buttonStyle(FluentButtonStyle())
        .help(help)
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
        Button { TaskbarController.shared.click(item, rect: frame) } label: {
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: item.isActive)
        .background(GeometryReader { g in
            Color.clear
                .onAppear { frame = g.frame(in: .global) }
                .onChange(of: g.frame(in: .global)) { _, new in frame = new }
        })
        .onHover { inside in
            hovering = inside
            if inside { TaskbarController.shared.hoverBegan(item, rect: frame) } else { TaskbarController.shared.hoverEnded() }
        }
        .help(item.isRunning ? "" : item.name + (index < 9 ? "  (⌃⌥\(index + 1))" : ""))
        .contextMenu {
            Text(item.name)
            Divider()
            if let url = item.url {
                Button(item.isRunning ? "Nuova finestra" : "Apri") { TaskbarModel.launch(url) }
            }
            Button(item.pinned ? "Rimuovi dalla barra delle applicazioni" : "Aggiungi alla barra delle applicazioni") {
                model.setPinned(item, !item.pinned)
            }
            let recent = files.recent(forApp: item.id.hasPrefix("/") ? nil : item.id)
            if !recent.isEmpty {
                Divider()
                Section("Recenti") {
                    ForEach(recent) { entry in
                        Button { FileIndex.open(entry) } label: {
                            Label { Text(entry.name) } icon: { Image(nsImage: files.icon(entry)) }
                        }
                    }
                }
            }
            if let app = item.app, item.isRunning {
                Divider()
                Button("Chiudi") { app.terminate() }
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
            TaskbarController.shared.toggleFlyout("quick", anchor: .right(r.maxX + 120), size: CGSize(width: 360, height: 220)) {
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
        .help("Impostazioni rapide")
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
            TaskbarController.shared.closeFlyout()
            model.toggleDesktop()
        }
        .help("Mostra desktop (⌃⌥D)")
        .padding(.leading, 4)
    }
}

// MARK: - Bar context menu

struct BarMenu: View {
    @ObservedObject var model: TaskbarModel

    var body: some View {
        Picker("Tema", selection: $model.theme) {
            ForEach(ThemeMode.allCases) { Text($0.label).tag($0) }
        }
        Toggle("Icone al centro", isOn: $model.centered)
        Toggle("Avvia con il Mac", isOn: Binding(
            get: { SMAppService.mainApp.status == .enabled },
            set: { on in
                do {
                    if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                } catch {
                    Log.write("login item: \(error.localizedDescription)")
                }
            }
        ))
        Divider()
        Button("Nascondi automaticamente il Dock") { TaskbarController.shared.autoHideDock() }
        Button("Permessi Accessibilità…") {
            TaskbarController.openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        }
        Button("Permessi Registrazione schermo…") {
            TaskbarController.openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        }
        Divider()
        Button("Esci da OmniBar") { NSApp.terminate(nil) }
    }
}
