// The hand-over folder between the Share Extension ("Add to ReplayNES", apps/ios/ShareExtension)
// and the app: a folder in the App Group container both can write. iOS hands an app only the first
// file of a multi-item Share › <app>, so a multi-file share goes through the extension: it copies
// every shared file into a batch folder here and the app imports the batch (ROMImportQueue) when
// it becomes active, or right away on the Darwin notification if it is running.
// Layout: ShareInbox/.incoming-<uuid>/<n>/<file> while the extension copies; renamed to
// ShareInbox/<uuid> when complete (atomic); the app claims it by renaming it to
// ShareInbox/.importing-<uuid> and removes it after the import.
// Compiled into the app, the extension and the logic tests.
// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation

enum ShareInbox {
    /// Info.plist key with the App Group id (build setting RN_APP_GROUP: group.<app bundle id>).
    static let infoKey = "RNAppGroup"
    /// Posted by the extension after a batch is committed.
    static let darwinNotification = "io.github.replaynes.share-inbox"
    /// Single files larger than this are not copied (the biggest NES ROMs are a few MB; a share may
    /// include videos). Packages (.nesrec projects) are copied whatever their size.
    static let maxFileSize = 16 << 20

    static var groupID: String? {
        guard let s = Bundle.main.object(forInfoDictionaryKey: infoKey) as? String, !s.isEmpty, !s.contains("$(") else { return nil }
        return s
    }

    /// ShareInbox in the App Group container (nil without the App Group entitlement).
    static func standardRoot(fileManager fm: FileManager = .default) -> URL? {
        guard let id = groupID, let c = fm.containerURL(forSecurityApplicationGroupIdentifier: id) else { return nil }
        return c.appendingPathComponent("ShareInbox", isDirectory: true)
    }

    // MARK: extension side

    /// A new staging folder for one share.
    static func beginBatch(root: URL, fileManager fm: FileManager = .default) throws -> URL {
        let dir = root.appendingPathComponent(".incoming-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Copies one shared item (file or package) into the batch as item `index`, keeping its name.
    @discardableResult
    static func add(_ src: URL, name: String? = nil, index: Int, to batch: URL, fileManager fm: FileManager = .default) throws -> URL {
        let slot = batch.appendingPathComponent(String(index), isDirectory: true)
        try fm.createDirectory(at: slot, withIntermediateDirectories: true)
        let dest = slot.appendingPathComponent(name ?? src.lastPathComponent)
        try fm.copyItem(at: src, to: dest)
        return dest
    }

    /// The batch is complete: visible to the app.
    static func commit(_ batch: URL, fileManager fm: FileManager = .default) throws {
        let name = batch.lastPathComponent.replacingOccurrences(of: ".incoming-", with: "")
        try fm.moveItem(at: batch, to: batch.deletingLastPathComponent().appendingPathComponent(name, isDirectory: true))
    }

    static func notifyApp() {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                             CFNotificationName(darwinNotification as CFString), nil, nil, true)
    }

    // MARK: app side

    /// Claims every committed batch (one rename each, so a second drain never sees it again) and
    /// returns their items in share order. Stale staging / claimed folders (an extension or an
    /// import that was killed) older than `staleAfter` are removed.
    static func claim(root: URL, fileManager fm: FileManager = .default, staleAfter: TimeInterval = 24 * 3600) -> [URL] {
        guard let dirs = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey], options: []) else { return [] }
        var out: [URL] = []
        for d in dirs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let n = d.lastPathComponent
            if n.hasPrefix(".") {
                let date = (try? d.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                if (n.hasPrefix(".incoming-") || n.hasPrefix(".importing-")) && Date().timeIntervalSince(date) > staleAfter {
                    try? fm.removeItem(at: d)
                }
                continue
            }
            let claimed = root.appendingPathComponent(".importing-" + n, isDirectory: true)
            guard (try? fm.moveItem(at: d, to: claimed)) != nil else { continue }
            let slots = ((try? fm.contentsOfDirectory(at: claimed, includingPropertiesForKeys: nil)) ?? [])
                .sorted { (Int($0.lastPathComponent) ?? 0) < (Int($1.lastPathComponent) ?? 0) }
            for s in slots {
                out += ((try? fm.contentsOfDirectory(at: s, includingPropertiesForKeys: nil)) ?? []).filter { !$0.lastPathComponent.hasPrefix(".") }
            }
        }
        return out
    }

    /// The claimed batch folder an item of `claim` is in (nil for other URLs).
    static func batchFolder(of item: URL, root: URL) -> URL? {
        let r = ROMImportPath.canonical(root) + "/"
        let batch = item.deletingLastPathComponent().deletingLastPathComponent()
        guard ROMImportPath.canonical(batch).hasPrefix(r), batch.lastPathComponent.hasPrefix(".importing-") else { return nil }
        return batch
    }

    /// Removes the claimed batch folders of `items` (after the import).
    static func finish(_ items: [URL], root: URL, fileManager fm: FileManager = .default) {
        for b in Set(items.compactMap { batchFolder(of: $0, root: root) }) { try? fm.removeItem(at: b) }
    }
}

/// /var and /private/var are the same folder on iOS.
enum ROMImportPath {
    static func canonical(_ url: URL) -> String { url.resolvingSymlinksInPath().standardizedFileURL.path }
}
