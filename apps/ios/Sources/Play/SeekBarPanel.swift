// Paused: the seek bar (docs/design/UI_REDESIGN.md, "Seek bar while paused", amended by
// docs/design/VTR_UX.md), for touch. A large Play (Continue at the end of the tape; through the
// resume countdown, which says "Retrying from here" before the end of the tape), the status label
// and the time, the ↶ Undo / ▶ Make Video chips when they apply, the track between the frame step
// buttons (drag = scrub: paused, muted, never records; the part ahead of the cursor dimmed), then the
// selected A/B section's tools (slot, Set A / Set B at the playhead - shared TimelineActions - and
// Practice). With a controller connected a hint line names its buttons (cancel = Play, L / R = Step,
// L2 / R2 = Rewind / Fast-forward), as on the desktop. Next to Play the slow-motion toggle (½ speed,
// the controller's L; touch has no L). The controller's marker workflow (SeekMarkers,
// shared) keeps working: its markers are drawn. Playback (watching the tape): Quick Menu › Retry.
// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

struct SeekBarPanel: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var clock = AppModel.shared.clock
    @ObservedObject private var markers = AppModel.shared.markers
    @ObservedObject private var monitor = AppModel.shared.input.controllerMonitor

    var body: some View {
        let st = clock.status
        VStack(spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                resumeButton(st)
                slowButton(st)
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 4) {
                    TapeStatusLabelIOS()
                    times(st)
                }
            }
            if st.canUndo || (st.endOfTape && !st.practicing) {
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    if st.canUndo { UndoChipIOS() }
                    if st.endOfTape && !st.practicing { MakeVideoChipIOS() }
                }
            }
            if let pad = monitor.controllers.min(by: { $0.slot < $1.slot }) { padHints(pad) }
            HStack(spacing: 6) {
                stepButton("backward.frame.fill", L("−1 frame"), String(localized: "Step Back One Frame")) { model.stepFrame(-1) }
                    .accessibilityIdentifier("seekStepBack")
                TimelineTrack(status: st)
                    .frame(height: 36)
                    .accessibilityElement()
                    .accessibilityLabel(L("Timeline"))
                    .accessibilityIdentifier("seekTrack")
                stepButton("forward.frame.fill", L("+1 frame"), String(localized: "Frame Advance")) { model.stepFrame(1) }
                    .accessibilityIdentifier("seekStepForward")
            }
            HStack(spacing: 8) {
                if !st.practicing {
                    Menu {
                        ForEach(0..<EngineSession.practiceSlotCount, id: \.self) { i in
                            Button("A/B \(i + 1) · \(model.practiceSlots[i].displayName)") { model.selectedSlot = i }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Circle().fill(SlotPalette.color(model.selectedSlot)).frame(width: 8, height: 8)
                            Text(verbatim: "A/B \(model.selectedSlot + 1)").font(.system(size: 13, weight: .semibold))
                            Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold)).opacity(0.6)
                        }
                        .padding(.horizontal, 10).frame(height: 36)
                        .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                        .touchTarget(height: 36)
                    }
                    .accessibilityIdentifier("seekSlot")
                    textTool(nil, String(localized: "Set A")) { model.emu.perform { [slot = model.selectedSlot] e in e.timelineMarkA(slot) } }
                        .accessibilityIdentifier("seekSetA")
                    textTool(nil, String(localized: "Set B")) { model.emu.perform { [slot = model.selectedSlot] e in e.timelineMarkB(slot) } }
                        .accessibilityIdentifier("seekSetB")
                    Spacer(minLength: 0)
                    if model.practiceSlots[model.selectedSlot].hasA {
                        textTool("target", String(localized: "Practice")) { model.practiceStart(model.selectedSlot) }
                            .accessibilityIdentifier("seekPractice")
                    }
                } else {
                    Spacer(minLength: 0)
                    textTool("stop.fill", String(localized: "Stop Practicing")) { model.practiceStop() }
                        .accessibilityIdentifier("seekStopPractice")
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.08).opacity(0.92)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("seekBar")
    }

    /// "Play" (at the end of the tape "Continue"): what it goes on with is said under the title.
    static func playTitle(_ st: EmuStatus) -> String {
        st.endOfTape && !st.practicing ? String(localized: "Continue (tape)") : String(localized: "Play")
    }

    /// The primary action: back to the game (what follows named under the title when not plain play).
    private func resumeButton(_ st: EmuStatus) -> some View {
        let mode = Self.resumeDetail(st)
        let title = Self.playTitle(st)
        return Button { model.togglePause() } label: {
            HStack(spacing: 10) {
                Image(systemName: "play.fill").font(.system(size: 18, weight: .bold))
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(.system(size: 16, weight: .bold)).lineLimit(1)
                    if let mode { Text(mode).font(.system(size: 10, weight: .medium)).opacity(0.65).lineLimit(1) }
                }
            }
            .padding(.leading, 14).padding(.trailing, 18).frame(height: 46)
            .foregroundStyle(.black)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
            .fixedSize()
        }
        .accessibilityLabel(title)
        .accessibilityHint(mode ?? "")
        .accessibilityIdentifier("seekResume")
    }

    /// Slow motion (½ ↔ normal, the Slow hotkey's toggle) for the play that follows: lit while on.
    private func slowButton(_ st: EmuStatus) -> some View {
        let on = st.slow != .normal
        return Button { model.toggleSlow() } label: {
            Image(systemName: on ? "tortoise.fill" : "tortoise").font(.system(size: 17, weight: .semibold))
                .frame(width: 46, height: 46)
                .foregroundStyle(on ? Color.black : Color.white)
                .background(on ? Color.green.opacity(0.85) : Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        }
        .accessibilityLabel(L("Slow Motion"))
        .accessibilityValue(on ? st.slow.label : String(localized: "Off"))
        .accessibilityIdentifier("seekSlow")
    }

    /// What Play goes on with (nil: plain play on the tape). docs/design/VTR_UX.md: never "record".
    static func resumeDetail(_ st: EmuStatus) -> String? {
        if st.practicing { return L("Keep practicing") }
        if !st.recording && !st.endOfTape { return L("Keep watching the tape") }
        if Tape.overwrites(mode: st.mode, frame: st.frame, length: st.takeLength) { return String(localized: "Retrying from here") }
        return nil
    }

    private func times(_ st: EmuStatus) -> some View {
        HStack(spacing: 4) {
            Text(verbatim: Engine.timecode(forFrame: st.practicing ? st.practiceFrame : st.frame))
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .accessibilityIdentifier("seekTime")
            Text(verbatim: "/ " + (st.practicing ? (st.practiceLength > 0 ? Engine.timecode(forFrame: st.practiceLength) : "--:--.--")
                                                 : Engine.timecode(forFrame: st.takeLength)))
                .font(.system(size: 12, design: .monospaced)).foregroundStyle(.white.opacity(0.55))
        }
        .fixedSize()
    }

    /// The controller's buttons on the bar (as the desktop's hint row): cancel = Play, L R = Step,
    /// L2 R2 = Rewind / Fast-forward.
    private func padHints(_ pad: ControllerInfo) -> some View {
        let south = UserDefaults.standard.bool(forKey: "southConfirm")
        let back = pad.label(String(cString: rnf_ui_cancel_element(south ? 1 : 0)))
        let ps = pad.family == .playStation
        let rw = model.controlName(for: "hk.rewind") ?? "L2", ff = model.controlName(for: "hk.fast_forward") ?? "R2"
        return HStack(spacing: 14) {
            hint([back], Self.playTitle(clock.status))
            hint([ps ? "L1" : "L", ps ? "R1" : "R"], String(localized: "Step"))
            hint([rw, ff], String(localized: "Rewind") + " / " + String(localized: "Fast-forward"))
            Spacer(minLength: 0)
        }
        .frame(height: 20)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("seekHints")
    }

    private func hint(_ keys: [String], _ verb: String) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, k in
                Text(verbatim: k).font(.system(size: 11, weight: .bold, design: .rounded))
                    .padding(.horizontal, 5).frame(minWidth: 20, minHeight: 20)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.16)))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.22), lineWidth: 1))
            }
            Text(verbatim: verb).font(.system(size: 12)).foregroundStyle(.white.opacity(0.75)).padding(.leading, 2)
        }
        .fixedSize()
    }

    /// Frame step: the icon with a short caption under it (−1 / +1 frame).
    private func stepButton(_ icon: String, _ caption: String, _ label: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            VStack(spacing: 1) {
                Image(systemName: icon).font(.system(size: 14, weight: .semibold))
                Text(caption).font(.system(size: 9, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7).opacity(0.75)
            }
            .frame(width: 50, height: 44)
            .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
        }
        .accessibilityLabel(label)
    }

    private func textTool(_ icon: String?, _ label: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            HStack(spacing: 5) {
                if let icon { Image(systemName: icon).font(.system(size: 12, weight: .semibold)) }
                Text(label).font(.system(size: 13, weight: .semibold)).lineLimit(1)
            }
            .padding(.horizontal, 10).frame(height: 36)
            .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
            .touchTarget(height: 36)
        }
        .accessibilityLabel(label)
    }
}

