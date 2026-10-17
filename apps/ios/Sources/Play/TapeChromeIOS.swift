// The VTR transport's small pieces over the game on iPhone (docs/design/VTR_UX.md; the macOS
// counterpart is apps/macos/Sources/App/Views/TapeChrome.swift): the bottom-left status label
// (non-default states only: Playback, Practice, Rewind, Fast-forward, Slow, End of tape, the video
// being made), the "↶ Undo" chip for 10 s after a retry, the "▶ Make Video" chip at the end of the
// tape, and the read-only tape strip shown while Rewind / Fast-forward is held during play.
// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

/// The status label; nothing when there is nothing to say (normal play). Practicing, it is the
/// "■ Stop Practice" button (tap; Y on a controller), then the rest of the label (as on the Mac).
struct TapeStatusLabelIOS: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        if model.status.hasSession && model.status.practicing {
            HStack(spacing: 8) {
                TapeChipIOS(title: String(localized: "■ Stop Practice")) { model.practiceStop() }
                    .accessibilityIdentifier("stopPracticeChip")
                let rest = model.status.tapeLabelBesidePractice
                if !rest.isEmpty { TapeLabelTextIOS(text: rest) }
            }
        } else {
            label
        }
    }

    @ViewBuilder private var label: some View {
        let base = model.status.hasSession ? model.status.tapeLabel : ""
        if let job = model.exportJob, !job.finished {
            ExportProgressLabelIOS(job: job, base: base)
        } else if !base.isEmpty {
            TapeLabelTextIOS(text: base)
        }
    }
}

/// "… · Making video… 42%" while an export runs.
private struct ExportProgressLabelIOS: View {
    @ObservedObject var job: ExportJob
    let base: String

    var body: some View {
        let pct = job.total == 0 ? 0 : Int(Double(job.done) * 100 / Double(job.total))
        let making = String(localized: "Making video… \(pct)%")
        TapeLabelTextIOS(text: base.isEmpty ? making : base + " · " + making)
    }
}

struct TapeLabelTextIOS: View {
    let text: String
    var body: some View {
        Text(verbatim: text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white.opacity(0.92))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(Capsule().fill(Color(red: 0.08, green: 0.08, blue: 0.09).opacity(0.72)))
            .allowsHitTesting(false)
            .accessibilityIdentifier("tapeLabel")
    }
}

/// A small tappable capsule (the Undo / Make Video chips).
struct TapeChipIOS: View {
    let title: String
    var glyph: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(verbatim: title).font(.system(size: 14, weight: .semibold))
                if let glyph { KeyCapIOS(glyph) }
            }
            .foregroundStyle(Color.white.opacity(0.95))
            .padding(.leading, 12).padding(.trailing, glyph == nil ? 12 : 6)
            .frame(height: 32)
            .background(Capsule().fill(Color(red: 0.08, green: 0.08, blue: 0.09).opacity(0.82)))
            .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1))
            .fixedSize()
            .touchTarget(height: 32)
        }
        .buttonStyle(.plain)
        .environment(\.colorScheme, .dark)
    }
}

/// "↶ Undo": back to before the last retry. With a controller it names the button bound to
/// hk.undo_take (L3 by default).
struct UndoChipIOS: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var monitor = AppModel.shared.input.controllerMonitor

    var body: some View {
        let pad = !monitor.controllers.isEmpty
        return TapeChipIOS(title: String(localized: "↶ Undo"), glyph: pad ? model.controlName(for: "hk.undo_take") : nil) {
            model.undoRetry()
        }
        .accessibilityIdentifier("undoChip")
    }
}

/// "▶ Make Video" (paused at the end of the tape): opens the Make Video sheet.
struct MakeVideoChipIOS: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        TapeChipIOS(title: String(localized: "▶ Make Video")) { model.requestExport() }
            .accessibilityIdentifier("makeVideoChip")
    }
}

/// Rewind / fast-forward held during play: the tape strip, read-only (label, time, track).
struct TapeStripReadOnly: View {
    @ObservedObject private var clock = AppModel.shared.clock

    var body: some View {
        let st = clock.status
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                TapeStatusLabelIOS()
                Spacer(minLength: 4)
                Text(verbatim: Engine.timecode(forFrame: st.frame) + " / " + Engine.timecode(forFrame: st.takeLength))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
            }
            TimelineTrack(status: st).frame(height: 24)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.08).opacity(0.85)))
        .environment(\.colorScheme, .dark)
        .allowsHitTesting(false)
        .accessibilityIdentifier("tapeStrip")
    }
}
