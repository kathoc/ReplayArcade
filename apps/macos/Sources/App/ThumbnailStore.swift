// Library thumbnails: the picture of the last session of each project and each ROM (by SHA-256),
// small PNGs (256x224) in <session folder>/Thumbnails. Written off the main thread when the app
// goes to the background, quits, closes a game or shows the library; read (and cached) by the
// library screen. Only where sessions are persisted (not in scripted runs without --session-root).
// SPDX-License-Identifier: GPL-2.0-or-later
import AppKit
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

enum ThumbnailStore {
    /// Set once at launch (AppModel.setupSessionPersistence).
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

    /// `pixels`: one 256x240 BGRA frame. The overscan rows are cropped.
    static func save(pixels: [UInt32], project: String?, romSHA: String?, on queue: DispatchQueue, done: @escaping () -> Void) {
        guard let dir else { return }
        let targets = [project.flatMap { url(project: $0) }, romSHA.flatMap { url(romSHA: $0) }].compactMap { $0 }
        guard !targets.isEmpty else { return }
        queue.async {
            let w = Int(RN_VIDEO_WIDTH), h = Int(RN_VIDEO_HEIGHT), crop = 8
            let data = pixels.withUnsafeBufferPointer { Data(buffer: $0) }
            guard let provider = CGDataProvider(data: data as CFData),
                  let full = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                                     space: CGColorSpaceCreateDeviceRGB(),
                                     bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                                     provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
                  let img = full.cropping(to: CGRect(x: 0, y: crop, width: w, height: h - 2 * crop)) else { return }
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
    /// docs/design/UI_REDESIGN.md "A picture for every ROM".
    static let romPictureFrame = 300
    private static var asked = Set<String>()  // main thread
    private static let pictureQueue = DispatchQueue(label: "replaynes.rom-picture", qos: .utility)
    /// The ROMs whose picture could not be made (rnf_picture_ledger; pictureQueue only): a ROM that ended the
    /// app twice while its picture was being made, or failed, is not run again (the app cannot start another
    /// process to make it on iPhone: docs/plans/2026-11-22-library-pictures-robust.md).
    private static var ledger: OpaquePointer?
    private static func pictureLedger() -> OpaquePointer? {
        if ledger == nil, let d = dir { ledger = rnf_picture_ledger_open(d.path) }
        return ledger
    }
    static func requestRomPicture(path: String, sha: String?, done: @escaping () -> Void) {
        guard dir != nil, let sha, !sha.isEmpty, image(romSHA: sha) == nil, asked.insert(sha).inserted else { return }
        pictureQueue.async {
            let ledger = pictureLedger()
            if rnf_picture_ledger_skipped(ledger, path) != 0 { return }  // its card keeps the name tile
            rnf_picture_ledger_begin(ledger, path)
            var s: OpaquePointer?
            guard rn_session_new(path, nil, nil, &s) == RN_OK, let s else {
                rnf_picture_ledger_end(ledger, path, 0, "the engine cannot open it")
                return
            }
            defer { rn_session_close(s) }
            for _ in 0..<romPictureFrame {
                if rn_step(s, 0, 0, 0, nil) != RN_OK {
                    rnf_picture_ledger_end(ledger, path, 0, "a frame failed")
                    return
                }
            }
            guard let v = rn_video(s) else {
                rnf_picture_ledger_end(ledger, path, 0, "no picture")
                return
            }
            rnf_picture_ledger_end(ledger, path, 1, nil)
            let px = Array(UnsafeBufferPointer(start: v, count: Int(RN_VIDEO_WIDTH) * Int(RN_VIDEO_HEIGHT)))
            save(pixels: px, project: nil, romSHA: sha, on: pictureQueue, done: done)
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
