import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Windows of the hovered app: thumbnails for a few windows, a compact list of documents for many.
@MainActor
final class PreviewModel: ObservableObject {
    struct Card: Identifiable {
        let window: AppWindow
        let icon: NSImage
        var image: NSImage?
        var id: String { window.id }
    }

    @Published private(set) var cards: [Card] = []
    @Published private(set) var windows = 0
    @Published private(set) var loading = false
    @Published private(set) var needsPermission = false
    @Published private(set) var name = ""
    @Published private(set) var icon = NSImage()
    private(set) var app: NSRunningApplication?
    private var token = 0

    static let thumb = CGSize(width: 210, height: 130)
    /// Above this many windows the picker switches from thumbnails to the vertical list (0 = always the list).
    static let maxThumbnails = 0
    static let maxWindows = 20
    static let rowHeight: CGFloat = 40
    static let listWidth: CGFloat = 360

    /// Icon of the document type (by extension), without touching the file.
    static func fileIcon(_ url: URL) -> NSImage {
        NSWorkspace.shared.icon(for: UTType(filenameExtension: url.pathExtension) ?? .data)
    }

    var listMode: Bool { cards.count > Self.maxThumbnails }

    var panelSize: CGSize {
        if cards.isEmpty && needsPermission { return CGSize(width: 300, height: 96) }
        if cards.isEmpty { return CGSize(width: max(140, CGFloat(name.count) * 7.5 + 56), height: 40) }
        if listMode {
            let rows = CGFloat(min(cards.count, 10))
            return CGSize(width: Self.listWidth, height: 44 + rows * Self.rowHeight + 10)
        }
        return CGSize(width: CGFloat(cards.count) * (Self.thumb.width + 24) + 4, height: Self.thumb.height + 60)
    }

    func load(app: NSRunningApplication, name: String, icon: NSImage) {
        if app == self.app { return }
        token += 1
        let t = token
        self.app = app
        self.name = name
        self.icon = icon
        cards = []
        windows = 0
        loading = true
        needsPermission = !AXIsProcessTrusted()
        Task { @MainActor in
            let list = await WindowService.windows(of: app)
            guard t == token else { return }
            loading = false
            cards = list.prefix(Self.maxWindows).map { w in
                Card(window: w, icon: w.document.map(Self.fileIcon) ?? icon, image: nil)
            }
            windows = cards.count
            guard !listMode else { return }
            for (i, card) in cards.enumerated() {
                guard let sc = card.window.scWindow, !card.window.minimized else { continue }
                let image = await WindowService.thumbnail(sc, maxSize: Self.thumb)
                guard t == token, cards.indices.contains(i) else { return }
                cards[i].image = image
            }
        }
    }

    /// Debug: shows a fixed list of windows (used by `--snapshot`).
    func loadStatic(_ list: [AppWindow], name: String, icon: NSImage) {
        clear()
        self.name = name
        self.icon = icon
        cards = list.map { w in Card(window: w, icon: w.document.map(Self.fileIcon) ?? icon, image: nil) }
        windows = cards.count
    }

    func focus(_ card: Card) {
        guard let app else { return }
        let window = card.window
        TaskbarController.shared.hidePreview()
        WindowService.focus(window, of: app)
    }

    func close(_ card: Card) {
        if let app { WindowService.close(card.window, of: app) }
        cards.removeAll { $0.id == card.id }
        windows = cards.count
    }

    func clear() {
        token += 1
        app = nil
        cards = []
        windows = 0
        loading = false
    }
}

struct PreviewView: View {
    @ObservedObject var model: PreviewModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let f = Fluent(scheme)
        Group {
            if model.cards.isEmpty && model.needsPermission {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(nsImage: model.icon).resizable().frame(width: 16, height: 16)
                        Text(model.name).font(.system(size: 12, weight: .semibold))
                    }
                    Text("Groundbar needs the Accessibility permission to list windows.")
                        .font(.system(size: 11)).foregroundStyle(f.secondary).fixedSize(horizontal: false, vertical: true)
                    Button("Open Accessibility Settings") {
                        TaskbarController.shared.hidePreview()
                        TaskbarController.openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
                    }
                    .buttonStyle(.link).font(.system(size: 11))
                }
                .foregroundStyle(f.text)
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            } else             if model.cards.isEmpty {
                HStack(spacing: 8) {
                    Image(nsImage: model.icon).resizable().frame(width: 16, height: 16)
                    Text(model.name).font(.system(size: 12)).foregroundStyle(f.text).lineLimit(1)
                }
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.listMode {
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Image(nsImage: model.icon).resizable().frame(width: 18, height: 18)
                        Text(model.name).font(.system(size: 12, weight: .semibold))
                        Spacer()
                        Text("\(model.cards.count) windows").font(.system(size: 11)).foregroundStyle(f.secondary)
                    }
                    .foregroundStyle(f.text)
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(model.cards) { card in PreviewRow(card: card, model: model) }
                        }
                        .padding(.horizontal, 6)
                    }
                }
                .padding(.bottom, 6)
            } else {
                HStack(spacing: 8) {
                    ForEach(model.cards) { card in PreviewCard(card: card, model: model) }
                }
                .padding(6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .flyoutChrome()
        .onHover { TaskbarController.shared.previewHover($0) }
    }
}

private struct CloseButton: View {
    let visible: Bool
    let action: () -> Void
    @Local private var hovering = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark").font(.system(size: 10, weight: .medium)).frame(width: 24, height: 22)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.red.opacity(hovering ? 0.85 : 0)))
                .foregroundStyle(hovering ? .white : Fluent(scheme).text)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .opacity(visible ? 1 : 0)
        .help("Close window")
        .accessibilityLabel("Close window")
    }
}

/// One document in list mode.
private struct PreviewRow: View {
    let card: PreviewModel.Card
    let model: PreviewModel
    @Local private var hovering = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let f = Fluent(scheme)
        HStack(spacing: 10) {
            Image(nsImage: card.icon).resizable().frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(card.window.displayName).font(.system(size: 12)).foregroundStyle(f.text)
                    .lineLimit(1).truncationMode(.middle)
                if card.window.minimized {
                    Text("Minimized").font(.system(size: 10)).foregroundStyle(f.secondary)
                }
            }
            Spacer(minLength: 4)
            CloseButton(visible: hovering) { model.close(card) }
        }
        .padding(.horizontal, 8)
        .frame(height: PreviewModel.rowHeight)
        .background(RoundedRectangle(cornerRadius: 4).fill(hovering ? f.hover : Color.clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { model.focus(card) }
        .help(card.window.document?.path ?? card.window.title)
    }
}

/// One window in thumbnail mode.
private struct PreviewCard: View {
    let card: PreviewModel.Card
    let model: PreviewModel
    @Local private var hovering = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let f = Fluent(scheme)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(nsImage: card.icon).resizable().frame(width: 16, height: 16)
                Text(card.window.displayName).font(.system(size: 12)).foregroundStyle(f.text)
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
                CloseButton(visible: hovering) { model.close(card) }
            }
            ZStack {
                if let image = card.image {
                    Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                } else {
                    VStack(spacing: 6) {
                        Image(nsImage: card.icon).resizable().frame(width: 48, height: 48).opacity(0.85)
                        if card.window.minimized {
                            Text("Minimized").font(.system(size: 10)).foregroundStyle(f.secondary)
                        }
                    }
                }
            }
            .frame(width: PreviewModel.thumb.width, height: PreviewModel.thumb.height)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(hovering ? f.hover : Color.clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { model.focus(card) }
        .help(card.window.document?.path ?? card.window.title)
    }
}
