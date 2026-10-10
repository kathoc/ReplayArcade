// ROM import into the library's ROM folder.
// SPDX-License-Identifier: GPL-2.0-or-later
import XCTest

final class ROMImportTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("rn-import-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    func testCopiesReusesAndRenames() throws {
        let src = tmp.appendingPathComponent("in/Game.nes")
        try FileManager.default.createDirectory(at: src.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Engine.writeTestROM(to: src)
        let roms = tmp.appendingPathComponent("ROM")
        let a = try ROMImport.copy(src, into: roms)
        XCTAssertEqual(a.lastPathComponent, "Game.nes")
        XCTAssertEqual(try ROMImport.copy(src, into: roms), a, "the same file is not copied twice")
        let other = tmp.appendingPathComponent("in2/Game.nes")
        try FileManager.default.createDirectory(at: other.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([0x4E, 0x45, 0x53, 0x1A, 1, 2, 3]).write(to: other)
        XCTAssertEqual(try ROMImport.copy(other, into: roms).lastPathComponent, "Game 2.nes")
        XCTAssertEqual(try ROMImport.copy(a, into: roms), a, "a file already in the folder stays")
        XCTAssertThrowsError(try ROMImport.copy(tmp.appendingPathComponent("x.txt"), into: roms))
    }

    func testLooseROMsAtTheTopLevelMoveIntoROM() throws {
        let roms = tmp.appendingPathComponent("ROM")
        try Engine.writeTestROM(to: tmp.appendingPathComponent("Dropped.nes"))
        try Data("x".utf8).write(to: tmp.appendingPathComponent("notes.txt"))
        let moved = ROMImport.adoptLooseROMs(root: tmp, roms: roms)
        XCTAssertEqual(moved.map(\.lastPathComponent), ["Dropped.nes"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: tmp.appendingPathComponent("Dropped.nes").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: roms.appendingPathComponent("Dropped.nes").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmp.appendingPathComponent("notes.txt").path))
    }

    // MARK: batch import (multi-file Open in / Share)

    private func rom(_ variant: Int, at url: URL) throws -> URL {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Engine.writeTestROM(to: url)
        if variant > 0 {
            var d = try Data(contentsOf: url)
            d[16 + 0x100 + variant] &+= UInt8(variant)
            try d.write(to: url)
        }
        return url
    }

    private func names(_ dir: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).sorted()
    }

    func testBatchImportsEveryFileDedupesAndSkipsJunk() throws {
        let src = tmp.appendingPathComponent("share")
        let roms = tmp.appendingPathComponent("Documents/ROM")
        var urls: [URL] = []
        for (i, n) in ["Alpha", "Bravo", "Charlie", "Delta", "Echo"].enumerated() {
            urls.append(try rom(i + 1, at: src.appendingPathComponent("\(n).nes")))
        }
        urls.append(try rom(9, at: src.appendingPathComponent("other/Alpha.nes")))           // same name, other ROM
        let dup = src.appendingPathComponent("other/Bravo copy.NES")
        try FileManager.default.copyItem(at: urls[1], to: dup)                             // same bytes as Bravo
        urls.append(dup)
        let text = src.appendingPathComponent("notes.nes")
        try Data("hello".utf8).write(to: text)                                             // .nes but no iNES header
        urls.append(text)
        let pdf = src.appendingPathComponent("manual.pdf")
        try Data("%PDF".utf8).write(to: pdf)
        urls.append(pdf)
        urls.append(src.appendingPathComponent("gone.nes"))                                // unreadable

        let r = ROMImport.importBatch(urls, into: roms)
        XCTAssertEqual(r.added.count, 6)
        XCTAssertEqual(r.existing.map(\.lastPathComponent), ["Bravo.nes"])
        XCTAssertEqual(r.invalid.sorted(), ["manual.pdf", "notes.nes"])
        XCTAssertEqual(r.failed.map(\.0), ["gone.nes"])
        XCTAssertEqual(r.skipped, 3)
        XCTAssertEqual(names(roms), ["Alpha 2.nes", "Alpha.nes", "Bravo.nes", "Charlie.nes", "Delta.nes", "Echo.nes"])
        XCTAssertEqual(try Data(contentsOf: roms.appendingPathComponent("Alpha 2.nes")), try Data(contentsOf: urls[5]))

        // Again: everything is already there (by SHA-256, whatever the name), nothing is copied.
        let again = ROMImport.importBatch(Array(urls.prefix(6)), into: roms)
        XCTAssertTrue(again.added.isEmpty)
        XCTAssertEqual(again.existing.count, 6)
        XCTAssertEqual(names(roms).count, 6)
    }

    func testBatchKeepsLibraryFilesAndCleansTheInbox() throws {
        let docs = tmp.appendingPathComponent("Documents")
        let roms = docs.appendingPathComponent("ROM")
        let inbox = docs.appendingPathComponent("Inbox")
        let inLibrary = try rom(1, at: roms.appendingPathComponent("Mine.nes"))
        let inboxCopy = try rom(2, at: inbox.appendingPathComponent("Shared.nes"))
        let inboxJunk = inbox.appendingPathComponent("junk.nes")
        try Data("x".utf8).write(to: inboxJunk)
        let r = ROMImport.importBatch([inLibrary, inboxCopy, inboxJunk], into: roms, inbox: inbox)
        XCTAssertEqual(r.existing, [inLibrary])
        XCTAssertEqual(r.added.map(\.lastPathComponent), ["Shared.nes"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: inboxCopy.path), "the Inbox copy is removed once imported")
        XCTAssertFalse(FileManager.default.fileExists(atPath: inboxJunk.path), "a rejected Inbox copy is removed too")
        XCTAssertEqual(names(roms), ["Mine.nes", "Shared.nes"])
    }

    func testSingleFileResultAndSummary() throws {
        let roms = tmp.appendingPathComponent("ROM")
        let one = ROMImport.importBatch([try rom(1, at: tmp.appendingPathComponent("in/One.nes"))], into: roms)
        XCTAssertEqual(one.added.map(\.lastPathComponent), ["One.nes"])
        XCTAssertEqual(one.summary, "Added 1 ROM(s)")
        let bad = ROMImport.importBatch([tmp.appendingPathComponent("in/One.txt")], into: roms)
        XCTAssertEqual(bad.summary, "No ROMs added · 1 skipped (not an NES ROM or unreadable)")
        var mixed = ROMImportResult(requested: 7)
        mixed.added = Array(repeating: roms, count: 5)
        mixed.existing = [roms]
        mixed.invalid = ["x"]
        XCTAssertEqual(mixed.summary, "Added 5 ROM(s) · 1 already in the library · 1 skipped (not an NES ROM or unreadable)")
    }

    func testLargeAndOversizedSelections() throws {
        let src = tmp.appendingPathComponent("many")
        let roms = tmp.appendingPathComponent("ROM")
        var urls: [URL] = []
        for i in 0..<120 { urls.append(try rom(i % 200 + 1, at: src.appendingPathComponent(String(format: "Game %03d.nes", i)))) }
        let big = src.appendingPathComponent("huge.nes")
        FileManager.default.createFile(atPath: big.path, contents: nil)
        let h = try FileHandle(forWritingTo: big)
        try h.truncate(atOffset: UInt64(ROMImport.maxROMSize + 1))
        try h.close()
        urls.append(big)
        let r = ROMImport.importBatch(urls, into: roms)
        XCTAssertEqual(r.added.count + r.existing.count, 120)
        XCTAssertEqual(r.failed.map(\.0) + r.invalid, ["huge.nes"])
        XCTAssertEqual(names(roms).count, r.added.count)
    }

    /// URLs delivered as successive events close together become one batch (one toast, one
    /// refresh); the work happens off the calling (main) thread.
    func testQueueCoalescesSuccessiveOpensIntoOneBatch() throws {
        let roms = tmp.appendingPathComponent("ROM")
        let a = try rom(1, at: tmp.appendingPathComponent("in/A.nes"))
        let b = try rom(2, at: tmp.appendingPathComponent("in/B.nes"))
        let c = try rom(3, at: tmp.appendingPathComponent("in/C.nes"))
        let deliver = DispatchQueue(label: "test.deliver")
        let q = ROMImportQueue(romDir: { roms }, coalesce: 0.3, deliver: deliver)
        let done = expectation(description: "one batch")
        var batches: [(ROMImportResult, ROMImportQueue.Batch)] = []
        var started: [Int] = []
        q.onStart = { started.append($0) }
        q.onFinish = { r, batch in
            XCTAssertFalse(Thread.isMainThread)
            batches.append((r, batch))
            done.fulfill()
        }
        q.enqueue([b], fromOtherApp: true)
        q.enqueue([a, b], fromOtherApp: true)       // the same file twice is imported once
        q.enqueue([c], fromOtherApp: false)
        XCTAssertTrue(q.busy)
        wait(for: [done], timeout: 10)
        deliver.sync {}
        XCTAssertEqual(started, [3])
        XCTAssertEqual(batches.count, 1)
        XCTAssertEqual(batches[0].1.urls.map(\.lastPathComponent), ["A.nes", "B.nes", "C.nes"])
        XCTAssertTrue(batches[0].1.fromOtherApp)
        XCTAssertEqual(batches[0].0.added.count, 3)
        XCTAssertFalse(q.busy)
    }

    func testQueueRunsLaterBatchesSeparately() throws {
        let roms = tmp.appendingPathComponent("ROM")
        let a = try rom(1, at: tmp.appendingPathComponent("in/A.nes"))
        let b = try rom(2, at: tmp.appendingPathComponent("in/B.nes"))
        let q = ROMImportQueue(romDir: { roms }, coalesce: 0.05, deliver: DispatchQueue(label: "test.deliver"))
        let first = expectation(description: "first"), second = expectation(description: "second")
        var results: [ROMImportResult] = []
        q.onFinish = { r, _ in results.append(r); (results.count == 1 ? first : second).fulfill() }
        q.enqueue([a], fromOtherApp: true)
        wait(for: [first], timeout: 10)
        q.enqueue([b], fromOtherApp: true)
        wait(for: [second], timeout: 10)
        XCTAssertEqual(results.map { $0.added.map(\.lastPathComponent) }, [["A.nes"], ["B.nes"]])
    }
}
