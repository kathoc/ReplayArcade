// Copying ROMs into the library's ROM folder (document picker, "Open in ReplayNES" / Files ›
// Share › ReplayNES with one or many files, AirDrop).
// SPDX-License-Identifier: GPL-2.0-or-later
import CryptoKit
import Foundation

enum ROMImport {
    enum Failure: Error, LocalizedError {
        case notAROM
        var errorDescription: String? { L("Not an NES ROM (.nes)") }
    }

    /// Larger files are not ROMs: the biggest iNES images are a few MB; another product's ROM sets
    /// (ReplayArcade's zip files) stay well under 64 MB.
    static let maxROMSize = RNProduct.romExtensions == ["nes"] ? 16 << 20 : 64 << 20

    /// Copies `src` into `romDir`. The same file already there (same size and bytes) is reused;
    /// another file with the same name gets " 2", " 3"... Returns the library file.
    static func copy(_ src: URL, into romDir: URL, fileManager fm: FileManager = .default) throws -> URL {
        guard RNProduct.isROMFile(src) else { throw Failure.notAROM }
        try fm.createDirectory(at: romDir, withIntermediateDirectories: true)
        let base = src.deletingPathExtension().lastPathComponent
        let ext = src.pathExtension
        var n = 1
        while true {
            let name = n == 1 ? "\(base).\(ext)" : "\(base) \(n).\(ext)"
            let dest = romDir.appendingPathComponent(name)
            if dest.standardizedFileURL == src.standardizedFileURL { return dest }
            if !fm.fileExists(atPath: dest.path) {
                try fm.copyItem(at: src, to: dest)
                return dest
            }
            if fm.contentsEqual(atPath: dest.path, andPath: src.path) { return dest }
            n += 1
        }
    }

    /// .nes files dropped next to ROM/ (Finder's file sharing puts them into the top level of
    /// On My iPhone › ReplayNES) are moved into ROM/. Returns the moved files.
    @discardableResult
    static func adoptLooseROMs(root: URL, roms: URL, fileManager fm: FileManager = .default) -> [URL] {
        guard let items = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return [] }
        var out: [URL] = []
        for u in items where RNProduct.isROMFile(u) {
            guard let dest = try? copy(u, into: roms, fileManager: fm), dest.standardizedFileURL != u.standardizedFileURL else { continue }
            try? fm.removeItem(at: u)
            out.append(dest)
        }
        return out
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// A ROM file of its extension, within the size limit: an iNES / NES 2.0 image ("NES\u{1A}" +
    /// header) or a zip archive ("PK\u{3}\u{4}", another product's ROM sets; which sets the library
    /// lists is the product's ROM filter, rnf_set_rom_filter).
    static func looksLikeROM(_ data: Data, extension ext: String = "nes") -> Bool {
        let magic: [UInt8]
        switch ext.lowercased() {
        case "nes": magic = [0x4E, 0x45, 0x53, 0x1A]
        case "zip": magic = [0x50, 0x4B, 0x03, 0x04]
        default: return false
        }
        return data.count > 16 && data.count <= maxROMSize && data.prefix(4).elementsEqual(magic)
    }

