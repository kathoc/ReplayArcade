// Whether the foreground session is playing (written by the emulation thread every tick). Background
// emulation on a core whose instances share one machine (RN_CORE_CAP_SHARES_MACHINE: ReplayArcade's
// FinalBurn Neo, multiplexed by swapping states and games) waits while it is: every switch between the
// two instances costs a swap, and running both made a frame take ~100 ms instead of ~1.4 ms (the library's
// ROM pictures at first launch). As the Linux app (SPEC R3): background renders only while the
// foreground is paused or has no session.
// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation

enum ForegroundPlay {
    private static let lock = NSLock()
    private static var playing_ = false

    static var playing: Bool {
        get { lock.lock(); defer { lock.unlock() }; return playing_ }
        set { lock.lock(); playing_ = newValue; lock.unlock() }
    }

    /// Whether sessions of `kind` share one machine with each other.
    static func sharesMachine(_ kind: rn_core_kind) -> Bool { rn_core_capabilities(kind) & RN_CORE_CAP_SHARES_MACHINE != 0 }

    /// The product's default core (the core of a library ROM's session).
    static var defaultCore: rn_core_kind {
        var o = rn_session_options()
        rn_session_options_init(&o)
        return o.core
    }

    /// Background thread: returns once the foreground is not playing (polls every 0.1 s).
    static func waitUntilIdle() {
        while playing { Thread.sleep(forTimeInterval: 0.1) }
    }
}
