// The resume countdown's rules (Sources/Play/ResumeCountdownLogic.swift): when a resume counts
// down, when it may still end in play, what the on-screen buttons do meanwhile, and the 3-2-1 clock.
// SPDX-License-Identifier: GPL-2.0-or-later
import XCTest

final class ResumeCountdownTests: XCTestCase {
    private let pausedInPlay = ResumeCountdownGate.Context(enabled: true, hasSession: true, paused: true)

    func testCountsDownOnlyFromPauseOnThePlayScreen() {
        XCTAssertTrue(ResumeCountdownGate.shouldCountDown(pausedInPlay))
        var c = pausedInPlay
        c.enabled = false
        XCTAssertFalse(ResumeCountdownGate.shouldCountDown(c), "setting off: plays at once")
        c = pausedInPlay; c.paused = false
        XCTAssertFalse(ResumeCountdownGate.shouldCountDown(c), "already playing")
        c = pausedInPlay; c.hasSession = false
        XCTAssertFalse(ResumeCountdownGate.shouldCountDown(c), "no game")
        c = pausedInPlay; c.menuOpen = true
        XCTAssertFalse(ResumeCountdownGate.shouldCountDown(c), "menu up")
        c = pausedInPlay; c.libraryShown = true
        XCTAssertFalse(ResumeCountdownGate.shouldCountDown(c), "library up")
        c = pausedInPlay; c.dialogShown = true
        XCTAssertFalse(ResumeCountdownGate.shouldCountDown(c), "dialog up")
    }

    /// The practice run returning to A counts down itself: no second countdown before it.
    func testNoCountdownWhilePracticeReturns() {
        var c = pausedInPlay
        c.practiceReturning = true
        XCTAssertFalse(ResumeCountdownGate.shouldCountDown(c))
        XCTAssertTrue(ResumeCountdownGate.canResume(c), "it still resumes (at once)")
    }

    func testEndsInPlayOnlyWhenStillPausedOnThePlayScreen() {
        XCTAssertTrue(ResumeCountdownGate.canResume(pausedInPlay))
        var c = pausedInPlay
        c.enabled = false
        XCTAssertTrue(ResumeCountdownGate.canResume(c), "turning the setting off meanwhile does not strand it")
        for change: (inout ResumeCountdownGate.Context) -> Void in [{ $0.menuOpen = true }, { $0.libraryShown = true },
                                                                     { $0.dialogShown = true }, { $0.hasSession = false }] {
            c = pausedInPlay
            change(&c)
            XCTAssertFalse(ResumeCountdownGate.canResume(c))
        }
    }

    func testAbortsWhenResumedElsewhereOrTheSessionGoes() {
        XCTAssertFalse(ResumeCountdownGate.shouldAbort(pausedInPlay))
        var c = pausedInPlay
        c.dialogShown = true
        XCTAssertFalse(ResumeCountdownGate.shouldAbort(c), "a dialog only holds the end (checked then)")
        c = pausedInPlay; c.paused = false
        XCTAssertTrue(ResumeCountdownGate.shouldAbort(c))
        c = pausedInPlay; c.hasSession = false
        XCTAssertTrue(ResumeCountdownGate.shouldAbort(c))
        c = pausedInPlay; c.menuOpen = true
        XCTAssertTrue(ResumeCountdownGate.shouldAbort(c))
        c = pausedInPlay; c.libraryShown = true
        XCTAssertTrue(ResumeCountdownGate.shouldAbort(c))
    }

    func testTouchDuringCountdown() {
        for b: TouchButton in [.up, .down, .left, .right, .a, .b, .turboA, .turboB, .select, .start] {
            XCTAssertEqual(ResumeCountdownGate.touchRoute(b), .game, "\(b) is held into the first frame")
        }
        for b: TouchButton in [.l, .r, .l2, .r2, .stepBack, .stepForward] {
            XCTAssertEqual(ResumeCountdownGate.touchRoute(b), .drop, "\(b) is ignored")
        }
        XCTAssertEqual(ResumeCountdownGate.touchRoute(.menu), .abort)
        // Every button has a route (a new one must be decided here).
        XCTAssertEqual(TouchButton.allCases.count, 17)
    }

    func testClockCountsThreeTwoOne() {
        XCTAssertEqual(ResumeCountdownClock.seconds, 3)
        let c = ResumeCountdownClock(start: 100)
        XCTAssertEqual(c.state(at: 99), .counting(number: 3, fraction: 0), "before the start: 3")
        XCTAssertEqual(c.state(at: 100), .counting(number: 3, fraction: 0))
        XCTAssertEqual(c.state(at: 100.5), .counting(number: 3, fraction: 0.5))
        XCTAssertEqual(c.state(at: 101), .counting(number: 2, fraction: 0))
        XCTAssertEqual(c.state(at: 102.25), .counting(number: 1, fraction: 0.25))
        if case .counting(let n, let f) = c.state(at: 102.999) {
            XCTAssertEqual(n, 1)
            XCTAssertEqual(f, 0.999, accuracy: 1e-9)
        } else { XCTFail("still counting just before 3 s") }
        XCTAssertEqual(c.state(at: 103), .finished)
        XCTAssertEqual(c.state(at: 200), .finished)
    }

    /// The numbers drawn are the practice countdown's (same visual for 3, 2, 1).
    func testVisualIsThePracticeCountdowns() {
        for n in 1...3 {
            let v = PracticeLoop.countdownVisual(count: n, fraction: 0.5)
            XCTAssertEqual(Int(v.number), n)
            XCTAssertGreaterThan(v.alpha, 0.5)
        }
    }
}
