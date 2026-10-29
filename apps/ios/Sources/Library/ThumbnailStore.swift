// Library thumbnails (iOS copy of apps/macos/Sources/App/ThumbnailStore.swift, which imports
// AppKit): the picture of the last session of each project and each ROM (by SHA-256), small PNGs
// (256x224) in <session folder>/Thumbnails, written off the main thread, cached when read.
// SPDX-License-Identifier: GPL-2.0-or-later
import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ThumbnailStore {
    static var dir: URL?
    private static let cache = NSCache<NSString, CGImage>()

    static func url(project path: String) -> URL? {
        let h = SHA256.hash(data: Data(path.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
        return dir?.appendingPathComponent("p-\(h).png")
    }

    static func url(romSHA sha: String) -> URL? {
        guard !sha.isEmpty else { return nil }
        return dir?.appendingPathComponent("r-\(sha.prefix(24)).png")
    }

    static func save(_ picture: VideoPicture, project: String?, romSHA: String?, on queue: DispatchQueue, done: @escaping () -> Void) {
        guard let dir else { return }
        let targets = [project.flatMap { url(project: $0) }, romSHA.flatMap { url(romSHA: $0) }].compactMap { $0 }
        guard !targets.isEmpty else { return }
        queue.async {
            // The NES picture without its overscan rows (256x224); another core's picture whole and upright.
            guard let img = picture.cgImage(crop: picture.geometry.isNESPicture ? 8 : 0) else { return }
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            for u in targets {
                guard let dest = CGImageDestinationCreateWithURL(u as CFURL, UTType.png.identifier as CFString, 1, nil) else { continue }
                CGImageDestinationAddImage(dest, img, nil)
                if CGImageDestinationFinalize(dest) { cache.removeObject(forKey: u.path as NSString) }
            }
            DispatchQueue.main.async(execute: done)
        }
    }

    /// A ROM with no picture of its own: emulate it from power-on for `romPictureFrame` frames without
    /// input (in memory, no project; nothing written but the thumbnail) and save that picture as its
    /// thumbnail; `done` runs on the main thread when it is there. Asked by the library for the cards
    /// on screen; each ROM at most once per run (a ROM the engine cannot run keeps its name tile).
    /// docs/design/UI_REDESIGN.md "A picture for every ROM" (the same as macOS).
    static let romPictureFrame = Int(RN_PRODUCT_LIBRARY_PICTURE_FRAME)
    private static var asked = Set<String>()  // main thread
    private static let pictureQueue = DispatchQueue(label: "replaynes.rom-picture", qos: .utility)
    static func requestRomPicture(path: String, sha: String?, done: @escaping () -> Void) {
        guard dir != nil, let sha, !sha.isEmpty, image(romSHA: sha) == nil, asked.insert(sha).inserted else { return }
        pictureQueue.async {
            // A core whose sessions share one machine (ReplayArcade): only while the foreground is not
            // playing (ForegroundPlay), one ROM at a time (this serial queue).
            let shares = ForegroundPlay.sharesMachine(ForegroundPlay.defaultCore)
            if shares { ForegroundPlay.waitUntilIdle() }
            var s: OpaquePointer?
            guard rn_session_new(path, nil, nil, &s) == RN_OK, let s else { return }
            defer { rn_session_close(s) }
            for _ in 0..<romPictureFrame {
                if shares { ForegroundPlay.waitUntilIdle() }
                if rn_step(s, 0, 0, 0, nil) != RN_OK { return }
            }
            guard let picture = VideoPicture(session: s) else { return }
            save(picture, project: nil, romSHA: sha, on: pictureQueue, done: done)
        }
    }

    static func image(project path: String) -> CGImage? { load(url(project: path)) }
    static func image(romSHA sha: String?) -> CGImage? { sha.flatMap { load(url(romSHA: $0)) } }

    private static func load(_ u: URL?) -> CGImage? {
        guard let u else { return nil }
        if let c = cache.object(forKey: u.path as NSString) { return c }
        guard let src = CGImageSourceCreateWithURL(u as CFURL, nil), let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        cache.setObject(img, forKey: u.path as NSString)
        return img
    }
}
