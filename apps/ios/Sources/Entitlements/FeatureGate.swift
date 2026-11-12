// Feature gating for future paid unlocks (README.md, "Free and unlocked features").
// Core-agnostic and pure: no engine, UI or StoreKit types, so the policy is unit-tested
// (Tests/FeatureGateTests.swift) and the same rules can later be ported to other frontends.
//
// Free: play, rewind, fast-forward through what was played, pause / frame step / slow motion,
// practice (A/B repeat), replay and takes of the CURRENT session, flash reduction, touch and game
// controllers. The session lives in the single temporary slot (autosaved and resumed after the app
// is closed or killed) and is replaced when another game starts.
// Paid:
//   .recording  keep recordings: every library game starts its own project in Projects/ (kept,
//               listed per game, openable on the Mac too), Save / Save As, keeping the previous
//               temporary session when another game starts.
//   .mp4Export  Share › Export MP4.
//   .crt        the physical CRT display model (Settings › Display › CRT, CRT Details).
// Never locked: opening projects that already exist (made while unlocked or on the Mac), resume,
// settings, controller assignment. Locking never deletes or hides user data.
// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation

enum PaidFeature: String, CaseIterable, Codable, Identifiable {
    case recording
    case mp4Export
    case crt

    var id: String { rawValue }
}

/// What the user may use right now. `debugUnlockAll` is the prototype's switch (on by default:
/// nothing is sold yet); `purchased` comes from the purchase store (StoreKit later).
struct EntitlementState: Equatable, Codable {
    var purchased: Set<PaidFeature> = []
    var debugUnlockAll = true

    func isUnlocked(_ f: PaidFeature) -> Bool { debugUnlockAll || purchased.contains(f) }

    static let allUnlocked = EntitlementState(purchased: Set(PaidFeature.allCases), debugUnlockAll: false)
    static let free = EntitlementState(purchased: [], debugUnlockAll: false)
}

/// The app's gated decisions. Each names the feature it needs.
enum GatedAction: CaseIterable {
    case startLibraryProject   // library "Play": a new kept project instead of the temporary slot
    case save                  // Save / Save As (also: keep a temporary session as a project)
    case keepPreviousSession   // starting another game offers to keep the temporary session
    case exportMP4
    case crtDisplay

    var feature: PaidFeature {
        switch self {
        case .startLibraryProject, .save, .keepPreviousSession: return .recording
        case .exportMP4: return .mp4Export
        case .crtDisplay: return .crt
        }
    }
}

enum FeatureGate {
    static func allows(_ a: GatedAction, _ e: EntitlementState) -> Bool { e.isUnlocked(a.feature) }

    /// Where a game started from the library is recorded.
    enum SessionTarget: Equatable {
        case temporary        // the single temporary slot (free)
        case newProject       // Projects/<ROM name> <date>.nesrec (recording unlocked)
    }

    static func sessionTarget(forLibraryPlay e: EntitlementState) -> SessionTarget {
        allows(.startLibraryProject, e) ? .newProject : .temporary
    }

    /// Starting another game while a temporary session with recorded content exists:
    /// unlocked = ask whether to keep it (Save / Don't Save / Cancel); free = it is replaced
    /// (the user is told once, with the unlock offer).
    enum PreviousSession: Equatable {
        case nothingToAsk
        case askKeep
        case replace
    }

    static func previousSession(hasContent: Bool, _ e: EntitlementState) -> PreviousSession {
        guard hasContent else { return .nothingToAsk }
        return allows(.keepPreviousSession, e) ? .askKeep : .replace
    }

    /// The CRT setting as the renderer must see it: the stored choice is kept (so unlocking
    /// restores it) but has no effect while locked.
    static func effectiveCRT(stored: Bool, _ e: EntitlementState) -> Bool { stored && allows(.crtDisplay, e) }

    /// Export may apply the CRT effect only with both unlocks.
    static func exportCRTAllowed(_ e: EntitlementState) -> Bool { allows(.exportMP4, e) && allows(.crtDisplay, e) }
}
