// The library (start screen): the Continue card (the last session, resumed where it was), game
// cards from Documents/ROM with the game database's titles, sort / filter / favourites / recent
// (shared core: LibraryCatalog), search, the projects of a game, ROM import (document picker or
// the Files app: On My iPhone › ReplayNES › ROM).
// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var library = AppModel.shared.library
    @ObservedObject private var focus = LibraryFocus.shared
    @ObservedObject private var entitlements = Entitlements.shared
    @State private var query = ""
    @State private var importing = false
    @State private var projectsOf: LibraryROM?

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let columns = max(2, Int(geo.size.width / 170))
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        hero
                        if let e = library.folderError ?? library.scanError {
                            Text(e).font(.footnote).foregroundStyle(.red)
                        }
                        let games = library.arranged(query: query)
                        if library.roms.isEmpty && !library.scanning {
                            emptyState
                        } else {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columns), spacing: 14) {
                                ForEach(Array(games.enumerated()), id: \.element.id) { i, rom in
                                    GameCard(rom: rom, favorite: library.isFavorite(rom), projects: library.projects(for: rom).count,
                                             focused: focus.index == i && !model.controllers.isEmpty)
                                        .accessibilityElement(children: .combine)
                                        .accessibilityIdentifier("gameCard.\(rom.relativePath)")
                                        .accessibilityAddTraits(.isButton)
                                        .onTapGesture { model.playFromLibrary(rom) }
                                        .contextMenu { cardMenu(rom) }
                                }
                            }
                            .onAppear { focus.columns = columns }
                            .onChange(of: columns) { _, c in focus.columns = c }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("ReplayNES")
            .searchable(text: $query, prompt: Text(L("Search games")))
            .onChange(of: query) { _, q in focus.query = q }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if model.status.hasSession {
                        Button { model.hideLibraryScreen() } label: { Label(L("Back to Game"), systemImage: "chevron.left") }
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    sortMenu
                    Button { importing = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel(L("Import ROMs"))
                        .accessibilityIdentifier("importROMs")
                    Menu {
                        Button { model.quickMenu.open(at: .display) } label: { Label(String(localized: "Settings"), systemImage: "gearshape") }
                        Button { model.showUnlocks = true } label: { Label(L("Unlocks"), systemImage: "lock.open") }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.nesROM, .data], allowsMultipleSelection: true) { result in
                if case .success(let urls) = result { model.importROMs(urls) }
            }
            .sheet(item: $projectsOf) { rom in ProjectsSheet(rom: rom) }
            .refreshable { library.refresh() }
        }
        .preferredColorScheme(.dark)
        .overlay {
            if model.quickMenu.isOpen {
                TouchQuickMenu(menu: model.quickMenu, monitor: model.input.controllerMonitor).ignoresSafeArea()
            }
        }
    }

    // MARK: Continue card

    @ViewBuilder
    private var hero: some View {
        if model.status.hasSession {
            HeroCard(title: String(localized: "Resume"), subtitle: URL(fileURLWithPath: model.status.romPath).deletingPathExtension().lastPathComponent,
                     detail: Engine.timecode(forFrame: model.status.frame), image: nil, focused: focus.index < 0 && !model.controllers.isEmpty) {
                model.hideLibraryScreen()
            }
        } else if let r = model.pendingResume {
            HeroCard(title: L("Continue"), subtitle: URL(fileURLWithPath: r.romPath).deletingPathExtension().lastPathComponent,
                     detail: (r.isTemp ? L("Temporary session") : URL(fileURLWithPath: r.projectPath).deletingPathExtension().lastPathComponent)
                        + " · " + Engine.timecode(forFrame: r.frame ?? 0),
                     image: model.continueThumbnail(), focused: focus.index < 0 && !model.controllers.isEmpty) {
                model.continueLast()
            }
        }
    }

    // MARK: sort / filter

    private var sortMenu: some View {
        Menu {
            Picker(L("Sort"), selection: Binding(get: { library.sort.rawValue }, set: { library.sort = rnf_library_sort(rawValue: $0) })) {
                ForEach(LibraryCatalog.sorts, id: \.rawValue) { s in Text(LibraryCatalog.name(s)).tag(s.rawValue) }
            }
            Picker(L("Show"), selection: Binding(get: { library.filter.rawValue }, set: { library.filter = rnf_library_filter(rawValue: $0) })) {
                ForEach(LibraryCatalog.filters, id: \.rawValue) { f in Text(LibraryCatalog.name(f)).tag(f.rawValue) }
            }
        } label: { Image(systemName: "arrow.up.arrow.down") }
    }

    @ViewBuilder
    private func cardMenu(_ rom: LibraryROM) -> some View {
        Button { model.playFromLibrary(rom) } label: {
            Label(entitlements.isUnlocked(.recording) ? L("Play (New Recording)") : L("Play"), systemImage: "play.fill")
        }
        if !library.projects(for: rom).isEmpty {
            Button { projectsOf = rom } label: { Label(L("Recordings…"), systemImage: "square.stack.3d.up") }
        }
        Button { library.toggleFavorite(rom) } label: {
            library.isFavorite(rom) ? Label(L("Remove from Favorites"), systemImage: "star.slash") : Label(L("Add to Favorites"), systemImage: "star")
        }
    }

    // MARK: empty library

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("No games yet")).font(.title3.weight(.semibold))
            Text(L("Put your .nes ROM files into Files › On My iPhone › ReplayNES › ROM (from a Mac: Finder › your iPhone › Files › ReplayNES), or import them here."))
                .font(.subheadline).foregroundStyle(.secondary)
            HStack {
                Button { importing = true } label: { Label(L("Import ROMs"), systemImage: "square.and.arrow.down") }
                    .buttonStyle(.borderedProminent)
                Button { addTestCartridge() } label: { Label(L("Add Test Cartridge"), systemImage: "hammer") }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("addTestCartridge")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.06)))
    }

    /// The ReplayNES Test Cartridge (tools/testcart, CC0; for trying the app without ROMs).
    private func addTestCartridge() {
        guard library.ensureFolders() else { return }
        let url = library.paths.roms.appendingPathComponent("ReplayNES Test Cartridge.nes")
        do { try Engine.writeTestCartridge(to: url) } catch { model.showError(L("Add Test Cartridge"), error.localizedDescription); return }
        library.refresh()
    }
}