    /// Imports a batch of files into `romDir` (blocking: call off the main thread; ROMImportQueue
    /// does). Each file is read with its security scope held and through a file coordinator
    /// (Files / iCloud Drive / other providers), checked (.nes + iNES header), de-duplicated by
    /// SHA-256 against the folder and the batch, and written under a free name ("Name 2.nes"...).
    /// Copies the system left in `inbox` (Documents/Inbox, "Open in" without open-in-place) are
    /// removed afterwards. Never throws: every file ends up in one bucket of the result.
    static func importBatch(_ urls: [URL], into romDir: URL, inbox: URL? = nil, fileManager fm: FileManager = .default) -> ROMImportResult {
        var result = ROMImportResult(requested: urls.count)
        do { try fm.createDirectory(at: romDir, withIntermediateDirectories: true) } catch {
            result.failed = urls.map { ($0.lastPathComponent, error.localizedDescription) }
            return result
        }
        let index = ROMFolderIndex(romDir: romDir, fileManager: fm)
        let romRoot = canonicalPath(romDir) + "/"
        for url in urls {
            let name = url.lastPathComponent
            guard RNProduct.isROMFile(url) else { result.invalid.append(name); continue }
            if canonicalPath(url).hasPrefix(romRoot) {
                // Already in the library (Files › ReplayNES › ROM › Share › ReplayNES).
                if fm.fileExists(atPath: url.path) { result.existing.append(url) } else { result.failed.append((name, "missing")) }
                continue
            }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let data: Data
            switch read(url, fileManager: fm) {
            case .success(let d): data = d
            case .failure(let e): result.failed.append((name, e.localizedDescription)); continue
            }
            guard looksLikeROM(data, extension: url.pathExtension) else { result.invalid.append(name); removeInboxCopy(url, inbox: inbox, fm); continue }
            let sha = sha256(data)
            if let same = index.file(sha256: sha, size: data.count) {
                result.existing.append(same)
                removeInboxCopy(url, inbox: inbox, fm)
                continue
            }
            do {
                let dest = try write(data, named: url.deletingPathExtension().lastPathComponent, ext: url.pathExtension, into: romDir, fileManager: fm)
                index.add(dest, sha256: sha, size: data.count)
                result.added.append(dest)
                removeInboxCopy(url, inbox: inbox, fm)
            } catch {
                result.failed.append((name, error.localizedDescription))
            }
        }
        return result
    }

    private static func read(_ url: URL, fileManager fm: FileManager) -> Result<Data, Error> {
        // Reject anything big before reading it (a selection may include videos, archives...).
        if let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size > maxROMSize {
            return .failure(Failure.notAROM)
        }
        var out: Result<Data, Error> = .failure(CocoaError(.fileReadUnknown))
        var coordError: NSError?
        // No file presenter: coordinating from this background queue cannot wait on the app itself.
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [.withoutChanges], error: &coordError) { u in
            out = Result { try Data(contentsOf: u, options: [.mappedIfSafe]) }
        }
        if let coordError { return .failure(coordError) }
        if case .success(let d) = out, d.count > maxROMSize { return .failure(Failure.notAROM) }
        return out
    }

    private static func write(_ data: Data, named base: String, ext: String, into romDir: URL, fileManager fm: FileManager) throws -> URL {
        let ext = ext.isEmpty ? (RNProduct.romExtensions.sorted().first ?? "rom") : ext
        var n = 1
        while true {
            let dest = romDir.appendingPathComponent(n == 1 ? "\(base).\(ext)" : "\(base) \(n).\(ext)")
            if !fm.fileExists(atPath: dest.path) {
                do {
                    try data.write(to: dest, options: [.withoutOverwriting])
                    return dest
                } catch CocoaError.fileWriteFileExists {
                    // Taken in the meantime: next name.
                }
            }
            n += 1
            if n > 10_000 { throw CocoaError(.fileWriteFileExists) }
        }
    }

    /// /var and /private/var are the same folder on iOS.
    static func canonicalPath(_ url: URL) -> String { url.resolvingSymlinksInPath().standardizedFileURL.path }

    private static func removeInboxCopy(_ url: URL, inbox: URL?, _ fm: FileManager) {
        guard let inbox, canonicalPath(url).hasPrefix(canonicalPath(inbox) + "/") else { return }
        try? fm.removeItem(at: url)
    }
}

/// What a batch import did with each file.
struct ROMImportResult {
    var requested = 0
    /// Copied into the ROM folder.
    var added: [URL] = []
    /// Already in the library (same SHA-256, or the file is in the ROM folder): the library file.
    var existing: [URL] = []
    /// Not .nes, not an iNES image, or too large.
    var invalid: [String] = []
    /// Unreadable / not writable: (file name, reason).
    var failed: [(String, String)] = []

    var skipped: Int { invalid.count + failed.count }

    /// The toast after an import ("5 本のROMを追加しました・1 本は追加済み・1 件はスキップ").
    var summary: String {
        var parts = [added.isEmpty ? L("No ROMs added") : L("Added %lld ROM(s)", Int64(added.count))]
        if !existing.isEmpty { parts.append(L("%lld already in the library", Int64(existing.count))) }
        if skipped > 0 { parts.append(L("%lld skipped (not an NES ROM or unreadable)", Int64(skipped))) }
        return parts.joined(separator: " · ")
    }
}

