// The resume countdown as the iPhone UI sees it (pure; unit tested: Tests/ResumeCountdownTests.swift).
// The countdown itself is the shared core's (rnf_resume_countdown, EmulationController.resume(),
// drawn by the renderer like the practice one; docs/design/UI_REDESIGN.md, "Resume countdown"):
// while it runs the game is unpaused but nothing is emulated, and the status shows 3 / 2 / 1.
// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation

enum ResumeCountdownStatus {
    /// The resume countdown is on screen (not the practice run's own countdown at A, which runs
    /// while its return sequence is in progress).
    static func counting(paused: Bool, countdown: Int, practicing: Bool, practiceLooping: Bool) -> Bool {
        !paused && countdown > 0 && !(practicing && practiceLooping)
    }
}