/// The tape as a track: recorded length, A/B sections on this take, controller markers, playhead.
/// Drag = scrub.
struct TimelineTrack: View {
    @EnvironmentObject var model: AppModel
    let status: EmuStatus
    @State private var dragging = false

    var body: some View {
        GeometryReader { geo in
            let w = max(1, geo.size.width)
            let len = max(1, Double(status.practicing ? max(status.practiceLength, status.practiceFrame) : status.takeLength))
            let cursor = Double(status.practicing ? status.practiceFrame : status.frame)
            let x = { (f: UInt64) in CGFloat(Double(f) / len) * w }
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.14)).frame(height: 8)
                // Played up to the cursor: bright; the recorded part ahead of it stays dimmed.
                RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.32))
                    .frame(width: CGFloat(max(0, min(1, cursor / len))) * w, height: 8)
                if !status.practicing {
                    let ranges = TimelineEditing.visibleRanges(slots: model.practiceSlots, takes: model.takes,
                                                               activeTake: status.activeTake, takeLength: status.takeLength)
                    ForEach(Array(ranges.enumerated()), id: \.offset) { _, r in
                        let a = x(r.a), b = r.b.map(x) ?? a + 3
                        Rectangle().fill(SlotPalette.color(r.slot).opacity(r.slot == model.selectedSlot ? 0.85 : 0.45))
                            .frame(width: max(3, b - a), height: r.slot == model.selectedSlot ? 14 : 8)
                            .offset(x: a)
                    }
                    ForEach(Array(model.markers.frames.enumerated()), id: \.offset) { i, f in
                        Rectangle().fill(model.markers.focus == i ? Color.white : Color.white.opacity(0.6))
                            .frame(width: 2, height: 22).offset(x: x(f) - 1)
                    }
                }
                // One tape: a neutral playhead (never the red of recording).
                RoundedRectangle(cornerRadius: 1.5).fill(Color.white)
                    .frame(width: 3, height: 26)
                    .offset(x: CGFloat(cursor / len) * w - 1.5)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                guard !status.practicing, status.takeLength > 0 else { return }
                dragging = true
                let f = UInt64(max(0, min(1, g.location.x / w)) * Double(status.takeLength))
                model.scrub(to: f)
            }.onEnded { _ in dragging = false })
        }
    }
}
