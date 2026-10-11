// Paused: the seek bar (docs/design/UI_REDESIGN.md, "Seek bar while paused"), for touch. A large
// labelled Resume (goes on in the current mode, said under it: recording / watching the replay /
// practicing; through the resume countdown), the time, the track between the frame step buttons
// (drag = scrub: paused, muted, replays the take, never records), then the selected A/B section's
// tools (slot, Set A / Set B at the playhead - shared TimelineActions - and Practice). With a
// controller connected a hint line names its buttons (cancel = Resume, L / R = Step), as on the
// desktop. The controller's marker workflow (SeekMarkers, shared) keeps working: its markers are drawn.
// Watching the recorded take is not here: Quick Menu › Retry › Watch Replay.
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
                Spacer(minLength: 4)
                times(st)
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

    /// The primary action: back to the game, in the current mode (named under the title).
    private func resumeButton(_ st: EmuStatus) -> some View {
        let mode = Self.resumeDetail(st)
        return Button { model.togglePause() } label: {
            HStack(spacing: 10) {
                Image(systemName: "play.fill").font(.system(size: 18, weight: .bold))
                VStack(alignment: .leading, spacing: 0) {
                    Text(String(localized: "Resume")).font(.system(size: 16, weight: .bold)).lineLimit(1)
                    Text(mode).font(.system(size: 10, weight: .medium)).opacity(0.65).lineLimit(1)
                }
            }
            .padding(.leading, 14).padding(.trailing, 18).frame(height: 46)
            .foregroundStyle(.black)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
            .fixedSize()
        }
        .accessibilityLabel(String(localized: "Resume"))
        .accessibilityHint(mode)
        .accessibilityIdentifier("seekResume")
    }

    /// What Resume goes on with.
    static func resumeDetail(_ st: EmuStatus) -> String {
        if st.practicing { return L("Keep practicing") }
        if st.recording { return L("Keep recording") }
        if RecordToggle.shouldRestartOnPlay(recording: false, practicing: false, frame: st.frame, takeLength: st.takeLength) {
            return L("Watch the replay from the start")
        }
        return L("Keep watching the replay")
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

    /// The controller's buttons on the bar (as the desktop's hint row): cancel = Resume, L R = Step.
    private func padHints(_ pad: ControllerInfo) -> some View {
        let south = UserDefaults.standard.bool(forKey: "southConfirm")
        let back = pad.label(String(cString: rnf_ui_cancel_element(south ? 1 : 0)))
        let ps = pad.family == .playStation
        return HStack(spacing: 14) {
            hint([back], String(localized: "Resume"))
            hint([ps ? "L1" : "L", ps ? "R1" : "R"], String(localized: "Step"))
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

/// The take as a track: recorded length, A/B sections on this take, controller markers, playhead.
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
                RoundedRectangle(cornerRadius: 1.5).fill(Color(red: 1, green: 0.23, blue: 0.23))
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