struct HeroCard: View {
    let title: String
    let subtitle: String
    let detail: String
    let image: CGImage?
    let focused: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Group {
                    if let image {
                        Image(decorative: image, scale: 1).resizable().interpolation(.none)
                    } else {
                        ZStack { Color.white.opacity(0.08); Image(systemName: "play.fill").font(.title) }
                    }
                }
                .aspectRatio(256.0 / 224.0, contentMode: .fit)
                .frame(height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline).foregroundStyle(Color(red: 1, green: 0.35, blue: 0.35))
                    Text(subtitle).font(.title3.weight(.semibold)).lineLimit(2)
                    Text(detail).font(.caption.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(focused ? Color.white : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }
}

struct GameCard: View {
    let rom: LibraryROM
    let favorite: Bool
    let projects: Int
    let focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let img = ThumbnailStore.image(romSHA: rom.sha256) {
                        Image(decorative: img, scale: 1).resizable().interpolation(.none)
                    } else {
                        ZStack {
                            LinearGradient(colors: [Color(hue: hue, saturation: 0.5, brightness: 0.45), Color(hue: hue, saturation: 0.6, brightness: 0.18)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                            Text(rom.title).font(.system(size: 15, weight: .bold)).multilineTextAlignment(.center).padding(8)
                                .foregroundStyle(.white.opacity(0.9)).lineLimit(3).minimumScaleFactor(0.7)
                        }
                    }
                }
                .aspectRatio(256.0 / 224.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                HStack(spacing: 4) {
                    if projects > 0 {
                        Label("\(projects)", systemImage: "square.stack.3d.up.fill").font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 5).padding(.vertical, 2).background(.black.opacity(0.6), in: Capsule())
                    }
                    if favorite { Image(systemName: "star.fill").foregroundStyle(.yellow).padding(4).background(.black.opacity(0.5), in: Circle()) }
                }
                .padding(5)
            }
            Text(rom.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
            Text(rom.byline.isEmpty ? rom.name : rom.byline).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 12).fill(focused ? Color.white.opacity(0.14) : .clear))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(focused ? Color.white : .clear, lineWidth: 2))
        .contentShape(Rectangle())
    }

    private var hue: Double { Double(abs(rom.name.hashValue % 360)) / 360 }
}

/// The projects (kept recordings) of one game.
struct ProjectsSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let rom: LibraryROM

    var body: some View {
        NavigationStack {
            List(model.library.projects(for: rom)) { p in
                Button {
                    dismiss()
                    model.continueProject(p.url)
                } label: {
                    HStack(spacing: 12) {
                        if let img = ThumbnailStore.image(project: p.url.path) {
                            Image(decorative: img, scale: 1).resizable().interpolation(.none).aspectRatio(256.0 / 224.0, contentMode: .fit)
                                .frame(height: 48).clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        VStack(alignment: .leading) {
                            Text(p.name).lineLimit(1)
                            Text(p.modified.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle(rom.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(String(localized: "Done")) { dismiss() } } }
        }
    }
}
