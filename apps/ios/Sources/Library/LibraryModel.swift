// ROM library state (iOS port of apps/macos/Sources/App/LibraryModel.swift without AppKit):
// Documents/ROM and Documents/Projects (Files: On My iPhone › ReplayNES), background scanning
// (ROM hashes, game database, project manifests) and folder watching. Scanning, matching, naming,
// favourites / history / order all come from the shared core (Core/Library.swift). Main thread API.
// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation

extension LibraryPaths {
    /// iOS: the app's Documents folder itself, so ROM/ and Projects/ appear directly under
    /// On My iPhone › ReplayNES in the Files app (UIFileSharingEnabled).
    static var documents: LibraryPaths {
        LibraryPaths(root: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0])
    }
}

final class LibraryModel: ObservableObject {
    @Published private(set) var roms: [LibraryROM] = []
    @Published private(set) var projectsBySHA: [String: [LibraryProject]] = [:]
    @Published private(set) var scanning = false
    @Published private(set) var folderError: String?
    @Published private(set) var scanError: String?
    @Published private(set) var catalogRevision = 0

    private(set) var paths = LibraryPaths.documents
    let catalog = LibraryCatalog()
    private var arrangedKey = ""
    private var arrangedCache: [LibraryROM] = []
    private let queue = DispatchQueue(label: "replaynes.library", qos: .utility)
    private let hashes = ROMHashCache()
    private var watchers: [String: DispatchSourceFileSystemObject] = [:]
    private var pendingRefresh: DispatchWorkItem?
    private var scanGeneration = 0
    private var scanSerial = 0

    func setRoot(_ url: URL) { paths = LibraryPaths(root: url) }

    @discardableResult
    func start() -> String? {
        ensureFolders()
        refresh()
        return folderError
    }

    @discardableResult
    func ensureFolders() -> Bool {
        do {
            try paths.ensure()
            folderError = nil
            return true
        } catch {
            folderError = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            return false
        }
    }

    func setCatalogFile(_ url: URL) {
        catalog.load(url)
        catalogRevision += 1
    }

    func isFavorite(_ rom: LibraryROM) -> Bool { catalog.isFavorite(rom.sha256) }

    @discardableResult
    func toggleFavorite(_ rom: LibraryROM) -> Bool {
        let on = catalog.toggleFavorite(rom.sha256)
        catalogRevision += 1
        return on
    }

    func recordPlay(_ sha: String, start: Date, seconds: Double) {
        catalog.recordPlay(sha, start: start, seconds: seconds)
        catalogRevision += 1
    }

    var sort: rnf_library_sort {
        get { catalog.sort }
        set { catalog.sort = newValue; catalogRevision += 1 }
    }
    var filter: rnf_library_filter {
        get { catalog.filter }
        set { catalog.filter = newValue; catalogRevision += 1 }
    }

    func rom(sha256: String?) -> LibraryROM? {
        guard let sha256, !sha256.isEmpty else { return nil }
        return roms.first { $0.sha256 == sha256 }
    }

    func arranged(query: String) -> [LibraryROM] {
        let key = "\(roms.count)/\(roms.first?.id ?? "")/\(scanSerial)/\(catalogRevision)/\(String(cString: rnf_l10n_language()))/\(query)"
        if key != arrangedKey {
            arrangedCache = catalog.arrange(roms, query: query)
            arrangedKey = key
        }
        return arrangedCache
    }

    func projects(for rom: LibraryROM) -> [LibraryProject] {
        guard let sha = rom.sha256 else { return [] }
        return (projectsBySHA[sha] ?? []).sorted { $0.modified > $1.modified }
    }

    func refresh() {
        pendingRefresh?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.scanNow() }
        pendingRefresh = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func scanNow() {
        if folderError != nil { ensureFolders() }
        scanGeneration += 1
        let gen = scanGeneration
        let paths = self.paths, hashes = self.hashes
        scanning = true
        queue.async { [weak self] in
            ROMImport.adoptLooseROMs(root: paths.root, roms: paths.roms)
            var roms: [LibraryROM] = []
            var projects: [LibraryProject] = []
            var errors: [String] = []
            do { roms = try LibraryScanner.scanROMs(in: paths.roms) } catch {
                errors.append((error as? LocalizedError)?.errorDescription ?? "\(error)")
            }
            do { projects = try LibraryScanner.scanProjects(in: paths.projects) } catch {
                errors.append((error as? LocalizedError)?.errorDescription ?? "\(error)")
            }
            for i in roms.indices {
                roms[i].sha256 = hashes.sha256(of: roms[i])
                roms[i].game = hashes.game(of: roms[i])
            }
            let grouped = Dictionary(grouping: projects, by: { $0.romSHA256 })
            let subdirs = Set(roms.compactMap { r -> String? in
                let d = r.url.deletingLastPathComponent()
                return d.standardizedFileURL.path == paths.roms.standardizedFileURL.path ? nil : d.path
            })
            DispatchQueue.main.async {
                guard let self, gen == self.scanGeneration else { return }
                if self.roms != roms { self.roms = roms; self.scanSerial += 1 }
                if self.projectsBySHA != grouped { self.projectsBySHA = grouped }
                self.scanError = errors.isEmpty ? nil : errors.joined(separator: "\n")
                self.scanning = false
                self.updateWatchers([paths.root.path, paths.roms.path, paths.projects.path] + subdirs.sorted())
            }
        }
    }

    private func updateWatchers(_ dirs: [String]) {
        let wanted = Set(dirs)
        for (path, src) in watchers where !wanted.contains(path) {
            src.cancel()
            watchers[path] = nil
        }
        for path in dirs where watchers[path] == nil {
            let fd = open(path, O_EVTONLY)
            guard fd >= 0 else { continue }
            let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete, .link, .extend],
                                                                queue: .main)
            src.setEventHandler { [weak self] in self?.refresh() }
            src.setCancelHandler { close(fd) }
            src.resume()
            watchers[path] = src
        }
    }
}

/// Controller focus on the library screen: -1 = the Continue card, 0... = the game cards.
final class LibraryFocus: ObservableObject {
    static let shared = LibraryFocus()
    @Published var index = -1
    /// Cards per row (set by the grid for its width).
    var columns = 2
    var query = ""

    func handle(_ n: NavInput, model m: AppModel) {
        let games = m.library.arranged(query: query)
        let hasHero = m.pendingResume != nil || m.status.hasSession
        let lower = hasHero ? -1 : 0
        let upper = games.count - 1
        var i = min(max(index, lower), max(lower, upper))
        switch n {
        case .left: i = max(lower, i - 1)
        case .right: i = min(upper, i + 1)
        case .up: i = i < columns ? lower : i - columns
        case .down: i = i < 0 ? 0 : min(upper, i + columns)
        case .confirm:
            if i < 0 { m.continueLast() } else if games.indices.contains(i) { m.playFromLibrary(games[i]) }
        case .x:
            if games.indices.contains(i) { m.library.toggleFavorite(games[i]) }
        case .options:
            let sorts = LibraryCatalog.sorts
            if let k = sorts.firstIndex(of: m.library.sort) { m.library.sort = sorts[(k + 1) % sorts.count] }
        default: break
        }
        index = i
    }
}
