// The Share Extension → app hand-over folder (Sources/Shared/ShareInbox.swift) and its import.
// SPDX-License-Identifier: GPL-2.0-or-later
import XCTest

final class ShareInboxTests: XCTestCase {
    private var root: URL!
    private var src: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        let base = fm.temporaryDirectory.appendingPathComponent("ShareInboxTests-\(UUID().uuidString)", isDirectory: true)
        root = base.appendingPathComponent("ShareInbox", isDirectory: true)
        src = base.appendingPathComponent("src", isDirectory: true)
        try fm.createDirectory(at: src, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? fm.removeItem(at: root.deletingLastPathComponent()) }

    private func file(_ name: String, _ text: String = "x", in dir: URL? = nil) throws -> URL {
        let d = dir ?? src!
        try fm.createDirectory(at: d, withIntermediateDirectories: true)
        let u = d.appendingPathComponent(name)
        try Data(text.utf8).write(to: u)
        return u
    }

    /// Every item of a share arrives, in order, same names kept apart; a batch is claimed once.
    func testBatchCommitClaimFinish() throws {
        let batch = try ShareInbox.beginBatch(root: root)
        let names = ["Alpha.nes", "Bravo.nes", "Charlie.nes"]
        for (i, n) in names.enumerated() { try ShareInbox.add(try file(n), index: i, to: batch) }
        // The same name from another folder.
        try ShareInbox.add(try file("Alpha.nes", "other", in: src.appendingPathComponent("Other")), index: 3, to: batch)
        XCTAssertTrue(ShareInbox.claim(root: root).isEmpty, "not visible before commit")
        try ShareInbox.commit(batch)
        let items = ShareInbox.claim(root: root)
        XCTAssertEqual(items.map(\.lastPathComponent), names + ["Alpha.nes"])
        XCTAssertEqual(try String(contentsOf: items[3], encoding: .utf8), "other")
        XCTAssertTrue(ShareInbox.claim(root: root).isEmpty, "claimed once")
        XCTAssertNotNil(ShareInbox.batchFolder(of: items[0], root: root))
        XCTAssertNil(ShareInbox.batchFolder(of: src.appendingPathComponent("Alpha.nes"), root: root))
        ShareInbox.finish(items, root: root)
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: root.path), [], "the claimed batch is removed after the import")
    }

    /// Packages (.nesrec projects) are copied whole.
    func testPackageItem() throws {
        let pkg = src.appendingPathComponent("Game 2026.nesrec", isDirectory: true)
        _ = try file("manifest.json", "{}", in: pkg)
        let batch = try ShareInbox.beginBatch(root: root)
        try ShareInbox.add(pkg, index: 0, to: batch)
        try ShareInbox.commit(batch)
        let items = ShareInbox.claim(root: root)
        XCTAssertEqual(items.map(\.lastPathComponent), ["Game 2026.nesrec"])
        XCTAssertTrue(fm.fileExists(atPath: items[0].appendingPathComponent("manifest.json").path))
    }

    /// Two shares before the app looks: both batches, in commit order of their folders.
    func testSeveralBatchesAndStaleStaging() throws {
        for n in ["One.nes", "Two.nes"] {
            let b = try ShareInbox.beginBatch(root: root)
            try ShareInbox.add(try file(n), index: 0, to: b)
            try ShareInbox.commit(b)
        }
        let stale = try ShareInbox.beginBatch(root: root)
        try fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -3 * 86400)], ofItemAtPath: stale.path)
        let fresh = try ShareInbox.beginBatch(root: root)
        XCTAssertEqual(Set(ShareInbox.claim(root: root).map(\.lastPathComponent)), ["One.nes", "Two.nes"])
        XCTAssertFalse(fm.fileExists(atPath: stale.path), "a staging folder a killed extension left is cleaned up")
        XCTAssertTrue(fm.fileExists(atPath: fresh.path), "an extension still copying is left alone")
    }

    /// The claimed items through the ROM import: every ROM added, junk skipped.
    func testClaimedItemsImport() throws {
        let rom = src.appendingPathComponent("base.nes")
        try Engine.writeTestROM(to: rom)
        var data = try Data(contentsOf: rom)
        let batch = try ShareInbox.beginBatch(root: root)
        for i in 0..<5 {
            data[16 + 0x2000 + i] &+= 1
            let u = src.appendingPathComponent("Game \(i).nes")
            try data.write(to: u)
            try ShareInbox.add(u, index: i, to: batch)
        }
        try ShareInbox.add(try file("notes.txt"), index: 5, to: batch)
        try ShareInbox.commit(batch)
        let items = ShareInbox.claim(root: root)
        let romDir = root.deletingLastPathComponent().appendingPathComponent("ROM", isDirectory: true)
        let r = ROMImport.importBatch(items, into: romDir)
        XCTAssertEqual(r.added.count, 5)
        XCTAssertEqual(r.invalid, ["notes.txt"])
        ShareInbox.finish(items, root: root)
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: root.path), [])
    }
}
