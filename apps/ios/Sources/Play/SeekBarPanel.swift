// Paused: the seek bar (docs/design/UI_REDESIGN.md, "Seek bar while paused"), for touch. Drag
// the track to scrub (paused, muted: replays the take, never records), step one frame, put A / B
// of the selected section at the playhead (shared TimelineActions), practice it, resume. The
// controller's marker workflow (SeekMarkers, shared) keeps working alongside: its markers are drawn.
// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

struct SeekBarPanel: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var clock = AppModel.shared.clock
    @ObservedObject private var markers = AppModel.shared.markers

    var body: some View {
        let st = clock.status
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button { model.togglePause() } label: {
                    Image(systemName: "play.fill").font(.system(size: 18, weight: .bold)).frame(width: 44, height: 36)
                        .background(Color.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 9))
                }
                .accessibilityLabel(String(localized: "Resume"))
                Text(verbatim: Engine.timecode(forFrame: st.practicing ? st.practiceFrame : st.frame))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced)).fixedSize()
                TimelineTrack(status: st)
                    .frame(height: 30)
                Text(verbatim: st.practicing ? (st.practiceLength > 0 ? Engine.timecode(forFrame: st.practiceLength) : "--:--.--")
                                             : Engine.timecode(forFrame: st.takeLength))
                    .font(.system(size: 12, design: .monospaced)).foregroundStyle(.white.opacity(0.6)).fixedSize()
            }
            HStack(spacing: 8) {
                tool("backward.frame.fill", String(localized: "Step Back One Frame")) { model.stepFrame(-1) }
                tool("forward.frame.fill", String(localized: "Frame Advance")) { model.stepFrame(1) }
                Spacer(minLength: 4)
                if !st.practicing {
                    Menu {
                        ForEach(0..<EngineSession.practiceSlotCount, id: \.self) { i in
                            Button("A/B \(i + 1) · \(model.practiceSlots[i].displayName)") { model.selectedSlot = i }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Circle().fill(SlotPalette.color(model.selectedSlot)).frame(width: 8, height: 8)
                            Text(verbatim: "A/B \(model.selectedSlot + 1)").font(.system(size: 13, weight: .semibold))
                        }
                        .padding(.horizontal, 10).frame(height: 34)
                        .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                    }
                    textTool(String(localized: "Set A")) { model.emu.perform { [slot = model.selectedSlot] e in e.timelineMarkA(slot) } }
                    textTool(String(localized: "Set B")) { model.emu.perform { [slot = model.selectedSlot] e in e.timelineMarkB(slot) } }
                    if model.practiceSlots[model.selectedSlot].hasA {
                        tool("target", String(localized: "Practice")) { model.practiceStart(model.selectedSlot) }
                    }
                } else {
                    textTool(String(localized: "Stop Practicing")) { model.practiceStop() }
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.08).opacity(0.92)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }

    private func tool(_ icon: String, _ label: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Image(systemName: icon).font(.system(size: 15, weight: .semibold)).frame(width: 44, height: 34)
                .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
        }
        .accessibilityLabel(label)
    }

    private func textTool(_ label: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Text(label).font(.system(size: 13, weight: .semibold)).lineLimit(1).padding(.horizontal, 10).frame(height: 34)
                .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
        }
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
