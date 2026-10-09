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
}
