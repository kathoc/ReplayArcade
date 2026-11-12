// The resume countdown on iPhone: AppModel resumes through ResumeCountdownDriver, today the shared
// core's (CoreResumeCountdown: EmulationController.resume() applies rnf_resume_countdown, the renderer
// draws 3, 2, 1 in the game's own pass). On top, iPhone only: ✕ (or the pause button) goes back to
// paused (ResumeCountdownCatcher; the controller's cancel tap does the same through InputManager). The
// picture itself is not a control (2026-10-30): its side quarters wind the tape, also during the countdown.
// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

protocol ResumeCountdownDriver: AnyObject {
    /// A user resume from pause: 3, 2, 1 first when the countdown applies (setting, mode).
    func resume()
    /// Back to paused while it counts (nothing happens otherwise).
    func abort()
    /// It is on screen in this status.
    func isCounting(_ st: EmuStatus) -> Bool
}

final class CoreResumeCountdown: ResumeCountdownDriver {
    private weak var emu: EmulationController?
    init(emu: EmulationController) { self.emu = emu }

    func resume() { emu?.perform { e in e.resume() } }
    /// A pause cancels the resume countdown (EmulationController.paused). The practice countdown has
    /// no cancel (its NES buttons are game input); the catcher is not shown for it.
    func abort() { emu?.perform { e in e.paused = true } }
    func isCounting(_ st: EmuStatus) -> Bool {
        ResumeCountdownStatus.counting(paused: st.paused, countdown: st.countdown, practicing: st.practicing,
                                       practiceLooping: st.practiceLooping)
    }
}

/// Over the picture while the resume countdown runs: ✕ goes back to paused. Touches elsewhere pass
/// through (the rewind / fast-forward quarters stay live). Draws nothing else (the numeral is the renderer's).
struct ResumeCountdownCatcher: View {
    let picture: CGRect
    let onAbort: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.clear.allowsHitTesting(false)
            Button(action: onAbort) {
                Image(systemName: "xmark").font(.system(size: 14, weight: .bold))
                    .frame(width: 32, height: 32)
                    .background(.black.opacity(0.55), in: Circle())
                    .foregroundStyle(.white.opacity(0.85))
                    .touchTarget(width: 32, height: 32)
            }
            .padding(8)
            .accessibilityLabel(L("Cancel Countdown"))
            .accessibilityIdentifier("countdownCancel")
        }
        .frame(width: picture.width, height: picture.height)
        .offset(x: picture.minX, y: picture.minY)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("resumeCountdown")
        .transition(.opacity)
    }
}
