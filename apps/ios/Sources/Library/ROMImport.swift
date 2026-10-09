// Copying ROMs into the library's ROM folder (document picker, "Open in ReplayNES").
// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation

enum ROMImport {
    enum Failure: Error, LocalizedError {
        case notAROM
        var errorDescription: String? { L("Not an NES ROM (.nes)") }
    }

    /// Copies `src` into `romDir`. The same file already there (same size and bytes) is reused;
    /// another file with the same name gets " 2", " 3"... Returns the library file.
    static func copy(_ src: URL, into romDir: URL, fileManager fm: FileManager = .default) throws -> URL {
        guard src.pathExtension.lowercased() == "nes" else { throw Failure.notAROM }
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
        for u in items where u.pathExtension.lowercased() == "nes" {
            guard let dest = try? copy(u, into: roms, fileManager: fm), dest.standardizedFileURL != u.standardizedFileURL else { continue }
            try? fm.removeItem(at: u)
            out.append(dest)
        }
        return out
    }
}
