// The resume countdown's rules, pure (unit tested: Tests/ResumeCountdownTests.swift): resuming from
// pause (seek bar Resume, the menu's Resume / ✕ / MENU pill, the controller's cancel tap) first shows
// 3, 2, 1 over the paused picture - the same numeral, disc and ring as the practice countdown
// (rnf_practice_countdown_visual, CountdownOverlay) - then plays. Setting: Settings › Controls ›
// Resume Countdown (default on).
// Nothing is emulated meanwhile (the game stays paused): game buttons pressed then are held into
// the first frame (as the practice countdown), app gestures (frame step, L / R, rewind / fast-forward)
// are dropped, and a tap on the picture, ✕, the menu or the controller's cancel tap go back to paused.
// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation

enum ResumeCountdownGate {
    /// What the app looks like when a resume is asked for (main thread snapshot).
    struct Context: Equatable {
        var enabled = true          // the setting
        var hasSession = false
        var paused = false
        /// The practice run is returning to A (hold / sweep / its own countdown): that run counts
        /// down itself when it goes on, so a second countdown would only delay it.
        var practiceReturning = false
        var menuOpen = false
        var libraryShown = false
        var dialogShown = false
    }

    /// A resume from pause counts down first.
    static func shouldCountDown(_ c: Context) -> Bool {
        c.enabled && canResume(c) && !c.practiceReturning
    }

    /// The countdown may (still) end in play: the same session is paused on the play screen and
    /// nothing modal is up. Checked again when it reaches zero.
    static func canResume(_ c: Context) -> Bool {
        c.hasSession && c.paused && !c.menuOpen && !c.libraryShown && !c.dialogShown
    }

    /// The countdown stops (back to paused, or nothing to resume any more) when the game was
    /// resumed some other way or the session went away.
    static func shouldAbort(_ c: Context) -> Bool {
        !c.hasSession || !c.paused || c.menuOpen || c.libraryShown
    }

    /// An on-screen button pressed during the countdown.
    enum TouchRoute: Equatable {
        case game     // game input: held into the first frame (nothing is emulated before)
        case drop     // app gesture (step, L / R, rewind / fast-forward): ignored, its release too
        case abort    // the MENU pill: back to paused (the menu opens)
    }

    static func touchRoute(_ b: TouchButton) -> TouchRoute {
        switch b {
        case .menu: return .abort
        case .up, .down, .left, .right, .a, .b, .turboA, .turboB, .select, .start: return .game
        case .l, .r, .l2, .r2, .stepBack, .stepForward: return .drop
        }
    }
}

/// 3, 2, 1 - one number per second, from `start` (seconds on any monotonic clock).
struct ResumeCountdownClock: Equatable {
    static let seconds = RNF_PRACTICE_COUNTDOWN_SECONDS   // 3 s, as the practice countdown

    enum State: Equatable {
        case counting(number: Int, fraction: Double)  // fraction: 0...1 within that number's second
        case finished
    }

    let start: Double

    func state(at now: Double) -> State {
        let e = max(0, now - start)
        if e >= Self.seconds { return .finished }
        let whole = floor(e)
        return .counting(number: Int(Self.seconds - whole), fraction: e - whole)
    }
}
