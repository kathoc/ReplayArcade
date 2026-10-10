// Launch arguments for simulator checks and measurements (Xcode scheme or `simctl launch`):
//   -autoplayTestROM YES      write the engine's test ROM into ROM/ and play it (temporary session)
//   -autoplayROM <name.nes>   play that file of ROM/
//   -pauseAfter <s>           pause after s seconds (the seek bar)
//   -continueLast YES         press the library's Continue card at 1 s (resume check)
//   -openMenu <page>          open the Quick Menu at a page (top, retry, practice, display, ...) after 2 s
//   -debugUnlockAll NO        free mode (the prototype switch off)
//   -pacingProbe <s>          after s seconds of play write Library/Caches/pacing.json (PacingProbe)
//   -holdTouch <button>       press an on-screen button at 1 s (e.g. r = pause) to check touch input
//   -logTouch YES             log every on-screen press / release edge ("ReplayNES touch: a+ b-")
//   -logTouchEvents YES       log every UITouch the on-screen gamepad receives
//   -orientation landscape    rotate the window (screenshots of the landscape layout)
//   -rotateCycle <s>          rotate portrait → landscape right → portrait → landscape left ... every s seconds
//   -resetLibraryForTests YES empty Documents/ROM and Documents/Projects and forget the temporary session
//   -importTestBatch YES      at 1 s, open 7 files at once like a multi-item Share › ReplayNES: 5 distinct
//                             test ROMs (one name twice, from two folders), a duplicate, a non-ROM
// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import UIKit

enum TestHooks {
    /// Before the app model starts.
    static func prepare() {
        guard UserDefaults.standard.bool(forKey: "resetLibraryForTests") else { return }
        let docs = LibraryPaths.documents
        for dir in [docs.roms, docs.projects] { try? FileManager.default.removeItem(at: dir) }
    }

    static func run(_ m: AppModel) {
        let d = UserDefaults.standard
        if d.bool(forKey: "resetLibraryForTests") { m.discardTemporarySession() }
        if d.bool(forKey: "importTestBatch") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                do { m.open(urls: try importTestBatch()) } catch { NSLog("ReplayNES: importTestBatch: \(error)") }
            }
        }
        var rom: URL?
        if d.bool(forKey: "autoplayTestROM") {
            m.library.ensureFolders()
            let url = m.library.paths.roms.appendingPathComponent("ReplayNES Test.nes")
            if !FileManager.default.fileExists(atPath: url.path) { try? Engine.writeTestROM(to: url) }
            rom = url
        } else if let name = d.string(forKey: "autoplayROM") {
            rom = m.library.paths.roms.appendingPathComponent(name)
        }
        if let rom {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                m.discardTemporarySession()
                let entry = LibraryROM(url: rom, name: rom.deletingPathExtension().lastPathComponent, relativePath: rom.lastPathComponent,
                                       size: 0, modified: Date(), sha256: nil, game: nil)
                m.playFromLibrary(entry, autoplay: true)
            }
        }
        if d.bool(forKey: "continueLast") { DispatchQueue.main.asyncAfter(deadline: .now() + 1) { m.continueLast() } }
        let pause = d.double(forKey: "pauseAfter")
        if pause > 0 { DispatchQueue.main.asyncAfter(deadline: .now() + pause) { m.setPaused(true) } }
        if let page = d.string(forKey: "openMenu"), let p = QMPage(rawValue: page) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { m.quickMenu.open(at: p) }
        }
        let probe = d.double(forKey: "pacingProbe")
        if probe > 0 { PacingProbe.shared.start(after: probe) }
        if let b = d.string(forKey: "holdTouch"), let button = TouchButton(rawValue: b) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { m.touchButtons(pressed: [button], released: []) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.3) { m.touchButtons(pressed: [], released: [button]) }
        }
        if d.string(forKey: "orientation") == "landscape" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { rotate(to: .landscapeRight) }
        }
        let cycle = d.double(forKey: "rotateCycle")
        if cycle > 0 { rotateCycle(every: cycle, step: 0) }
    }

    /// Files outside the library as another app would hand them over.
    static func importTestBatch() throws -> [URL] {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("ImportBatch-\(UUID().uuidString)", isDirectory: true)
        let other = dir.appendingPathComponent("Other", isDirectory: true)
        try fm.createDirectory(at: other, withIntermediateDirectories: true)
        let base = dir.appendingPathComponent("base.tmp")
        try Engine.writeTestROM(to: base)
        let rom = try Data(contentsOf: base)
        try fm.removeItem(at: base)
        var urls: [URL] = []
        let names = ["Alpha", "Bravo", "Charlie", "Delta"]
        for (i, name) in names.enumerated() {
            var d = rom
            d[16 + 0x2000 + i] &+= UInt8(1 + i)
            let u = dir.appendingPathComponent("\(name).nes")
            try d.write(to: u)
            urls.append(u)
        }
        // Same name as Alpha, other contents (-> "Alpha 2.nes").
        var e = rom
        e[16 + 0x2000 + 9] &+= 7
        let sameName = other.appendingPathComponent("Alpha.nes")
        try e.write(to: sameName)
        urls.append(sameName)
        // A duplicate of Bravo under another name, and a file that is no ROM.
        let dup = other.appendingPathComponent("Bravo (copy).nes")
        try fm.copyItem(at: urls[1], to: dup)
        urls.append(dup)
        let junk = dir.appendingPathComponent("readme.nes")
        try Data("not a ROM".utf8).write(to: junk)
        urls.append(junk)
        return urls
    }

    private static func rotate(to o: UIInterfaceOrientationMask) {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        scene?.requestGeometryUpdate(.iOS(interfaceOrientations: o)) { NSLog("ReplayNES: rotate: \($0)") }
    }

    /// -rotateCycle <s>: portrait, landscape right, portrait, landscape left, ... every s seconds
    /// (rotation checks: the layout must be the same after any number of turns).
    private static func rotateCycle(every s: Double, step: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + s) {
            let seq: [UIInterfaceOrientationMask] = [.landscapeRight, .portrait, .landscapeLeft, .portrait]
            let o = seq[step % seq.count]
            NSLog("ReplayNES: rotateCycle step \(step + 1): \(o == .portrait ? "portrait" : o == .landscapeLeft ? "landscapeLeft" : "landscapeRight")")
            rotate(to: o)
            rotateCycle(every: s, step: step + 1)
        }
    }
}

