import AppKit
import SwiftUI

struct StartMenuView: View {
    @ObservedObject var model: TaskbarModel
    @ObservedObject var catalog: AppCatalog
    @ObservedObject var files: FileIndex
    @Local private var query = ""
    @Local private var showAll = false
    @Local private var showAllRecent = false
    @Local private var selection = 0
    @FocusState private var searchFocused: Bool
    @Environment(\.colorScheme) private var scheme

    /// A search result: an app or a file.
    private enum Hit: Identifiable {
        case app(AppEntry)
        case file(FileEntry)
        var id: String {
            switch self {
            case .app(let a): "app:" + a.id
            case .file(let f): "file:" + f.id
            }
        }
    }

    private var hits: [Hit] {
        catalog.search(query).prefix(6).map(Hit.app) + files.searchResults.map(Hit.file)
    }

    var body: some View {
        let f = Fluent(scheme)
        VStack(spacing: 0) {
            searchField(f)
                .padding(.horizontal, 32)
                .padding(.top, 28)
                .padding(.bottom, 20)

            Group {
                if !query.isEmpty {
                    resultsList(f)
                } else if showAll {
                    allAppsList(f)
                } else if showAllRecent {
                    recentList(f)
                } else {
                    home(f)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            footer(f)
        }
        .flyoutChrome()
        .onAppear { DispatchQueue.main.async { searchFocused = true } }
        .onChange(of: query) { _, new in
            selection = 0
            files.search(new)
        }
    }

    // MARK: Parts

    private func searchField(_ f: Fluent) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(f.secondary)
            TextField("Cerca app e file", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($searchFocused)
                .focusEffectDisabled()
                .onSubmit {
                    let list = hits
                    if list.indices.contains(selection) { open(list[selection]) }
                }
                .onKeyPress(.downArrow) { selection = min(selection + 1, max(hits.count - 1, 0)); return .handled }
                .onKeyPress(.upArrow) { selection = max(selection - 1, 0); return .handled }
        }
        .foregroundStyle(f.text)
        .padding(.horizontal, 14)
        .frame(height: 36)
        .background(Capsule().fill(f.field))
        .overlay(Capsule().strokeBorder(searchFocused ? f.accent.opacity(0.8) : f.stroke, lineWidth: 1))
    }

    private func sectionHeader(_ title: String, button: String, action: @escaping () -> Void) -> some View {
        let f = Fluent(scheme)
        return HStack {
            Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(f.text)
            Spacer()
            Button(action: action) {
                Text(button).font(.system(size: 12)).foregroundStyle(f.text)
                    .padding(.horizontal, 10).frame(height: 24)
                    .background(RoundedRectangle(cornerRadius: 4).fill(f.cardTint))
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(f.stroke))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 48)
        .padding(.bottom, 8)
    }

    /// Recently used apps, then "Consigliati" (recent files), as in Windows 11.
    private func home(_ f: Fluent) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                sectionHeader("App recenti", button: "Tutte le app  ›") { showAll = true }
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(88), spacing: 4), count: 6), spacing: 6) {
                    ForEach(catalog.recentApps) { entry in
                        Button { open(entry) } label: {
                            VStack(spacing: 6) {
                                Image(nsImage: catalog.icon(entry)).resizable().frame(width: 36, height: 36)
                                Text(entry.name).font(.system(size: 11)).foregroundStyle(f.text)
                                    .lineLimit(1).truncationMode(.tail)
                            }
                            .frame(width: 88, height: 76)
                        }
                        .buttonStyle(FluentButtonStyle())
                        .contextMenu { entryMenu(entry) }
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 20)

                sectionHeader("Consigliati", button: "Altro  ›") { showAllRecent = true }
                if files.recent.isEmpty {
                    Text("I file che apri compariranno qui.")
                        .font(.system(size: 12)).foregroundStyle(f.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 48).padding(.vertical, 8)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 4) {
                        ForEach(files.recent.prefix(6)) { entry in fileRow(entry, f, selected: false) }
                    }
                    .padding(.horizontal, 36)
                }
            }
            .padding(.bottom, 12)
        }
    }

    private func recentList(_ f: Fluent) -> some View {
        VStack(spacing: 0) {
            sectionHeader("Consigliati", button: "‹  Indietro") { showAllRecent = false }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(files.recent) { entry in fileRow(entry, f, selected: false) }
                }
                .padding(.horizontal, 36)
            }
        }
    }

    private func fileRow(_ entry: FileEntry, _ f: Fluent, selected: Bool) -> some View {
        Button { open(.file(entry)) } label: {
            HStack(spacing: 12) {
                Image(nsImage: files.icon(entry)).resizable().frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.name).font(.system(size: 12)).foregroundStyle(f.text)
                        .lineLimit(1).truncationMode(.middle)
                    Text(FileIndex.relative(entry.lastUsed)).font(.system(size: 11)).foregroundStyle(f.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: 48)
            .overlay(alignment: .leading) {
                if selected { Capsule().fill(f.accent).frame(width: 3, height: 16) }
            }
        }
        .buttonStyle(FluentButtonStyle(selected: selected))
        .help(entry.url.path)
        .contextMenu {
            Button("Apri") { open(.file(entry)) }
            Button("Mostra nel Finder") { NSWorkspace.shared.activateFileViewerSelecting([entry.url]) }
            Button("Fissa sulla barra delle applicazioni") { model.pin(entry.url) }
        }
    }

    private func allAppsList(_ f: Fluent) -> some View {
        VStack(spacing: 0) {
            sectionHeader("Tutte le app", button: "‹  Indietro") { showAll = false }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    let groups = Dictionary(grouping: catalog.apps) { initial($0.name) }
                    ForEach(groups.keys.sorted(), id: \.self) { letter in
                        Text(letter).font(.system(size: 12, weight: .semibold)).foregroundStyle(f.secondary)
                            .padding(.leading, 12).padding(.top, 10).padding(.bottom, 4)
                        ForEach(groups[letter] ?? []) { entry in row(entry, f, selected: false) }
                    }
                }
                .padding(.horizontal, 36)
            }
        }
    }

    private func resultsList(_ f: Fluent) -> some View {
        let list = hits
        let appCount = list.filter { if case .app = $0 { true } else { false } }.count
        return VStack(alignment: .leading, spacing: 0) {
            if list.isEmpty {
                Text("Nessun risultato per \"\(query)\"")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(f.text)
                    .padding(.horizontal, 48).padding(.bottom, 6)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { i, hit in
                        if i == 0 && appCount > 0 { resultsHeader("App", f) }
                        if i == appCount { resultsHeader("File", f) }
                        switch hit {
                        case .app(let entry): row(entry, f, selected: i == selection)
                        case .file(let entry): fileRow(entry, f, selected: i == selection)
                        }
                    }
                }
                .padding(.horizontal, 36)
            }
        }
    }

    private func resultsHeader(_ title: String, _ f: Fluent) -> some View {
        Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(f.secondary)
            .padding(.leading, 12).padding(.top, 8).padding(.bottom, 4)
    }

    private func row(_ entry: AppEntry, _ f: Fluent, selected: Bool) -> some View {
        Button { open(entry) } label: {
            HStack(spacing: 12) {
                Image(nsImage: catalog.icon(entry)).resizable().frame(width: 26, height: 26)
                Text(entry.name).font(.system(size: 13)).foregroundStyle(f.text)
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .overlay(alignment: .leading) {
                if selected { Capsule().fill(f.accent).frame(width: 3, height: 16) }
            }
        }
        .buttonStyle(FluentButtonStyle(selected: selected))
        .contextMenu { entryMenu(entry) }
    }

    @ViewBuilder
    private func entryMenu(_ entry: AppEntry) -> some View {
        Button("Apri") { open(entry) }
        Divider()
        if !model.isPinnedToBar(entry) {
            Button("Aggiungi alla barra delle applicazioni") { model.pinToBar(entry) }
        }
        Button("Mostra nel Finder") { NSWorkspace.shared.activateFileViewerSelecting([entry.url]) }
    }

    private func footer(_ f: Fluent) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "person.crop.circle.fill").font(.system(size: 26)).foregroundStyle(f.secondary)
            Text(NSFullUserName()).font(.system(size: 12)).foregroundStyle(f.text)
            Spacer()
            Menu {
                Button("Blocca") { Power.lock() }
                Button("Sospendi") { Power.run("sleep") }
                Divider()
                Button("Esci (logout)") { Power.run("log out") }
                Button("Riavvia") { Power.run("restart") }
                Button("Arresta il sistema") { Power.run("shut down") }
            } label: {
                Image(systemName: "power").font(.system(size: 15)).foregroundStyle(f.text)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 36, height: 36)
            .help("Arresta")
        }
        .padding(.horizontal, 48)
        .frame(height: 64)
        .background(f.cardTint.opacity(0.45))
        .overlay(alignment: .top) { Rectangle().fill(f.stroke).frame(height: 1) }
    }

    // MARK: Helpers

    private func initial(_ name: String) -> String {
        guard let c = name.folding(options: .diacriticInsensitive, locale: nil).first?.uppercased(), c.first!.isLetter else { return "#" }
        return c
    }

    private func open(_ entry: AppEntry) {
        TaskbarController.shared.closeFlyout()
        TaskbarModel.launch(entry.url)
    }

    private func open(_ hit: Hit) {
        switch hit {
        case .app(let entry): open(entry)
        case .file(let entry):
            TaskbarController.shared.closeFlyout()
            FileIndex.open(entry)
        }
    }
}

@MainActor
enum Power {
    static func run(_ command: String) {
        TaskbarController.shared.closeFlyout()
        var error: NSDictionary?
        NSAppleScript(source: "tell application \"System Events\" to \(command)")?.executeAndReturnError(&error)
    }

    static func lock() {
        TaskbarController.shared.closeFlyout()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        p.arguments = ["displaysleepnow"]
        try? p.run()
    }
}
