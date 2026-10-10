// Multi-file ROM import end to end (simulator).
//  - testMultiFileImportBatch: the app's -importTestBatch hook hands one batch of 7 URLs (5 new
//    ROMs - two named Alpha.nes -, a duplicate, a non-ROM) to the entry point of a multi-item
//    "Open in ReplayNES" (AppModel.open(urls:), as SceneDelegate does); the library must list
//    every ROM, show one toast, start no game and stay responsive.
//  - testShareFromFilesApp: the real thing through the Files app's share sheet (select all ›
//    Share › Add to ReplayNES, the Share Extension › Add). It needs .nes files in On My iPhone ›
//    ShareROMs (copy them into the simulator's File Provider Storage first; see apps/ios/README.md)
//    and is skipped otherwise. Every file arrives (iOS hands the app's own "ReplayNES" entry only
//    the first one, hence the extension); SHARE_ROM_COUNT (default 7) = the .nes files there.
// SPDX-License-Identifier: GPL-2.0-or-later
import XCTest

final class ROMImportUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func gameCards(_ app: XCUIApplication) -> Int {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'gameCard.'")).count
    }

    private func waitFor(_ timeout: TimeInterval, _ cond: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if cond() { return true }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return cond()
    }

    func testMultiFileImportBatch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-resetLibraryForTests", "YES", "-importTestBatch", "YES", "-AppleLanguages", "(en)"]
        app.launch()
        let toast = app.staticTexts["notice"]
        XCTAssertTrue(toast.waitForExistence(timeout: 20), "the import toast")
        XCTAssertEqual(toast.label, "Added 5 ROM(s) · 1 already in the library · 1 skipped (not an NES ROM or unreadable)")
        XCTAssertTrue(waitFor(10) { gameCards(app) == 5 }, "5 game cards, found \(gameCards(app))")
        XCTAssertTrue(app.descendants(matching: .any)["gameCard.Alpha 2.nes"].exists, "same name, other ROM -> Alpha 2.nes")
        // Nothing started by itself, and the UI still answers.
        XCTAssertTrue(app.buttons["importROMs"].isHittable)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "library after multi import"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// SHARE_WHILE_PLAYING=1 (TEST_RUNNER_SHARE_WHILE_PLAYING for xcodebuild): a game runs when the
    /// files arrive. SHARE_COLD=1: the app is not running.
    func testShareFromFilesApp() throws {
        let env = ProcessInfo.processInfo.environment
        let app = XCUIApplication()
        app.launchArguments = ["-resetLibraryForTests", "YES", "-AppleLanguages", "(en)"]
        if env["SHARE_WHILE_PLAYING"] == "1" { app.launchArguments += ["-autoplayTestROM", "YES"] }
        app.launch()
        if env["SHARE_WHILE_PLAYING"] == "1" {
            Thread.sleep(forTimeInterval: 4)
        } else {
            XCTAssertTrue(app.buttons["importROMs"].waitForExistence(timeout: 15))
        }
        if env["SHARE_COLD"] == "1" { app.terminate() }

        let files = XCUIApplication(bundleIdentifier: "com.apple.DocumentsApp")
        files.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        files.launch()
        let browse = files.tabBars.buttons["Browse"]
        if browse.waitForExistence(timeout: 10) { browse.tap(); browse.tap() }
        let onPhone = files.staticTexts["On My iPhone"]
        guard onPhone.waitForExistence(timeout: 10) else { throw XCTSkip("Files: no On My iPhone") }
        onPhone.tap()
        let folder = files.staticTexts["ShareROMs"]
        guard folder.waitForExistence(timeout: 10) else { throw XCTSkip("put .nes files into On My iPhone › ShareROMs first") }
        let cell = files.cells.containing(.staticText, identifier: "ShareROMs").firstMatch
        (cell.exists ? cell : folder).tap()
        XCTAssertTrue(files.cells["Alpha.nes, nes"].waitForExistence(timeout: 10) || files.cells.count > 0, files.debugDescription)
        // Select every file of the folder.
        files.navigationBars.buttons["More"].tap()
        let select = files.descendants(matching: .any).matching(NSPredicate(format: "label == 'Select'")).firstMatch
        XCTAssertTrue(select.waitForExistence(timeout: 5), files.debugDescription)
        select.tap()
        let selectAll = files.buttons["Select All"]
        XCTAssertTrue(selectAll.waitForExistence(timeout: 5), files.debugDescription)
        selectAll.tap()
        let share = files.buttons["Share"]
        XCTAssertTrue(share.waitForExistence(timeout: 5), files.debugDescription)
        share.tap()
        // The share sheet: the app row shows the extension under the app's name, next to the app's
        // own "ReplayNES" entry (document types; it gets only the first file): find the one that
        // brings up the extension's confirmation.
        let cells = files.cells.matching(NSPredicate(format: "label == 'ReplayNES' OR label == 'Add to ReplayNES' OR label == 'ReplayNESに追加'"))
        XCTAssertTrue(cells.firstMatch.waitForExistence(timeout: 10), files.debugDescription)
        let index = Int(env["SHARE_CELL_INDEX"] ?? "") ?? (cells.count - 1)
        cells.element(boundBy: index).tap()

        // The extension's confirmation ("Add N file(s) to ReplayNES" + Add / Cancel), hosted by Files.
        let title = files.staticTexts["shareTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 15), files.debugDescription)
        let shotSheet = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shotSheet.name = "share extension: \(title.label)"
        shotSheet.lifetime = .keepAlways
        add(shotSheet)
        files.buttons["shareAdd"].tap()
        XCTAssertTrue(waitFor(15) { !title.exists }, "the extension finishes")

        // Back to ReplayNES: the batch is imported when it becomes active.
        if env["SHARE_COLD"] == "1" { app.launchArguments = ["-AppleLanguages", "(en)"]; app.launch() } else { app.activate() }
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
        let toast = app.staticTexts["notice"]
        XCTAssertTrue(toast.waitForExistence(timeout: 20), "the import toast")
        let roms = Int(env["SHARE_ROM_COUNT"] ?? "") ?? 7
        XCTAssertTrue(toast.label.hasPrefix("Added \(roms) ROM(s)"), toast.label)
        let shotToast = XCTAttachment(screenshot: app.screenshot())
        shotToast.name = "after Files share: \(toast.label)"
        shotToast.lifetime = .keepAlways
        add(shotToast)
        if env["SHARE_WHILE_PLAYING"] == "1" {
            // The game keeps running (no other game was started); the library lists the imports.
            XCTAssertFalse(app.buttons["importROMs"].exists, "still on the play screen")
            app.terminate()
            app.launchArguments = ["-AppleLanguages", "(en)"]
            app.launch()
            XCTAssertTrue(app.buttons["importROMs"].waitForExistence(timeout: 15))
        }
        // + the test ROM that was playing.
        let expected = (Int(env["SHARE_ROM_COUNT"] ?? "") ?? 7) + (env["SHARE_WHILE_PLAYING"] == "1" ? 1 : 0)
        XCTAssertTrue(waitFor(10) { gameCards(app) == expected }, "\(expected) game cards, found \(gameCards(app))")
        XCTAssertTrue(app.buttons["importROMs"].isHittable, "the library still answers")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "library after Files share"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
