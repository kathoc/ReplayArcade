// The resume countdown on iPhone (Sources/Play/ResumeCountdownLogic.swift): when the UI treats it as
// on screen (the countdown itself is the shared core's: apps/macos/Tests/PlaybackLogicTests.swift
// and tests/test_frontend_resume_countdown.cpp).
// SPDX-License-Identifier: GPL-2.0-or-later
import XCTest

final class ResumeCountdownStatusTests: XCTestCase {
    private func counting(paused: Bool = false, countdown: Int, practicing: Bool = false, looping: Bool = false) -> Bool {
        ResumeCountdownStatus.counting(paused: paused, countdown: countdown, practicing: practicing, practiceLooping: looping)
    }

    func testCountingWhileUnpausedWithANumber() {
        for n in 1...3 { XCTAssertTrue(counting(countdown: n), "\(n)") }
        XCTAssertFalse(counting(countdown: 0), "playing")
        XCTAssertFalse(counting(paused: true, countdown: 0), "paused")
        XCTAssertFalse(counting(paused: true, countdown: 2), "paused (a stale number) is no countdown")
    }

    /// Practice: a resume while the run plays counts down (resume countdown); the run's own countdown
    /// at A (its return in progress) is not the resume countdown (its ✕ / tap would not apply).
    func testPracticeCountdownIsNotTheResumeCountdown() {
        XCTAssertTrue(counting(countdown: 3, practicing: true, looping: false))
        XCTAssertFalse(counting(countdown: 3, practicing: true, looping: true))
    }
}
