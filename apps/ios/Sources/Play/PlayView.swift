// The play screen: the game + touch controls (PlaySurface, UIKit) under small SwiftUI overlays:
// status badges and notices at the top of the picture, the practice pill, the latency meter and,
// while paused, the seek bar (SeekBarPanel). The Quick Menu goes over everything.
// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

struct PlayView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var crt = CRTSettingsModel.shared

    var body: some View {
        // The surface and the overlay layer each fill the whole screen (safe area ignored) in the
        // same coordinate space: the overlays are placed with the surface's layout (points).
        // Everything is sized from the screen (the proxy), never from the published layout: that
        // one is the previous orientation's for a moment after a rotation, and sizing the overlays
        // with it made the ZStack the union of both orientations (874 x 874), which the surface
        // then laid out for - and kept, rotation after rotation.
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                PlaySurface(model: model, displayOptions: model.displayOptions, touchOptions: model.touchOptions,
                            controlsVisible: model.touchControlsVisible && !model.quickMenu.isOpen,
                            opacity: model.touchOpacity, haptics: model.touchHaptics,
                            followX: model.touchFollowX, followY: model.touchFollowY)
                    .frame(width: geo.size.width, height: geo.size.height)
                // A layout for another size is stale (mid-rotation): the overlays wait for the new one.
                if let l = model.playLayout, abs(l.size.width - geo.size.width) < 1, abs(l.size.height - geo.size.height) < 1 { overlays(l) }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .clipped()
        }
        .ignoresSafeArea(.all, edges: .all)
        .background(Color.black.ignoresSafeArea())
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .defersSystemGestures(on: .all)
    }

    @ViewBuilder
    private func overlays(_ l: TouchLayout) -> some View {
        let game = l.gameArea
        let picture = pictureRect(l)
        let st = model.status
        // Top of the picture: badges, notice.
        VStack(spacing: 6) {
            StatusBadgesIOS()
            if let n = model.notice {
                Text(n).font(.system(size: 13, weight: .medium)).multilineTextAlignment(.center)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(.white)
                    .accessibilityIdentifier("notice")
                    .transition(.opacity)
            }
            if st.practicing { PracticePill() }
            if model.showLatency { LatencyText() }
        }
        .frame(width: max(200, picture.width - 16))
        .position(x: picture.midX, y: picture.minY + 8 + 60)
        .frame(width: l.size.width, height: l.size.height, alignment: .topLeading)
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.15), value: model.notice)

        // Paused: the seek bar over the bottom of the game area (its bottom edge 8 pt above the
        // area's; it grows upwards). The resume countdown is not paused: the bar goes for it.
        if st.hasSession && st.paused && !model.quickMenu.isOpen {
            SeekBarPanel()
                .frame(width: min(l.landscape ? max(picture.width, game.width - 16) : game.width - 16, 640))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 8)
                .frame(width: game.width, height: game.height, alignment: .bottom)
                .offset(x: game.minX, y: game.minY)
                .frame(width: l.size.width, height: l.size.height, alignment: .topLeading)
                .transition(.opacity)
        }
        // The resume countdown (drawn by the renderer): a tap on the picture or ✕ goes back to paused.
        if st.hasSession && model.resumeCountdownShown && !model.quickMenu.isOpen {
            ResumeCountdownCatcher(picture: picture) { model.abortResumeCountdown() }
                .frame(width: l.size.width, height: l.size.height, alignment: .topLeading)
        }
        // Without touch controls (a controller is connected) the menu stays reachable.
        if !model.touchControlsVisible && !model.quickMenu.isOpen {
            Button { model.quickMenu.open() } label: {
                Image(systemName: "line.3.horizontal").font(.system(size: 16, weight: .semibold))
                    .padding(10).background(.black.opacity(0.5), in: Circle()).foregroundStyle(.white.opacity(0.8))
                    .touchTarget(width: 38, height: 38)
            }
            .accessibilityLabel(String(localized: "Menu"))
            .accessibilityIdentifier("menuButton")
            .position(x: l.size.width - 40, y: max(40, game.minY + 30))
        }
        if model.quickMenu.isOpen {
            TouchQuickMenu(menu: model.quickMenu, monitor: model.input.controllerMonitor)
                .frame(width: l.size.width, height: l.size.height)
                .transition(.opacity)
        }
    }

    /// The picture inside the game area (points), as the renderer places it.
    private func pictureRect(_ l: TouchLayout) -> CGRect {
        let scale = UIScreen.main.nativeScale
        let px = CGSize(width: l.gameArea.width * scale, height: l.gameArea.height * scale)
        let (r, _) = GameRenderer.viewport(drawableSize: px, options: model.displayOptions)
        // viewport() is bottom-left based; flip into the top-left based game area.
        return CGRect(x: l.gameArea.minX + r.minX / scale, y: l.gameArea.minY + (px.height - r.maxY) / scale,
                      width: r.width / scale, height: r.height / scale)
    }
}