/// Basic pacing check: the latency meter's counters over a window of play, written as JSON.
final class PacingProbe {
    static let shared = PacingProbe()
    private(set) var active = false
    private var first: LatencyMeter.Snapshot?
    private var startTime = 0.0
    private var duration = 0.0

    func start(after seconds: Double) {
        active = true
        duration = seconds
        startTime = ProcessInfo.processInfo.systemUptime + 2   // let the game boot first
    }

    /// Main thread, 4x a second while active.
    func observe(_ s: LatencyMeter.Snapshot) {
        guard active else { return }
        let t = ProcessInfo.processInfo.systemUptime
        if t < startTime { return }
        if first == nil { first = s; return }
        guard t >= startTime + duration, let a = first else { return }
        active = false
        let out: [String: Any] = [
            "seconds": duration,
            "pacing": s.pacing,
            "refreshHz": s.refreshHz,
            "emulatedFPS": s.emulatedFPS,
            "presentedFPS": s.presentedFPS,
            "presents": s.presentCount - a.presentCount,
            "presentHitches": s.presentHitches - a.presentHitches,
            "offCadence": s.offCadence - a.offCadence,
            "skippedFrames": s.skippedFrames - a.skippedFrames,
            "droppedFrames": s.droppedFrames - a.droppedFrames,
            "missedRefreshes": s.missedRefreshes - a.missedRefreshes,
            "repeatPresents": s.repeatPresents - a.repeatPresents,
            "foreignCallbacks": s.foreignCallbacks - a.foreignCallbacks,
            "inputLeadMs": s.inputLeadMs,
            "sampleToPresentMs": s.sampleToPresentMs,
            "stepMs": s.stepMs,
            "audioUnderruns": s.audioUnderruns - a.audioUnderruns,
            "audioFillMs": s.audioFillMs,
            "audioRatio": s.audioRatio,
            "audioSession": AppModel.shared.audioSession.describe,
            "audioRunning": AppModel.shared.emu.audio.running,
            "audioPulledSamples": AppModel.shared.emu.audio.stats().pulled_samples,
            "layerPixels": s.layerPixels,
        ]
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("pacing.json")
        if let data = try? JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url)
            NSLog("ReplayNES pacing: \(String(decoding: data, as: UTF8.self))")
        }
    }
}