/// SHA-256s of the ROM folder, computed only for files whose size matches an incoming ROM.
final class ROMFolderIndex {
    private var bySize: [Int: [URL]] = [:]
    private var hashes: [URL: String] = [:]
    private let fm: FileManager

    init(romDir: URL, fileManager fm: FileManager = .default) {
        self.fm = fm
        let keys: [URLResourceKey] = [.fileSizeKey, .isRegularFileKey]
        guard let e = fm.enumerator(at: romDir, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { return }
        for case let u as URL in e where RNProduct.isROMFile(u) {
            guard let v = try? u.resourceValues(forKeys: Set(keys)), v.isRegularFile == true, let size = v.fileSize else { continue }
            bySize[size, default: []].append(u)
        }
    }

    func file(sha256: String, size: Int) -> URL? {
        for u in bySize[size] ?? [] {
            if hashes[u] == nil, let d = try? Data(contentsOf: u, options: [.mappedIfSafe]) { hashes[u] = ROMImport.sha256(d) }
            if hashes[u] == sha256 { return u }
        }
        return nil
    }

    func add(_ url: URL, sha256: String, size: Int) {
        bySize[size, default: []].append(url)
        hashes[url] = sha256
    }
}

/// Imports off the main thread, one batch at a time. URLs that arrive close together (one
/// multi-item "Open in", or the system delivering them as successive events) are merged into one
/// batch: one library refresh and one toast at the end, on `deliver` (main).
final class ROMImportQueue {
    struct Batch {
        var urls: [URL] = []
        /// From another app (Open in / Share), not the in-app picker.
        var fromOtherApp = false
    }

    private let work: DispatchQueue
    private let deliver: DispatchQueue
    private let coalesce: TimeInterval
    private let lock = NSLock()
    private var pending = Batch()
    private var flushItem: DispatchWorkItem?
    private var inFlight = 0

    /// Called on `deliver` when a batch is about to be processed (its size) and when it is done.
    var onStart: ((Int) -> Void)?
    var onFinish: ((ROMImportResult, Batch) -> Void)?
    /// Where the ROMs go (read on the work queue).
    var romDir: () -> URL
    var inbox: () -> URL?

    init(romDir: @escaping () -> URL, inbox: @escaping () -> URL? = { nil }, coalesce: TimeInterval = 0.4,
         work: DispatchQueue = DispatchQueue(label: "replaynes.import", qos: .userInitiated), deliver: DispatchQueue = .main) {
        self.romDir = romDir
        self.inbox = inbox
        self.coalesce = coalesce
        self.work = work
        self.deliver = deliver
    }

    /// True while a batch waits or runs.
    var busy: Bool { lock.lock(); defer { lock.unlock() }; return inFlight > 0 || !pending.urls.isEmpty }

    func enqueue(_ urls: [URL], fromOtherApp: Bool) {
        guard !urls.isEmpty else { return }
        lock.lock()
        pending.urls += urls
        pending.fromOtherApp = pending.fromOtherApp || fromOtherApp
        flushItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.flush() }
        flushItem = item
        lock.unlock()
        work.asyncAfter(deadline: .now() + coalesce, execute: item)
    }

    private func flush() {
        lock.lock()
        let batch = pending
        pending = Batch()
        flushItem = nil
        if !batch.urls.isEmpty { inFlight += 1 }
        lock.unlock()
        guard !batch.urls.isEmpty else { return }
        // Stable order (a multi-item open arrives as a Set), each file once.
        var seen = Set<String>()
        let urls = batch.urls.filter { seen.insert(ROMImport.canonicalPath($0)).inserted }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        deliver.async { [weak self] in self?.onStart?(urls.count) }
        let result = ROMImport.importBatch(urls, into: romDir(), inbox: inbox())
        var b = batch
        b.urls = urls
        deliver.async { [weak self] in
            guard let self else { return }
            self.lock.lock(); self.inFlight -= 1; self.lock.unlock()
            self.onFinish?(result, b)
        }
    }
}