/// REC / REPLAY / PRACTICE, slow, fast-forward, rewind, flash reduction.
struct StatusBadgesIOS: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let st = model.status
        HStack(spacing: 6) {
            if st.hasSession {
                if st.practicing { badge(String(localized: "Practicing"), .orange) }
                else if st.recording { badge("● REC", .red) }
                else { badge("▶ REPLAY", .blue) }
                if st.slow != .normal { badge(st.slow == .half ? "1/2" : "1/4", .purple) }
                if st.rewinding { badge("◀◀", .white.opacity(0.4)) }
                if st.fastForward { badge("▶▶", .white.opacity(0.4)) }
                if st.flashActive && model.showFlashIndicator { badge("⚡︎", .yellow.opacity(0.7)) }
            }
        }
    }

    private func badge(_ t: String, _ c: Color) -> some View {
        Text(t).font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(.white)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(c.opacity(0.75), in: Capsule())
    }
}

struct PracticePill: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var clock = AppModel.shared.clock

    var body: some View {
        let st = clock.status
        let name = st.practiceSlot >= 0 && st.practiceSlot < model.practiceSlots.count
            ? "\(st.practiceSlot + 1). " + model.practiceSlots[st.practiceSlot].displayName : String(localized: "Practicing")
        let len = st.practiceLength > 0 ? Engine.timecode(forFrame: st.practiceLength) : "--:--.--"
        HStack(spacing: 8) {
            Image(systemName: "target").foregroundStyle(SlotPalette.color(max(0, st.practiceSlot)))
            Text(name).lineLimit(1)
            Text(verbatim: "\(Engine.timecode(forFrame: st.practiceLength > 0 ? min(st.practiceFrame, st.practiceLength) : st.practiceFrame)) / \(len)")
                .font(.system(.caption, design: .monospaced)).foregroundStyle(.white.opacity(0.65))
        }
        .font(.system(size: 12, weight: .medium)).foregroundStyle(.white)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(.black.opacity(0.6), in: Capsule())
    }
}

/// The A/B slot colours (as the macOS timeline's SlotColors).
enum SlotPalette {
    static let colors: [Color] = [.red, .orange, .yellow, .green, .mint, .cyan, .blue, .purple]
    static func color(_ i: Int) -> Color { colors[((i % colors.count) + colors.count) % colors.count] }
}

struct LatencyText: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        let s = model.stats
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: s.pacing.isEmpty ? "—" : s.pacing)
            Text(verbatim: String(format: "emu %.1f fps · shown %.1f fps · lead %.1f ms", s.emulatedFPS, s.presentedFPS, s.inputLeadMs))
            Text(verbatim: String(format: "sample→screen %.1f ms · hitches %llu · dropped %llu", s.sampleToPresentMs, s.presentHitches, s.droppedFrames))
            Text(verbatim: String(format: "audio %.1f ms · underruns %llu · ratio %.4f", s.audioFillMs, s.audioUnderruns, s.audioRatio))
        }
        .font(.system(size: 10, design: .monospaced)).foregroundStyle(.green)
        .padding(6).background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
    }
}
