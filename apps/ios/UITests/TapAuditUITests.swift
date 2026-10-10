// Tap audit: every tappable control of the iPhone UI is tapped like a finger would (XCUITest taps
// on accessibility identifiers, or on the touch controls' probe points) and must have a visible
// effect. Library (cards, Continue / Resume, "…" › Settings / Unlocks, sort, search, import, Add Test
// Cartridge), the play screen (MENU pill, seek bar while paused), the Quick Menu (top tiles, every
// page's rows: toggles, segments, choice menus, sliders, detail rows, tabs, back, close, backdrop)
// and the Export / Unlocks sheets.
// Regression: the Quick Menu's open / closed state lives in QuickMenuController, which the library
// and play screens read through AppModel without observing it: "…" › Settings in the library and
// the menu's ✕ (or the backdrop) on a paused game changed nothing on screen.
// SPDX-License-Identifier: GPL-2.0-or-later
import XCTest

final class TapAuditUITests: XCTestCase {
    private var app: XCUIApplication!
    private var geo: [String: [Double]] = [:]

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-touchHideWithPad", "NO", "-logTouch", "YES", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-debugUnlockAll", "YES"]
    }

    // MARK: helpers

    /// A failure keeps the screen and the element tree (attachments; AUDIT_DIR = also as files).
    override func record(_ issue: XCTIssue) {
        var issue = issue
        if let app, app.state == .runningForeground {
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.lifetime = .keepAlways
            issue.add(shot)
            let tree = XCTAttachment(string: app.debugDescription)
            tree.lifetime = .keepAlways
            issue.add(tree)
            if let dir = ProcessInfo.processInfo.environment["AUDIT_DIR"] {
                let name = "\(name.filter { $0.isLetter || $0.isNumber })-\(Int(Date().timeIntervalSince1970))"
                try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"))
                try? app.debugDescription.write(toFile: dir + "/" + name + ".txt", atomically: true, encoding: .utf8)
            }
        }
        super.record(issue)
    }

    /// The element with that identifier (a toolbar Menu shows up twice: its wrapper and the button).
    private func el(_ id: String) -> XCUIElement {
        let b = app.buttons[id]
        return b.exists ? b : app.descendants(matching: .any)[id]
    }
    private var menuPanel: XCUIElement { el("quickMenu") }
    private var menuTitle: String { el("qmTitle").label }

    private func waitFor(_ timeout: TimeInterval = 5, _ what: String, _ cond: () -> Bool) {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if cond() { return }
            Thread.sleep(forTimeInterval: 0.15)
        }
        XCTAssertTrue(cond(), what)
    }

    private func gone(_ e: XCUIElement, _ what: String) { waitFor(5, what) { !e.exists } }

    /// A finger-like tap on an element (fails if something else covers it).
    private func tap(_ id: String, _ what: String? = nil) {
        let e = el(id)
        XCTAssertTrue(e.waitForExistence(timeout: 5), "\(what ?? id) exists")
        reveal(e)
        // XCUITest reports toolbar menus (wrapper + button) as not hittable although they are.
        if !id.hasPrefix("library") { XCTAssertTrue(e.isHittable, "\(what ?? id) is hittable") }
        e.tap()
    }

    /// Scrolls the Quick Menu's list until `e` is on screen (a finger would scroll too).
    private func reveal(_ e: XCUIElement) {
        guard menuPanel.exists, !e.isHittable else { return }
        let list = menuPanel.scrollViews.firstMatch
        guard list.exists else { return }
        for _ in 0..<4 where !e.isHittable { list.swipeUp(velocity: .slow) }
        for _ in 0..<8 where !e.isHittable { list.swipeDown(velocity: .slow) }
    }

    private func tapPoint(_ p: CGPoint) { app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: p.x, dy: p.y)).tap() }
    private func pt(_ k: String) -> CGPoint { CGPoint(x: geo[k]![0], y: geo[k]![1]) }

    private func startPlay() {
        app.launchArguments += ["-autoplayTestROM", "YES"]
        app.launch()
        let probe = el("touchProbe")
        XCTAssertTrue(probe.waitForExistence(timeout: 15))
        waitFor(10, "probe geometry") {
            if let d = probe.label.data(using: .utf8), let g = try? JSONSerialization.jsonObject(with: d) as? [String: [Double]], g["menu"] != nil {
                geo = g
                return true
            }
            return false
        }
        Thread.sleep(forTimeInterval: 1.5)
    }

    private func probeEdges() -> String { (el("touchProbe").value as? String) ?? "" }

    private func openMenuWithPill() {
        tapPoint(pt("menu"))
        XCTAssertTrue(menuPanel.waitForExistence(timeout: 5), "MENU pill opens the Quick Menu")
    }

    private func pause() {
        tapPoint(pt("r"))
        XCTAssertTrue(el("seekBar").waitForExistence(timeout: 5), "R pauses: the seek bar shows")
    }

    // MARK: library

    func testLibrary() throws {
        app.launchArguments += ["-resetLibraryForTests", "YES"]
        app.launch()
        // Empty library: Add Test Cartridge.
        tap("addTestCartridge")
        let card = el("gameCard.ReplayNES Test Cartridge.nes")
        XCTAssertTrue(card.waitForExistence(timeout: 10), "Add Test Cartridge adds a card")

        // "…" › Settings opens the Quick Menu at Settings (reported: did nothing).
        tap("libraryMore", "… menu")
        tap("librarySettings", "… › Settings")
        XCTAssertTrue(menuPanel.waitForExistence(timeout: 5), "… › Settings opens the Quick Menu")
        XCTAssertEqual(menuTitle, "Display")
        // Tabs.
        for (tab, title) in [("controls", "Controls"), ("sound", "Sound"), ("system", "System"), ("display", "Display")] {
            tap("qmTab.\(tab)")
            waitFor(3, "tab \(tab)") { menuTitle == title }
        }
        // ✕ closes it (reported: did nothing).
        tap("qmClose", "✕")
        gone(menuPanel, "✕ closes the Quick Menu (library)")
        // The backdrop closes it too.
        tap("libraryMore"); tap("librarySettings")
        XCTAssertTrue(menuPanel.waitForExistence(timeout: 5))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        gone(menuPanel, "the backdrop closes the Quick Menu")

        // "…" › Unlocks.
        tap("libraryMore"); tap("libraryUnlocks", "… › Unlocks")
        XCTAssertTrue(app.navigationBars["Unlocks"].waitForExistence(timeout: 5), "Unlocks sheet")
        app.navigationBars["Unlocks"].buttons["Done"].tap()
        gone(app.navigationBars["Unlocks"], "Done closes Unlocks")

        // Sort / show menu.
        tap("librarySort", "sort menu")
        XCTAssertTrue(app.buttons["Year"].waitForExistence(timeout: 3), "sort menu opens")
        app.buttons["Year"].tap()
        gone(app.buttons["Year"], "sort choice closes the menu")

        // Search filters the cards.
        let search = app.searchFields.firstMatch
        if !search.exists { app.swipeDown() }
        XCTAssertTrue(search.waitForExistence(timeout: 3), "search field")
        search.tap()
        search.typeText("zzzz")
        gone(card, "search filters the cards")
        app.buttons["Cancel"].firstMatch.tap()
        XCTAssertTrue(card.waitForExistence(timeout: 3), "cancelling the search shows the cards again")

        // + import: the document picker.
        tap("importROMs", "+ import")
        let picker = app.descendants(matching: .any)["DocumentPickerViewController"]
        let cancel = app.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 8) || picker.exists, "import opens the document picker")
        if cancel.exists { cancel.tap() }
        XCTAssertTrue(card.waitForExistence(timeout: 5))

        // A card starts the game; Library from the menu, Resume card, Back to Game.
        XCTAssertTrue(card.isHittable)
        card.tap()
        XCTAssertTrue(el("touchProbe").waitForExistence(timeout: 15), "the card starts the game")
        Thread.sleep(forTimeInterval: 1.5)
        el("touchProbe").label.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: [Double]] }.map { geo = $0 }
        openMenuWithPill()
        tap("qm.game"); waitFor(3, "Game page") { menuTitle == "Game" }
        tap("qm.choose", "Game › Library")
        XCTAssertTrue(el("heroCard").waitForExistence(timeout: 5), "the library shows the Resume card")
        tap("backToGame", "Back to Game")
        XCTAssertTrue(el("touchProbe").waitForExistence(timeout: 5), "Back to Game")
        openMenuWithPill()
        tap("qm.game"); tap("qm.choose")
        tap("heroCard", "Resume card")
        XCTAssertTrue(el("touchProbe").waitForExistence(timeout: 5), "the Resume card returns to the game")
    }

    // MARK: play screen

    func testPlayScreenAndSeekBar() throws {
        XCUIDevice.shared.orientation = .portrait
        try playScreenAndSeekBar()
    }

    func testPlayScreenAndSeekBarLandscape() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        try playScreenAndSeekBar()
    }

    private func playScreenAndSeekBar() throws {
        startPlay()
        // MENU pill, ✕ while playing.
        openMenuWithPill()
        tap("qmClose")
        gone(menuPanel, "✕ closes the menu (playing)")
        // Paused: the menu's ✕ / backdrop / back on the top page (reported: ✕ did nothing).
        pause()
        openMenuWithPill()
        tap("qmClose")
        gone(menuPanel, "✕ closes the menu (paused)")
        XCTAssertTrue(el("seekBar").waitForExistence(timeout: 3), "still paused: the seek bar")
        openMenuWithPill()
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        gone(menuPanel, "the backdrop closes the menu (paused)")
        openMenuWithPill()
        tap("qm.resume", "Resume tile")
        gone(menuPanel, "Resume closes the menu")
        gone(el("seekBar"), "Resume plays")
        pause()

        // Seek bar.
        let time = el("seekTime")
        let t0 = time.label
        tap("seekStepBack")
        waitFor(3, "step back changes the time") { time.label != t0 }
        let t1 = time.label
        tap("seekStepForward")
        waitFor(3, "step forward changes the time") { time.label != t1 }
        // Scrub: tap the start of the track.
        let track = el("seekTrack")
        XCTAssertTrue(track.isHittable)
        let t2 = time.label
        track.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)).tap()
        waitFor(3, "scrubbing moves the playhead") { time.label != t2 }
        // A/B slot menu.
        tap("seekSlot")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'A/B 2'")).firstMatch.waitForExistence(timeout: 3), "slot menu")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'A/B 2'")).firstMatch.tap()
        waitFor(3, "slot 2 selected") { el("seekSlot").label.contains("A/B 2") }
        tap("seekSetA")
        XCTAssertTrue(el("seekPractice").waitForExistence(timeout: 3), "Set A makes Practice available")
        tap("seekStepForward"); tap("seekStepForward")
        tap("seekSetB")
        tap("seekPractice")
        XCTAssertTrue(app.staticTexts["Practicing"].waitForExistence(timeout: 5), "Practice starts (and plays)")
        Thread.sleep(forTimeInterval: 1)
        pause()
        XCTAssertTrue(el("seekStopPractice").waitForExistence(timeout: 5), "paused while practicing: Stop Practicing")
        tap("seekStopPractice")
        XCTAssertTrue(el("seekSetA").waitForExistence(timeout: 5), "Stop Practicing")
        tap("seekResume")
        gone(el("seekBar"), "▶ resumes")

        // Touch extras (pause / step / menu) go through the probe.
        let before = probeEdges()
        tapPoint(pt("stepBack"))
        waitFor(3, "◀︎| reaches the app") { probeEdges().count > before.count }
        XCTAssertTrue(el("seekBar").waitForExistence(timeout: 3), "◀︎| pauses")
    }

    // MARK: Quick Menu

    /// Rows of the current page: identifiers "qm.<item id>".
    private func rowIDs() -> [String] {
        let q = menuPanel.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'qm.'"))
        return q.allElementsBoundByIndex.map(\.identifier)
    }

    /// Every control of a settings-style page: toggles flip (and are flipped back), segments and
    /// choice menus select, sliders move, detail rows open their page (and Back returns).
    private func exercisePage(_ title: String, depth: Int = 0) {
        waitFor(3, "page \(title)") { menuTitle == title }
        var done = Set<String>()
        let ids = rowIDs()
        XCTAssertFalse(ids.isEmpty, "\(title): rows")
        print("TapAudit \(title): \(ids.joined(separator: " "))")
        for id in ids where !done.contains(id) {
            done.insert(id)
            let item = String(id.dropFirst(3))
            let row = el(id)
            guard row.exists else { continue }
            // Disabled rows (greyed out, e.g. CRT details while CRT is off) do nothing by design.
            if row.descendants(matching: .any).allElementsBoundByIndex.contains(where: { !$0.isEnabled }) { continue }
            reveal(row)
            if el("qmToggle.\(item)").exists {
                let t = el("qmToggle.\(item)")
                if !t.isEnabled { continue }
                let v0 = t.value as? String
                row.tap()
                waitFor(3, "\(title) › \(item): toggle flips") { (t.value as? String) != v0 }
                row.tap()
                waitFor(3, "\(title) › \(item): toggle flips back") { (t.value as? String) == v0 }
            } else if el("qmSeg.\(item).0").exists {
                let segs = row.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "qmSeg.\(item)."))
                let n = segs.count
                let sel = (0..<n).first { el("qmSeg.\(item).\($0)").isSelected } ?? 0
                let other = (sel + 1) % n
                tap("qmSeg.\(item).\(other)")
                waitFor(3, "\(title) › \(item): segment \(other)") { el("qmSeg.\(item).\(other)").isSelected }
                tap("qmSeg.\(item).\(sel)")
                waitFor(3, "\(title) › \(item): segment back") { el("qmSeg.\(item).\(sel)").isSelected }
            } else if el("qmChoice.\(item)").exists {
                let c = el("qmChoice.\(item)")
                let v0 = c.label
                tap("qmChoice.\(item)")
                let options = app.collectionViews.buttons
                XCTAssertTrue(options.firstMatch.waitForExistence(timeout: 3), "\(title) › \(item): choice menu opens")
                let pick = options.allElementsBoundByIndex.first { !$0.label.isEmpty && !v0.hasPrefix($0.label) && $0.isHittable }
                if let pick {
                    let l = pick.label
                    pick.tap()
                    waitFor(3, "\(title) › \(item): choice \(l)") { c.label.hasPrefix(l) }
                    tap("qmChoice.\(item)")
                    if let back = app.collectionViews.buttons.allElementsBoundByIndex.first(where: { v0.hasPrefix($0.label) && !$0.label.isEmpty }) { back.tap() }
                } else {
                    app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
                }
                gone(app.collectionViews.firstMatch, "choice menu closed")
            } else if el("qmSlider.\(item)").exists {
                let s = el("qmSlider.\(item)")
                let v0 = (s.value as? String) ?? ""
                let high = (Double(v0.filter(\.isNumber)) ?? 0) > 50
                s.adjust(toNormalizedSliderPosition: high ? 0.1 : 0.9)
                waitFor(3, "\(title) › \(item): slider moves (\(v0))") { (s.value as? String) != v0 }
                let v1 = s.value as? String
                s.adjust(toNormalizedSliderPosition: high ? 0.9 : 0.1)
                waitFor(3, "\(title) › \(item): slider moves back (\(v1 ?? ""))") { (s.value as? String) != v1 }
            } else if el("qmLink.\(item)").exists, depth < 2 {
                row.tap()
                waitFor(3, "\(title) › \(item): opens its page") { menuTitle != title }
                let sub = menuTitle
                if sub != title && !["Change Button", "Controller"].contains(sub) { exercisePage(sub, depth: depth + 1) }
                tap("qmBack")
                waitFor(3, "back to \(title)") { menuTitle == title }
            }
        }
    }

    func testQuickMenuPages() throws {
        startPlay()
        openMenuWithPill()
        XCTAssertEqual(menuTitle, "Menu")
        // Every top tile opens its page or acts; Back returns.
        for (tile, title) in [("retry", "Retry"), ("practice", "Practice"), ("share", "Share"), ("settings", "Display"), ("game", "Game")] {
            tap("qm.\(tile)")
            waitFor(3, "tile \(tile)") { menuTitle == title }
            tap("qmBack")
            waitFor(3, "back from \(tile)") { menuTitle == "Menu" }
        }
        // Retry › Takes / Bookmarks: cards are tappable (the current take).
        tap("qm.retry")
        for id in rowIDs() where id != "qm.retry" {
            let e = el(id)
            reveal(e)
            XCTAssertTrue(e.isHittable, "Retry › \(id) hittable")
        }
        tap("qmBack")
        // Practice: slot cards.
        tap("qm.practice")
        waitFor(3, "Practice") { menuTitle == "Practice" }
        for id in rowIDs() { reveal(el(id)); XCTAssertTrue(el(id).isHittable, "Practice › \(id) hittable") }
        tap("qmBack")
        // Settings: every tab, every row.
        tap("qm.settings")
        for (tab, title) in [("display", "Display"), ("controls", "Controls"), ("sound", "Sound"), ("system", "System")] {
            tap("qmTab.\(tab)")
            exercisePage(title)
        }
        tap("qmClose")
        gone(menuPanel, "✕ closes the menu")
    }

    private func label(_ id: String) -> String {
        el(id).descendants(matching: .staticText).allElementsBoundByIndex.map(\.label).joined(separator: " ")
    }

    /// The "…" menu of a card (Rename / Delete / Clear) and the rename prompt (an alert).
    private func cardMenu(_ item: String, _ action: String) {
        tap("qmMore.\(item)", "\(item) …")
        let b = app.buttons[action]
        XCTAssertTrue(b.waitForExistence(timeout: 3), "\(item) … › \(action)")
        b.tap()
    }

    func testRetryPracticeAndDialogs() throws {
        startPlay()
        openMenuWithPill()
        // Practice: Set A on a slot card, its … menu (Rename prompt: Cancel / Rename, Clear).
        tap("qm.practice")
        waitFor(3, "Practice") { menuTitle == "Practice" }
        XCTAssertTrue(label("qm.slot0").contains("Set A Here"))
        tap("qm.slot0", "slot 1 card")
        waitFor(3, "Set A Here sets A") { !label("qm.slot0").contains("Set A Here") }
        cardMenu("slot0", "Rename")
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 3), "rename prompt")
        alert.buttons["Cancel"].tap()
        gone(alert, "Cancel closes the prompt")
        cardMenu("slot0", "Rename")
        XCTAssertTrue(alert.waitForExistence(timeout: 3))
        let field = alert.textFields.firstMatch
        field.tap()
        field.press(forDuration: 0.1)
        if let v = field.value as? String, !v.isEmpty { field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: v.count)) }
        field.typeText("Boss")
        alert.buttons["Rename"].tap()
        gone(alert, "Rename closes the prompt")
        waitFor(3, "renamed") { label("qm.slot0").contains("Boss") }
        cardMenu("slot0", "Clear")
        waitFor(3, "Clear") { label("qm.slot0").contains("Set A Here") }
        tap("qmBack")

        // Retry › Bookmarks: Add Here, rename, jump.
        tap("qm.retry"); waitFor(3, "Retry") { menuTitle == "Retry" }
        tap("qm.bookmarks"); waitFor(3, "Bookmarks") { menuTitle == "Bookmarks" }
        let before = rowIDs().count
        tap("qm.addBookmark", "Add Here")
        waitFor(3, "a bookmark is added") { rowIDs().count == before + 1 }
        guard let bm = rowIDs().first(where: { $0.hasPrefix("qm.bm") }) else { return XCTFail("bookmark card") }
        let bmID = String(bm.dropFirst(3))
        cardMenu(bmID, "Rename")
        XCTAssertTrue(alert.waitForExistence(timeout: 3), "bookmark rename prompt")
        alert.buttons["Cancel"].tap()
        gone(alert, "Cancel")
        tap(bm, "bookmark card")
        gone(menuPanel, "a bookmark jumps and closes the menu")

        // Retry › Takes: the current take closes the menu.
        openMenuWithPill()
        tap("qm.retry"); tap("qm.takes"); waitFor(3, "Takes") { menuTitle == "Takes" }
        guard let take = rowIDs().first(where: { $0.hasPrefix("qm.take") }) else { return XCTFail("take card") }
        tap(take)
        gone(menuPanel, "a take card closes the menu")

        // Retry › Restart Recording: its confirmation (Cancel).
        openMenuWithPill()
        tap("qm.retry"); tap("qm.restart", "Restart Recording")
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "Restart Recording asks first")
        let cancel = alert.buttons["Cancel"]
        XCTAssertTrue(cancel.exists, "the confirmation's Cancel: \(alert.buttons.allElementsBoundByIndex.map(\.label))")
        cancel.tap()
        gone(alert, "Cancel closes the confirmation")

        // Game › Reset › Soft Reset, Game › Close.
        openMenuWithPill()
        tap("qm.game"); waitFor(3, "Game") { menuTitle == "Game" }
        tap("qm.reset"); waitFor(3, "Reset") { menuTitle == "Reset" }
        tap("qm.soft", "Soft Reset")
        gone(menuPanel, "Soft Reset closes the menu")
        openMenuWithPill()
        tap("qm.game"); tap("qm.close", "Close")
        XCTAssertTrue(el("importROMs").waitForExistence(timeout: 10), "Close returns to the library")
    }

    func testExportSheet() throws {
        startPlay()
        Thread.sleep(forTimeInterval: 1)
        openMenuWithPill()
        tap("qm.share")
        waitFor(3, "Share") { menuTitle == "Share" }
        let ids = rowIDs()
        guard let export = ids.first(where: { $0.lowercased().contains("export") }) else { return XCTFail("no export item: \(ids)") }
        tap(export)
        XCTAssertTrue(app.navigationBars["Export MP4"].waitForExistence(timeout: 5), "Export sheet")
        app.navigationBars["Export MP4"].buttons["Close"].tap()
        gone(app.navigationBars["Export MP4"], "Close closes Export")
    }
}
