// The paused seek bar's Resume and the resume countdown (shared core; ResumeCountdown.swift): Resume (and
// the Quick Menu's Resume) shows 3, 2, 1 over the paused picture and then plays; a tap on the
// picture or ✕ goes back to paused; with the setting off Resume plays at once.
// Reported (iPhone): it was unclear which seek bar button resumes (an unlabelled ▶ read as "play
// the recording").
// TEST_RUNNER_SHOT_DIR=<dir>: also writes portrait screenshots of the seek bar and the countdown there
// (XCUITest's landscape screenshots come out rotated: use simctl with -orientation landscape
// -pauseAfter 3 -resumeAfter 6 for those).
// SPDX-License-Identifier: GPL-2.0-or-later
import XCTest

final class ResumeCountdownUITests: XCTestCase {
    private var app: XCUIApplication!
    private var geo: [String: [Double]] = [:]

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-touchHideWithPad", "NO", "-logTouch", "YES", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-debugUnlockAll", "YES", "-setResumeCountdown", "YES"]
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    // MARK: helpers

    private func el(_ id: String) -> XCUIElement {
        let b = app.buttons[id]
        return b.exists ? b : app.descendants(matching: .any)[id]
    }

    private func waitFor(_ timeout: TimeInterval, _ what: String, _ cond: () -> Bool) {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if cond() { return }
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTAssertTrue(cond(), what)
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

    private func pause() {
        // The pause button above MENU (2026-10-30: the picture is no longer tapped to pause).
        el("touch.pause").tap()
        XCTAssertTrue(el("seekBar").waitForExistence(timeout: 5), "the pause button pauses: the seek bar shows")
    }

    /// Holds the picture's left (rewind) or right (fast-forward) quarter: "rewindZone" / "ffZone".
    private func pressZone(_ k: String, _ seconds: TimeInterval) {
        let z = geo[k]!
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: z[0], dy: z[1])).press(forDuration: seconds)
    }

    private func shot(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["SHOT_DIR"] else { return }
        try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"))
    }

    // MARK: tests

    /// Play is a labelled button (no "record" wording: docs/design/VTR_UX.md); it counts down, then plays.
    func testResumeCountsDownThenPlays() throws {
        startPlay()
        pause()
        let resume = el("seekResume")
        XCTAssertTrue(resume.isHittable)
        XCTAssertEqual(resume.label, "Continue", "paused at the end of the tape: Continue")
        XCTAssertFalse(app.staticTexts["Keep recording"].exists, "Play never says recording")
        XCTAssertGreaterThanOrEqual(resume.frame.height, 44)
        for id in ["seekStepBack", "seekStepForward", "seekSetA", "seekSetB"] {
            XCTAssertFalse(el(id).label.isEmpty, "\(id) has a label")
        }
        shot("seekbar-portrait")
        let t0 = el("seekTime").label
        resume.tap()
        XCTAssertTrue(el("resumeCountdown").waitForExistence(timeout: 2), "the countdown shows")
        XCTAssertFalse(el("seekBar").exists, "the seek bar goes while counting down")
        Thread.sleep(forTimeInterval: 0.6)
        shot("countdown-portrait")
        waitFor(5, "the countdown ends") { !el("resumeCountdown").exists }
        XCTAssertFalse(el("seekBar").exists, "playing after the countdown")
        Thread.sleep(forTimeInterval: 1)
        pause()
        XCTAssertNotEqual(el("seekTime").label, t0, "the game ran after the countdown")
    }

    /// 2026-10-30: the picture is no control; the pause button goes back to paused during the countdown.
    func testPauseButtonAbortsToPaused() throws {
        startPlay()
        pause()
        let t0 = el("seekTime").label
        el("seekResume").tap()
        let cd = el("resumeCountdown")
        XCTAssertTrue(cd.waitForExistence(timeout: 2))
        el("touch.pause").tap()
        XCTAssertTrue(el("seekBar").waitForExistence(timeout: 2), "back to paused: the seek bar")
        XCTAssertFalse(cd.exists)
        Thread.sleep(forTimeInterval: 3.5)
        XCTAssertTrue(el("seekBar").exists, "still paused after the countdown's time")
        XCTAssertEqual(el("seekTime").label, t0, "nothing ran")
    }

    func testCancelButtonAbortsToPaused() throws {
        startPlay()
        pause()
        el("seekResume").tap()
        XCTAssertTrue(el("countdownCancel").waitForExistence(timeout: 2))
        el("countdownCancel").tap()
        XCTAssertTrue(el("seekBar").waitForExistence(timeout: 2), "✕: back to paused")
        Thread.sleep(forTimeInterval: 3.5)
        XCTAssertTrue(el("seekBar").exists, "still paused")
    }

    /// The Quick Menu's Resume counts down too; the MENU pill during the countdown pauses (the menu);
    /// closing that menu resumes again (the game was running), through a new countdown.
    func testMenuResumeCountsDownAndPillAborts() throws {
        startPlay()
        pause()
        tapPoint(pt("menu"))
        XCTAssertTrue(el("quickMenu").waitForExistence(timeout: 5))
        el("qm.resume").tap()
        XCTAssertTrue(el("resumeCountdown").waitForExistence(timeout: 2), "menu Resume counts down")
        tapPoint(pt("menu"))
        XCTAssertTrue(el("quickMenu").waitForExistence(timeout: 3), "MENU during the countdown opens the menu")
        XCTAssertFalse(el("resumeCountdown").exists)
        el("qmClose").tap()
        XCTAssertTrue(el("resumeCountdown").waitForExistence(timeout: 3), "✕ resumes: a new countdown")
        el("countdownCancel").tap()
        XCTAssertTrue(el("seekBar").waitForExistence(timeout: 3), "✕ on the countdown: paused")
    }

    /// The play controls during the countdown are transport, not game input: the pause button goes
    /// back to paused (cancels the countdown); a rewind zone held winds (released: the countdown again).
    func testTransportDuringCountdown() throws {
        startPlay()
        pause()
        el("seekResume").tap()
        XCTAssertTrue(el("resumeCountdown").waitForExistence(timeout: 2))
        el("touch.pause").tap()
        XCTAssertTrue(el("seekBar").waitForExistence(timeout: 2), "pause during the countdown: paused")
        XCTAssertFalse(el("resumeCountdown").exists)
        Thread.sleep(forTimeInterval: 3.5)
        XCTAssertTrue(el("seekBar").exists, "still paused")
        el("seekResume").tap()
        XCTAssertTrue(el("resumeCountdown").waitForExistence(timeout: 2))
        // Rewind held during the countdown takes over (the countdown stops while it winds); the
        // interrupted resume still counts as play, so its release counts down again
        // (EmulationController: rewindStartedPaused), as a controller's L2 does.
        let edges = (el("touchProbe").value as? String) ?? ""
        pressZone("rewindZone", 0.8)
        waitFor(3, "rewind edges") { ((el("touchProbe").value as? String) ?? "").count > edges.count }
        XCTAssertTrue(el("resumeCountdown").waitForExistence(timeout: 2), "released: the countdown again")
        el("countdownCancel").tap()
        XCTAssertTrue(el("seekBar").waitForExistence(timeout: 2), "✕: paused")
    }

    /// Rewind held while playing: released, the resume countdown runs, then play (VTR_UX.md).
    func testRewindReleaseCountsDown() throws {
        startPlay()
        Thread.sleep(forTimeInterval: 2)
        pressZone("rewindZone", 1)
        XCTAssertTrue(el("resumeCountdown").waitForExistence(timeout: 2), "released: the countdown")
        waitFor(5, "the countdown ends") { !el("resumeCountdown").exists }
        XCTAssertFalse(el("seekBar").exists, "playing")
    }

    func testCountdownOffResumesAtOnce() throws {
        app.launchArguments += ["-setResumeCountdown", "NO"]
        startPlay()
        pause()
        el("seekResume").tap()
        waitFor(2, "plays at once") { !el("seekBar").exists }
        XCTAssertFalse(el("resumeCountdown").exists, "no countdown")
    }

    func testLandscape() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        startPlay()
        Thread.sleep(forTimeInterval: 1)
        pause()
        XCTAssertTrue(el("seekResume").isHittable)
        el("seekResume").tap()
        XCTAssertTrue(el("resumeCountdown").waitForExistence(timeout: 2))
        Thread.sleep(forTimeInterval: 0.6)
        waitFor(5, "the countdown ends") { !el("resumeCountdown").exists }
        XCTAssertFalse(el("seekBar").exists, "playing")
    }
}
