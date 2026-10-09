// Swift port of NESTERM web/brickboy/input.mjs — the on-screen touch gamepad of Brickboy
// (upstream kathoc/brickboy @ 9f26b5a2f9d598caff72b4192e0e6bc15ac990e5, src/ui/input.ts) with the
// NESTERM modifications of 2026-10-05 (roll-tap reading of the A/B pad). Translated function by
// function: names, constants, state and the order of every step are the original's; each
// declaration says which JS function it is. Only the browser plumbing is replaced (see
// apps/ios/docs/TOUCH_PORT.md for the table of mappings and the deliberate deviations):
//   - DOM elements / getBoundingClientRect  -> TouchGamepad.Geometry (TouchLayout, points)
//   - PointerEvent (pointerId, clientX/Y, timeStamp) -> PointerEvent (UITouch identity, location
//     in the play surface, UITouch.timestamp in ms) - TouchControlsView feeds them
//   - requestAnimationFrame / cancelAnimationFrame -> the same API here, run by the view's
//     CADisplayLink at 60 Hz (animationFrame(now:))
//   - classList gp-active / style.transform -> isActive(_:) / ox, oy, read by TouchControlsView
//   - navigator.vibrate(HAPTIC_MS) / the iOS <input switch> Taptic -> onHaptic (UIKit impact)
// Not ported (diagnostics of the web build, no iPhone equivalent needed): the debug overlay
// canvas, the gesture / face-event recording and export, probe(), the CSS rotation option, the
// keyboard path (handleKey) and the A/B autofire ring.
//
// Copyright 2026 Katsuya Hokamura. Licensed under the Apache License, Version 2.0
// (apps/ios/ThirdParty/brickboy/LICENSE); modified for ReplayNES (Swift port, 2026).
// SPDX-License-Identifier: Apache-2.0
import CoreGraphics
import Foundation

/// buttons.mjs `Button`: adapter identifiers matching Brickboy src/emu/joypad.ts. These are
/// identifiers, not NES bit masks (TouchControlsView maps them to the touch input ids).
enum BBButton: Int, CaseIterable, Hashable {
    case right = 0, left = 1, up = 2, down = 3, a = 4, b = 5, select = 6, start = 7
}

// ---- D-pad feel constants (input.mjs, top of file; values and names unchanged) ----
let R_COMMIT_OF_REACH: CGFloat = 0.6
let R_COMMIT_MIN: CGFloat = 0.12 // pad radii
let R_COMMIT_MAX: CGFloat = 0.3 // pad radii
let REACH_DEFAULT: CGFloat = 0.45 // assumed reach (pad radii) before any taps are in
let DZ_OF_REACH: CGFloat = 0.25
let DZ_MIN: CGFloat = 0.08 // pad radii
let DZ_MAX: CGFloat = 0.2 // pad radii
let SPEED_STILL: CGFloat = 0.06 // px/ms below which home-calibration may run
let R_TARGET: CGFloat = 0.28
let R_MAX_TARGET: CGFloat = 0.6
let CARD_HALF_ENGAGE: CGFloat = 29.25 // 65% of the circle to the cardinals
let CARD_HALF_HELD: CGFloat = 22.5 // an even 50/50 once engaged
let SHARE_RAMP_TICKS: CGFloat = 18 // ~300 ms of calibration ticks to relax across
let CARD_HALF_4WAY: CGFloat = 45
let R_COMMIT_4WAY: CGFloat = 1.6 // multiplies the commit radius (and its clamps)
let ANGLE_HYST: CGFloat = 6 // extra degrees to leave a sector — only while nearly still
let HOME_LEAK: CGFloat = 1.2 // per-second rate the home folds toward the finger
let HOME_LEAK_X: CGFloat = 1 // 横も縦と同じ率で較正する
let HOME_MAX_X: CGFloat = 0.4 // max horizontal home offset, in pad radii
let HOME_MAX_Y: CGFloat = 0.55 // max vertical home offset, in pad radii
let RELAX_ON_TURN: CGFloat = 0.6
let HOME_RETURN_DELAY: Double = 260 // ms of complete stillness before the return starts
let HOME_RETURN_TAU: Double = 420 // ms time-constant of the ease once it does
let TD_DECAY: CGFloat = 0.92 // per touchdown — an effective window of ~12 recent taps
let TD_MIN_W: CGFloat = 2.5 // accumulated weight before the estimate is acted on
let TD_GAIN: CGFloat = 0.3
let TD_LEAK: CGFloat = 0.03
let EDGE_MARGIN: CGFloat = 8 // px the pad must stay inside the viewport
let HAPTIC_MS = 8 // weak tick on each press edge (navigator.vibrate duration; see onHaptic)
// A/B shared pad (input.mjs; NESTERM roll-tap additions ROLL_*).
let FACE_THR: CGFloat = 0.62
let FACE_LATCH_TRAVEL: CGFloat = 0.3 // fraction of the centre separation
let FACE_HYST: CGFloat = 1.12
let ROLL_RETURN: CGFloat = 0.08
let ROLL_ENGAGE: CGFloat = 0.12
let ROLL_WINDOW_MS: Double = 160

private func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat { v < lo ? lo : v > hi ? hi : v }
private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }

/// input.mjs `DIR8`: eight directions on the pad, centre angle (screen degrees: 0 = right,
/// 90 = down) and the button(s) each engages.
enum Dir8: String, CaseIterable {
    case R, DR, D, DL, L, UL, U, UR

    var c: CGFloat {
        switch self {
        case .R: return 0
        case .DR: return 45
        case .D: return 90
        case .DL: return 135
        case .L: return 180
        case .UL: return 225
        case .U: return 270
        case .UR: return 315
        }
    }

    var btns: [BBButton] {
        switch self {
        case .R: return [.right]
        case .DR: return [.down, .right]
        case .D: return [.down]
        case .DL: return [.down, .left]
        case .L: return [.left]
        case .UL: return [.up, .left]
        case .U: return [.up]
        case .UR: return [.up, .right]
        }
    }
}

/// input.mjs `halfOf`: half-width of one sector, given how much of the circle the cardinals hold.
func halfOf(_ name: Dir8, _ cardHalf: CGFloat) -> CGFloat { name.btns.count == 2 ? 45 - cardHalf : cardHalf }
/// input.mjs `DIR8_ORDER`.
let DIR8_ORDER: [Dir8] = [.R, .DR, .D, .DL, .L, .UL, .U, .UR]
/// input.mjs `DIR8_SETS` / `NO_DIRS`.
let DIR8_SETS: [Dir8: Set<BBButton>] = Dictionary(uniqueKeysWithValues: DIR8_ORDER.map { ($0, Set($0.btns)) })
let NO_DIRS: Set<BBButton> = []

/// input.mjs `norm360` (JS % keeps the dividend's sign, as truncatingRemainder does).
func norm360(_ deg: CGFloat) -> CGFloat { (deg.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) }
/// input.mjs `angularDist`.
func angularDist(_ a: CGFloat, _ b: CGFloat) -> CGFloat {
    let d = abs(norm360(a) - norm360(b))
    return d > 180 ? 360 - d : d
}
/// input.mjs `sectorRaw`: raw sector for an angle, ignoring hysteresis. Bands tile the circle exactly.
func sectorRaw(_ angle: CGFloat, _ cardHalf: CGFloat) -> Dir8 {
    for name in DIR8_ORDER where angularDist(angle, name.c) <= halfOf(name, cardHalf) { return name }
    return .R // unreachable (bands tile 360°), keeps the type total
}

/// One pointer event (PointerEvent): `id` = pointerId (the UITouch), `x`/`y` = clientX/clientY
/// (points in the play surface, which covers the whole window like the web viewport), `t` =
/// timeStamp in ms (UITouch.timestamp; the same clock as the display link's frames).
struct PointerEvent {
    var id: Int
    var x: CGFloat
    var y: CGFloat
    var t: Double
}

/// Per-active-pointer D-pad tracking (input.mjs `DpadPtr`: position history, speed, current
/// sector). A class: the JS mutates the object in place.
final class DpadPtr {
    var lastX: CGFloat
    var lastY: CGFloat
    var lastT: Double
    var seenT: Double
    var speed: CGFloat = 0
    var dir8: Dir8?
    var calibDir: Dir8?
    var heldTicks = 0
    var accDX: CGFloat = 0
    var accDY: CGFloat = 0
    var dirs: Set<BBButton> = NO_DIRS

    init(lastX: CGFloat, lastY: CGFloat, lastT: Double) {
        self.lastX = lastX
        self.lastY = lastY
        self.lastT = lastT
        seenT = lastT
    }
}

/// NESTERM roll state per face pointer (input.mjs `rollTap`'s `roll` object).
final class FaceRoll {
    var base: BBButton
    var on: Bool
    var hist: [(t: Double, s: CGFloat)] = []
    var low = CGFloat.infinity
    var ext = -CGFloat.infinity
    var released = false
    var s: CGFloat = 0

    init(base: BBButton, on: Bool) {
        self.base = base
        self.on = on
    }
}

final class TouchGamepad {
    /// Where the DOM elements are (points, the play surface's coordinates). JS reads these from
    /// getBoundingClientRect on every use; here TouchLayout computes them from the same CSS.
    struct Geometry: Equatable {
        /// window.innerWidth / innerHeight (elemViewport).
        var viewport: CGSize = .zero
        /// The .bb-root content box (frameRect): where the pad may be placed.
        var frame: CGRect = .zero
        /// The .gp-dpad box at its natural place (before transform: translate(ox, oy)).
        var dpad: CGRect = .zero
        /// Hit boxes of the .gp-dpad children .gp-ext-up / .gp-ext-down: 34% of the pad's height
        /// above and below it, moving with it.
        var dpadExtFraction: CGFloat = 0.34
        /// Portrait: .bb-gamepad's box (clip-path: inset(0) also clips the hit targets); nil in
        /// landscape, where .bb-gamepad is display: contents.
        var dpadClip: CGRect?
        /// The .gp-face box (padding included): the A/B shared pad's hit area.
        var face: CGRect = .zero
        /// Centres of .gp-a / .gp-b with their translateY(∓--gp-off), not pressed.
        var a: CGPoint = .zero
        var b: CGPoint = .zero
        /// .gp-system's box in portrait (one hit area over both pills); nil in landscape, where it
        /// is display: contents and only the pills themselves take touches.
        var system: CGRect?
        var select: CGRect = .zero
        var start: CGRect = .zero
        /// .gp-round.gp-active { --gp-press: -3px } and `transition: transform .06s`: a pressed
        /// round moves 3 px up, easing over 60 ms - getBoundingClientRect (faceGeometry) sees it.
        var pressOffset: CGFloat = -3
        var pressTransitionMs: Double = 60
        /// .gp-edge-left { left: -4px }: how far the left glow bar reaches outside the pad.
        var edgeLeftOutset: CGFloat = -4
    }

    /// Which element a pointer went down on (the element that holds its pointer capture).
    enum Region: Equatable { case dpad, face, system }

    let press: (BBButton, Bool) -> Void
    /// Optional per-gesture feedback hook (audio tick); fires once per batch on the same edge as
    /// the haptic, so a diagonal ticks once.
    var feedback: ((BBButton) -> Void)?
    /// navigator.vibrate(HAPTIC_MS) / the hidden switch's Taptic tick (haptic()).
    var onHaptic: (() -> Void)?
    /// Something visible changed: a gp-active class or the pad's transform.
    var onVisual: (() -> Void)?
    /// A requestAnimationFrame callback is waiting: start the display link.
    var onAnimationFrameRequest: (() -> Void)?

    var geometry = Geometry()
    /// Live press count per button (all sources); edges drive press + visual.
    private(set) var counts: [BBButton: Int] = [:]
    /// State for each active D-pad pointer (position → direction, plus home calib).
    private(set) var dpadPtrs: [Int: DpadPtr] = [:]
    /// Insertion order of dpadPtrs (a JS Map iterates in insertion order: values().next()).
    private var dpadOrder: [Int] = []
    /// A/B currently engaged by each active face pointer (proximity → set).
    private(set) var facePointers: [Int: Set<BBButton>] = [:]
    private var facePointerOrder: [Int] = []
    /// NESTERM roll state per face pointer.
    private(set) var faceRoll: [Int: FaceRoll] = [:]
    /// Pointers latched to one button by the second-finger rule, with the point they landed on.
    private(set) var faceLatch: [Int: (btn: BBButton, x: CGFloat, y: CGFloat)] = [:]
    /// Start/Select engaged by each active system pointer (proximity → set).
    private(set) var sysPointers: [Int: Set<BBButton>] = [:]
    /// Pointer capture: the region each pointer went down on.
    private var captured: [Int: Region] = [:]
    /// Current home offset (px) from the pad's natural CSS centre, via transform.
    private(set) var ox: CGFloat = 0
    private(set) var oy: CGFloat = 0
    /// rAF id for the post-release ease back to centre (0 = not running).
    private var homingRaf = 0
    private var homeTickLast: Double = 0
    /// rAF id for the while-held calibration clock (0 = not running).
    private var calibRaf = 0
    private var calibLast: Double = 0
    /// Decaying touchdown sums behind the rest estimate (see foldTouchdown).
    private(set) var tdW: CGFloat = 0
    private(set) var tdX: CGFloat = 0
    private(set) var tdY: CGFloat = 0
    private(set) var tdA: CGFloat = 0
    private(set) var tdUX: CGFloat = 0
    private(set) var tdUY: CGFloat = 0
    /// 8 = diagonals available, 4 = cardinals only.
    private(set) var ways = 8
    /// Calibration gain per axis (multiples of HOME_LEAK); see setHomeGain.
    private(set) var gainX: CGFloat = HOME_LEAK_X
    private(set) var gainY: CGFloat = 1
    /// Set true at the entry of each engaging gesture so a diagonal (two buttons) or any
    /// multi-button batch fires exactly one haptic tick, not one per button.
    private var hapticArmed = false
    /// The running --gp-press transition of each round: where it started and when.
    private var pressAnim: [BBButton: (from: CGFloat, t0: Double)] = [:]
    /// The clock of the latest event / frame (performance.now()).
    private var now: Double = 0

    /// input.mjs `constructor(root, press, feedback)` (the DOM building is TouchControlsView's).
    init(press: @escaping (BBButton, Bool) -> Void, feedback: ((BBButton) -> Void)? = nil) {
        self.press = press
        self.feedback = feedback
    }

    // MARK: requestAnimationFrame (browser API, run by the view's display link)

    private var rafNext = 1
    private var rafCallbacks: [(id: Int, cb: (Double) -> Void)] = []

    private func requestAnimationFrame(_ cb: @escaping (Double) -> Void) -> Int {
        let id = rafNext
        rafNext += 1
        rafCallbacks.append((id, cb))
        onAnimationFrameRequest?()
        return id
    }

    private func cancelAnimationFrame(_ id: Int) { rafCallbacks.removeAll { $0.id == id } }

    var hasPendingAnimationFrame: Bool { !rafCallbacks.isEmpty }

    /// One display frame: runs the callbacks requested before it (requested during it run on the
    /// next frame, as in a browser). `now` in ms on the touch clock.
    func animationFrame(now: Double) {
        self.now = now
        let run = rafCallbacks
        rafCallbacks.removeAll()
        for r in run { r.cb(now) }
    }

    // MARK: public surface

    /// The gp-active class of a button's elements (arrow / edge / key): its count is above 0.
    func isActive(_ btn: BBButton) -> Bool { (counts[btn] ?? 0) > 0 }

    var wayCount: Int { ways }

    /// input.mjs `relayout`: re-clamp the home after the pad's geometry changed from outside
    /// (the D-pad size setting, rotation).
    func relayout() { setHome(ox, oy) }

    /// Which element a new touch at `p` lands on (the DOM hit test): .gp-face and .gp-system
    /// (z-index 3) win over .gp-dpad (z-index auto); the pad moves with its transform and its
    /// .gp-ext hit areas reach above and below it.
    func regionAt(_ p: CGPoint) -> Region? {
        let g = geometry
        if g.face.contains(p) { return .face }
        if let s = g.system {
            if s.contains(p) { return .system }
        } else if g.select.contains(p) || g.start.contains(p) {
            return .system
        }
        let pad = g.dpad.offsetBy(dx: ox, dy: oy)
        let ext = pad.height * g.dpadExtFraction
        let hit = CGRect(x: pad.minX, y: pad.minY - ext, width: pad.width, height: pad.height + 2 * ext)
        if hit.contains(p), g.dpadClip?.contains(p) ?? true { return .dpad }
        return nil
    }

    /// pointerdown on the element under the finger (that element then holds the capture).
    @discardableResult
    func pointerDown(_ e: PointerEvent) -> Region? {
        now = e.t
        guard let r = regionAt(CGPoint(x: e.x, y: e.y)) else { return nil }
        captured[e.id] = r
        switch r {
        case .dpad: onDpadDown(e)
        case .face: onFaceDown(e)
        case .system: onSysDown(e)
        }
        return r
    }

    /// pointermove, delivered to the capturing element.
    func pointerMove(_ e: PointerEvent) {
        now = e.t
        switch captured[e.id] {
        case .dpad: onDpadMove(e)
        case .face: onFaceMove(e)
        case .system: onSysMove(e)
        case nil: break
        }
    }

    /// pointerup / pointercancel / lostpointercapture, then the window backstop.
    func pointerUp(_ e: PointerEvent) {
        now = e.t
        switch captured.removeValue(forKey: e.id) {
        case .dpad: onDpadUp(e)
        case .face: onFaceUp(e)
        case .system: onSysUp(e)
        case nil: break
        }
        // Backstop: if an up/cancel never reaches the element that captured the pointer, nothing
        // would ever release its buttons (a no-op after a normal release).
        releasePointer(e.id)
    }

    /// input.mjs `releasePointer`: release everything a pointer id still holds, wherever it is
    /// tracked (an up/cancel can be lost, and ids can be reused).
    func releasePointer(_ id: Int) {
        if let st = dpadPtrs[id] {
            applyDpad(st, NO_DIRS)
            removeDpadPtr(id)
        }
        if facePointers[id] != nil {
            applyFace(id, [])
            removeFacePointer(id)
            faceLatch[id] = nil
            faceRoll[id] = nil
        }
        if sysPointers[id] != nil {
            applySystem(id, [])
            sysPointers[id] = nil
        }
    }

    /// input.mjs `setWays`: switch between eight-way and cardinals-only.
    func setWays(_ ways: Int) {
        if self.ways == ways { return }
        self.ways = ways
        // Anything held under the old geometry may not be legal under the new one.
        for id in dpadOrder { if let st = dpadPtrs[id] { readDirs(st) } }
    }

    /// input.mjs `setHomeGain`: per-axis calibration gain, as a multiple of the base rate.
    func setHomeGain(_ x: CGFloat, _ y: CGFloat) {
        gainX = x
        gainY = y
    }

    /// input.mjs `releaseAll`: force-release everything (pause, blur, ROM swap) so nothing sticks
    /// down, and return the pad to its natural home. The rest estimate (the user's hand) is kept.
    func releaseAll() {
        for btn in BBButton.allCases where (counts[btn] ?? 0) > 0 {
            press(btn, false)
            pressAnim[btn] = (pressShift(btn), now)
        }
        counts.removeAll()
        dpadPtrs.removeAll()
        dpadOrder.removeAll()
        facePointers.removeAll()
        facePointerOrder.removeAll()
        faceLatch.removeAll()
        faceRoll.removeAll()
        sysPointers.removeAll()
        captured.removeAll()
        resetHome()
        onVisual?()
    }

    // ---- reference-counted edge dispatch ----

    /// input.mjs `setBtn`.
    private func setBtn(_ btn: BBButton, _ down: Bool) {
        let c = counts[btn] ?? 0
        let nc = down ? c + 1 : max(0, c - 1)
        // The visual edge restarts the round's transform transition from where it is now.
        if (c == 0) != (nc == 0) { pressAnim[btn] = (pressShift(btn), now) }
        counts[btn] = nc
        if c == 0 && nc > 0 {
            press(btn, true)
            onVisual?()
            // One tick per gesture batch: a diagonal engages two buttons but buzzes once.
            if hapticArmed {
                hapticArmed = false
                haptic()
                feedback?(btn)
            }
        } else if c > 0 && nc == 0 {
            press(btn, false)
            onVisual?()
        }
    }

    /// input.mjs `haptic`: weak tactile tick on a press edge; never relied upon for correctness.
    private func haptic() { onHaptic?() }

    // ---- D-pad ----

    /// input.mjs `setHome`: move the pad's home to (ox, oy) px from its natural centre,
    /// double-clamped: it may not leave the frame (EDGE_MARGIN + inset) nor wander past HOME_MAX
    /// radii.
    func setHome(_ ox: CGFloat, _ oy: CGFloat) {
        let rect = elemRect()
        let natLeft = rect.minX - self.ox
        let natTop = rect.minY - self.oy
        let radius = rect.width / 2
        let vw = geometry.viewport.width, vh = geometry.viewport.height
        let capX = HOME_MAX_X * radius
        let capY = HOME_MAX_Y * radius
        // The frame the container actually leaves free (frameRect), in place of the raw insets.
        let frame = geometry.frame
        let fl = frame.minX
        let fr = vw - frame.maxX
        let ft = frame.minY
        let fb = vh - frame.maxY
        // Only the left edge is matched against what is painted, not the hit box.
        let visLeft = natLeft + visibleLeftOffset()
        let minOx = max(fl - visLeft, -capX)
        var maxOx = min(vw - EDGE_MARGIN - fr - (natLeft + rect.width), capX)
        let minOy = max(EDGE_MARGIN + ft - natTop, -capY)
        var maxOy = min(vh - EDGE_MARGIN - fb - (natTop + rect.height), capY)
        // Degenerate viewport (pad wider than the room): keep at least one edge in.
        if maxOx < minOx { maxOx = minOx }
        if maxOy < minOy { maxOy = minOy }
        self.ox = clamp(ox, minOx, maxOx)
        self.oy = clamp(oy, minOy, maxOy)
        onVisual?() // dpad.style.transform
    }

    /// input.mjs `resetHome`: snap the pad back to its natural centre immediately.
    func resetHome() {
        stopHomeReturn()
        ox = 0
        oy = 0
        onVisual?()
    }

    /// input.mjs `stopHomeReturn`.
    private func stopHomeReturn() {
        if homingRaf != 0 {
            cancelAnimationFrame(homingRaf)
            homingRaf = 0
        }
    }

    /// input.mjs `startHomeReturn`: after the last finger lifts, ease the home back to the
    /// estimated rest point instead of snapping (after HOME_RETURN_DELAY of stillness). The JS
    /// closure's locals (startT, rest) are the properties homeStartT / homeRest here.
    private func startHomeReturn() {
        if homingRaf != 0 { return }
        homeTickLast = 0
        homeStartT = 0
        homeRest = restEstimate() ?? CGPoint.zero
        homingRaf = requestAnimationFrame { [weak self] now in self?.homeReturnTick(now) }
    }

    private var homeStartT: Double = 0
    private var homeRest = CGPoint.zero

    /// The `tick` of startHomeReturn.
    private func homeReturnTick(_ now: Double) {
        if !dpadPtrs.isEmpty {
            homingRaf = 0 // a finger arrived — leave the home where it is
            return
        }
        if homeStartT == 0 { homeStartT = now }
        if homeTickLast == 0 { homeTickLast = now }
        let dt = min(64, now - homeTickLast) // clamp after a stall
        homeTickLast = now
        // Hold still first: during rapid tapping the gaps never reach this.
        if now - homeStartT < HOME_RETURN_DELAY {
            homingRaf = requestAnimationFrame { [weak self] now in self?.homeReturnTick(now) }
            return
        }
        let rest = homeRest
        let decay = CGFloat(exp(-dt / HOME_RETURN_TAU)) // frame-rate independent
        let nx = rest.x + (ox - rest.x) * decay
        let ny = rest.y + (oy - rest.y) * decay
        if abs(nx - rest.x) < 0.5 && abs(ny - rest.y) < 0.5 {
            homingRaf = 0
            setHome(rest.x, rest.y)
            return
        }
        setHome(nx, ny)
        homingRaf = requestAnimationFrame { [weak self] now in self?.homeReturnTick(now) }
    }

    /// input.mjs `toElem`: screen vector → the element's frame. The CSS rotation option is not
    /// ported (iOS rotates the whole UI), so this is the identity of `rotation === 0`.
    private func toElem(_ dx: CGFloat, _ dy: CGFloat) -> CGPoint { CGPoint(x: dx, y: dy) }

    /// input.mjs `padBox`: the pad's own size and its centre on screen (transform included).
    private func padBox() -> (w: CGFloat, h: CGFloat, cx: CGFloat, cy: CGFloat) {
        let r = elemRect()
        return (r.width, r.height, r.midX, r.midY)
    }

    /// input.mjs `elemRect`: getBoundingClientRect of the pad (transform: translate included).
    private func elemRect() -> CGRect { geometry.dpad.offsetBy(dx: ox, dy: oy) }

    /// input.mjs `visibleLeftOffset`: the leftmost painted part relative to the pad's left side
    /// (0 = the box). The arrows and the hub sit inside; .gp-edge-left sits 4 px outside but is
    /// counted only while it is visible (opacity 0 unless Left is active).
    private func visibleLeftOffset() -> CGFloat {
        var minV: CGFloat = 0
        if isActive(.left) { minV = min(minV, geometry.edgeLeftOutset) }
        return minV
    }

    /// input.mjs `resolveDirs`: the engaged buttons for a pointer at distance r / vector (vx, vy)
    /// from the origin. Mutates st.dir8.
    private func resolveDirs(_ st: DpadPtr, _ vx: CGFloat, _ vy: CGFloat, _ r: CGFloat, _ rCommit: CGFloat,
                             _ sticky: Bool, _ cardHalf: CGFloat, _ engageDz: CGFloat) -> Set<BBButton> {
        // A direction already engaged is LATCHED until the thumb has travelled far enough out.
        if let d = st.dir8, r < rCommit { return DIR8_SETS[d]! }
        // Nothing engaged yet and too close to the origin for the angle to mean anything.
        if st.dir8 == nil && r < engageDz { return NO_DIRS }
        let angle = norm360(atan2(vy, vx) * 180 / .pi)
        var dir = sectorRaw(angle, cardHalf)
        // Hysteresis holds the current sector only while nearly still (anti-chatter).
        if sticky, let cur = st.dir8, cur != dir {
            if angularDist(angle, cur.c) <= halfOf(cur, cardHalf) + ANGLE_HYST { dir = cur }
        }
        st.dir8 = dir
        return DIR8_SETS[dir]!
    }

    /// input.mjs `applyDpad`.
    private func applyDpad(_ st: DpadPtr, _ next: Set<BBButton>) {
        let prev = st.dirs
        for b in Self.ordered(prev) where !next.contains(b) { setBtn(b, false) }
        for b in Self.ordered(next) where !prev.contains(b) { setBtn(b, true) }
        st.dirs = next
    }

    // ---- thumb rest-point estimator (touchdowns) ----

    /// input.mjs `foldTouchdown`: fold one touchdown into the running fit for the thumb's rest
    /// point (rest = mean(P) − mean(a)·mean(û), all sums decaying together).
    private func foldTouchdown(_ px: CGFloat, _ py: CGFloat, _ hx: CGFloat, _ hy: CGFloat) {
        let a = hypot(hx, hy)
        // A tap essentially on the origin has no meaningful direction.
        let ux = a > 1 ? hx / a : 0
        let uy = a > 1 ? hy / a : 0
        tdW = tdW * TD_DECAY + 1
        tdX = tdX * TD_DECAY + px
        tdY = tdY * TD_DECAY + py
        tdA = tdA * TD_DECAY + a
        tdUX = tdUX * TD_DECAY + ux
        tdUY = tdUY * TD_DECAY + uy
    }

    /// input.mjs `engageDeadzone`: radius below which a fresh contact has no readable direction.
    func engageDeadzone(_ radius: CGFloat) -> CGFloat {
        let reach = tdW >= TD_MIN_W ? tdA / tdW : radius * REACH_DEFAULT
        let k: CGFloat = ways == 4 ? R_COMMIT_4WAY : 1
        return clamp(reach * DZ_OF_REACH * k, radius * DZ_MIN * k, radius * DZ_MAX * k)
    }

    /// input.mjs `commitRadius`: radius the thumb must clear before an engaged direction may
    /// become another, scaled to this thumb's measured reach.
    func commitRadius(_ radius: CGFloat) -> CGFloat {
        let reach = tdW >= TD_MIN_W ? tdA / tdW : radius * REACH_DEFAULT
        let k: CGFloat = ways == 4 ? R_COMMIT_4WAY : 1
        return clamp(reach * R_COMMIT_OF_REACH * k, radius * R_COMMIT_MIN * k, radius * R_COMMIT_MAX * k)
    }

    /// input.mjs `restEstimate`: the thumb's rest point as a home offset, or nil while too few
    /// taps have accumulated.
    func restEstimate() -> CGPoint? {
        if tdW < TD_MIN_W { return nil }
        let a = tdA / tdW
        return CGPoint(x: tdX / tdW - (a * tdUX) / tdW, y: tdY / tdW - (a * tdUY) / tdW)
    }

    /// input.mjs `calibrateFromTaps`: ease the home partway onto the fitted rest point, and a
    /// little back toward the designed centre (TD_LEAK).
    private func calibrateFromTaps() {
        guard let est = restEstimate() else { return }
        setHome(ox + (est.x - ox) * TD_GAIN * gainX - ox * TD_LEAK,
                oy + (est.y - oy) * TD_GAIN * gainY - oy * TD_LEAK)
    }

    /// input.mjs `onDpadDown`.
    private func onDpadDown(_ e: PointerEvent) {
        hapticArmed = true
        // This id may still be holding buttons from a touch whose up never arrived.
        releasePointer(e.id)
        // The D-pad is owned by the LAST finger that touched it (so a fast re-tap passes through
        // zero and produces both edges).
        for id in dpadOrder where id != e.id { releasePointer(id) }
        // A fresh touch keeps whatever home the release-return has eased to so far.
        stopHomeReturn()
        // (setPointerCapture: TouchControlsView keeps every UITouch with the view it began in.)
        let box = padBox()
        let radius = box.w / 2
        let v = toElem(e.x - box.cx, e.y - box.cy)
        let st = DpadPtr(lastX: e.x, lastY: e.y, lastT: e.t)
        // Touchdown is read absolutely from the current home, with no radius floor.
        _ = resolveDirs(st, v.x, v.y, hypot(v.x, v.y), commitRadius(radius), true,
                        ways == 4 ? CARD_HALF_4WAY : CARD_HALF_ENGAGE, engageDeadzone(radius))
        // Learn from the touchdown, then re-read it from the corrected home. Skipped while another
        // finger already owns the pad.
        dpadPtrs[e.id] = st
        if !dpadOrder.contains(e.id) { dpadOrder.append(e.id) }
        if dpadPtrs.count == 1 {
            foldTouchdown(v.x + ox, v.y + oy, v.x, v.y)
            calibrateFromTaps()
            // Clear the provisional read so the re-read is absolute.
            st.dir8 = nil
        }
        readDirs(st)
        st.calibDir = st.dir8
        startCalib()
    }

    /// input.mjs `onDpadMove`: kinematics and the direction only; calibration runs on the clock.
    private func onDpadMove(_ e: PointerEvent) {
        guard let st = dpadPtrs[e.id] else { return }
        hapticArmed = true
        let dt = max(1, e.t - st.lastT)
        let dxStep = e.x - st.lastX
        let dyStep = e.y - st.lastY
        let step = hypot(dxStep, dyStep)
        st.speed = lerp(st.speed, step / CGFloat(dt), 0.6) // EMA of px/ms (fairly responsive)
        st.lastX = e.x
        st.lastY = e.y
        st.lastT = e.t
        st.accDX += dxStep
        st.accDY += dyStep
        readDirs(st)
    }

    /// input.mjs `readDirs`: re-resolve and apply the direction for a pointer from its last
    /// known point (on every move AND on every calibration tick).
    private func readDirs(_ st: DpadPtr) {
        let box = padBox()
        let radius = box.w / 2
        let v = toElem(st.lastX - box.cx, st.lastY - box.cy)
        let r = hypot(v.x, v.y)
        // Hysteresis only while nearly still; an active sweep tracks the raw angle.
        let sticky = st.speed < SPEED_STILL * 2
        // Cardinal-heavy on the first read, easing to an even split as the press is held.
        let cardHalf = ways == 4
            ? CARD_HALF_4WAY
            : lerp(CARD_HALF_ENGAGE, CARD_HALF_HELD, clamp(CGFloat(st.heldTicks) / SHARE_RAMP_TICKS, 0, 1))
        applyDpad(st, resolveDirs(st, v.x, v.y, r, commitRadius(radius), sticky, cardHalf, engageDeadzone(radius)))
    }

    /// input.mjs `startCalib`: the calibration clock, the ONLY driver of home calibration while a
    /// finger is on the pad. Only a solo contact calibrates.
    private func startCalib() {
        if calibRaf != 0 { return }
        calibLast = 0
        calibRaf = requestAnimationFrame { [weak self] now in self?.calibTick(now) }
    }

    /// The `tick` of startCalib.
    private func calibTick(_ now: Double) {
        if dpadPtrs.isEmpty {
            calibRaf = 0
            return
        }
        if calibLast == 0 { calibLast = now }
        let dt = min(64, now - calibLast) // clamp after a stall
        calibLast = now
        if dt >= 1 && dpadPtrs.count == 1, let id = dpadOrder.first, let st = dpadPtrs[id] {
            if st.lastT == st.seenT {
                // No pointer event since the last tick: the finger is genuinely still.
                st.speed = lerp(st.speed, 0, 0.35)
                st.accDX = 0
                st.accDY = 0
            }
            st.seenT = st.lastT
            st.heldTicks += 1
            readDirs(st)
            calibrate(st, CGFloat(dt))
            st.accDX = 0
            st.accDY = 0
        }
        calibRaf = requestAnimationFrame { [weak self] now in self?.calibTick(now) }
    }

    /// input.mjs `padRadiusForCalib`.
    private func padRadiusForCalib() -> CGFloat { padBox().w / 2 }

    /// input.mjs `calibrate`: one calibration step of `dt` ms, easing the pad's home toward the
    /// thumb.
    private func calibrate(_ st: DpadPtr, _ dt: CGFloat) {
        let box = padBox()
        let v = toElem(st.lastX - box.cx, st.lastY - box.cy)
        let vx = v.x, vy = v.y
        let k = clamp((HOME_LEAK * dt) / 1000, 0, 0.5)

        if let calibDir = st.calibDir, st.dir8 != calibDir {
            // The direction just changed: relax the home partway toward the estimated rest point.
            let rest = restEstimate() ?? CGPoint.zero
            setHome(lerp(rest.x, ox, RELAX_ON_TURN), lerp(rest.y, oy, RELAX_ON_TURN))
        } else if let d = st.dir8, st.speed < SPEED_STILL * 2 {
            // Any held direction: cancel the PERPENDICULAR part of the finger vector, and pull the
            // origin along the axis only by what exceeds the learned reach.
            let cRad = d.c * .pi / 180
            let dxu = cos(cRad)
            let dyu = sin(cRad)
            let dot = vx * dxu + vy * dyu
            let perpX = vx - dot * dxu
            let perpY = vy - dot * dyu
            let radiusNow = padRadiusForCalib()
            let learned = tdW >= TD_MIN_W ? tdA / tdW : radiusNow * REACH_DEFAULT
            let target = clamp(learned, radiusNow * R_TARGET, radiusNow * R_MAX_TARGET)
            let excess = max(0, dot - target)
            setHome(ox + (perpX + excess * dxu) * k * gainX,
                    oy + (perpY + excess * dyu) * k * gainY)
        }
        st.calibDir = st.dir8

        // Horizontal play must stay horizontal even mid-slide: with clearly horizontal motion and
        // nothing vertical intended, ease the VERTICAL home toward the thumb at any speed.
        let dirs = st.dirs
        let noVertical = !dirs.contains(.up) && !dirs.contains(.down)
            && (dirs.isEmpty || dirs.contains(.left) || dirs.contains(.right))
        let acc = toElem(st.accDX, st.accDY)
        if noVertical && abs(acc.x) > abs(acc.y) * 1.4 + 0.5 {
            let kv = clamp((HOME_LEAK * gainY * dt) / 1000, 0, 0.5)
            setHome(ox, oy + vy * kv)
        }
    }

    /// input.mjs `onDpadUp`.
    private func onDpadUp(_ e: PointerEvent) {
        guard let st = dpadPtrs[e.id] else { return }
        applyDpad(st, NO_DIRS)
        removeDpadPtr(e.id)
        // Last finger up → ease (don't snap) the pad back to its natural home.
        if dpadPtrs.isEmpty { startHomeReturn() }
    }

    private func removeDpadPtr(_ id: Int) {
        dpadPtrs[id] = nil
        dpadOrder.removeAll { $0 == id }
    }

    // ---- face / system buttons ----

    /// input.mjs `systemButtonsAt`: Select and/or Start by proximity to each pill; the region
    /// between them (up to 0.66x the centre separation) engages BOTH.
    func systemButtonsAt(_ x: CGFloat, _ y: CGFloat) -> Set<BBButton> {
        let s = geometry.select, t = geometry.start
        let sx = s.midX, sy = s.midY
        let tx = t.midX, ty = t.midY
        let dSel = hypot(x - sx, y - sy)
        let dSta = hypot(x - tx, y - ty)
        let thr = hypot(sx - tx, sy - ty) * 0.66
        var set: Set<BBButton> = []
        if dSel < thr { set.insert(.select) }
        if dSta < thr { set.insert(.start) }
        if set.isEmpty { set.insert(dSel < dSta ? .select : .start) }
        return set
    }

    /// input.mjs `applySystem`.
    private func applySystem(_ id: Int, _ next: Set<BBButton>) {
        let prev = sysPointers[id] ?? []
        for b in Self.ordered(prev) where !next.contains(b) { setBtn(b, false) }
        for b in Self.ordered(next) where !prev.contains(b) { setBtn(b, true) }
        sysPointers[id] = next
    }

    /// input.mjs `onSysDown`.
    private func onSysDown(_ e: PointerEvent) {
        hapticArmed = true
        releasePointer(e.id)
        applySystem(e.id, systemButtonsAt(e.x, e.y))
    }

    /// input.mjs `onSysMove`.
    private func onSysMove(_ e: PointerEvent) {
        guard sysPointers[e.id] != nil else { return }
        hapticArmed = true
        applySystem(e.id, systemButtonsAt(e.x, e.y))
    }

    /// input.mjs `onSysUp`.
    private func onSysUp(_ e: PointerEvent) {
        guard sysPointers[e.id] != nil else { return }
        applySystem(e.id, [])
        sysPointers[e.id] = nil
    }

    // ---- A/B shared pad ----

    /// input.mjs `faceGeometry`: centres of A and B (as getBoundingClientRect sees them: a pressed
    /// round sits up to 3 px higher, easing over its 60 ms transform transition), and the
    /// distance between them.
    func faceGeometry() -> (ax: CGFloat, ay: CGFloat, bx: CGFloat, by: CGFloat, sep: CGFloat) {
        let ax = geometry.a.x, bx = geometry.b.x
        let ay = geometry.a.y + pressShift(.a)
        let by = geometry.b.y + pressShift(.b)
        return (ax, ay, bx, by, hypot(ax - bx, ay - by))
    }

    /// The round's current --gp-press translation: CSS `transition: transform .06s` (timing
    /// function `ease`) from where it was to the value of its gp-active state.
    private func pressShift(_ btn: BBButton) -> CGFloat {
        let target: CGFloat = isActive(btn) ? geometry.pressOffset : 0
        let dur = geometry.pressTransitionMs
        guard dur > 0, let anim = pressAnim[btn] else { return target }
        let p = (now - anim.t0) / dur
        if p >= 1 { return target }
        if p <= 0 { return anim.from }
        return anim.from + (target - anim.from) * Self.cssEase(CGFloat(p))
    }

    /// CSS `ease` = cubic-bezier(0.25, 0.1, 0.25, 1): progress at time fraction x.
    static func cssEase(_ x: CGFloat) -> CGFloat {
        let p1x: CGFloat = 0.25, p1y: CGFloat = 0.1, p2x: CGFloat = 0.25, p2y: CGFloat = 1
        func bx(_ t: CGFloat) -> CGFloat { 3 * (1 - t) * (1 - t) * t * p1x + 3 * (1 - t) * t * t * p2x + t * t * t }
        func by(_ t: CGFloat) -> CGFloat { 3 * (1 - t) * (1 - t) * t * p1y + 3 * (1 - t) * t * t * p2y + t * t * t }
        var lo: CGFloat = 0, hi: CGFloat = 1, t = x
        for _ in 0..<30 {
            t = (lo + hi) / 2
            if bx(t) < x { lo = t } else { hi = t }
        }
        return by(t)
    }

    /// input.mjs `faceSoloHeldByOther`: the single face button held ALONE by exactly one pointer
    /// other than `id`, or nil.
    private func faceSoloHeldByOther(_ id: Int) -> BBButton? {
        var found: BBButton?
        for pid in facePointerOrder {
            guard pid != id, let btns = facePointers[pid], btns.count == 1 else { continue }
            if found != nil { return nil } // more than one committed hold: no inference
            found = btns.first
        }
        return found
    }

    /// input.mjs `faceButtonsAt`: buttons engaged for pointer `id` at (x, y): 1. latched tap,
    /// 2. geometry (A and/or B by proximity, FACE_HYST for a held one), then the NESTERM roll
    /// reading.
    private func faceButtonsAt(_ x: CGFloat, _ y: CGFloat, _ id: Int) -> Set<BBButton> {
        let g = faceGeometry()

        // 1. Latched tap. Breaking on travel is what lets the latch ignore position at touchdown.
        if let latch = faceLatch[id] {
            if hypot(x - latch.x, y - latch.y) < g.sep * FACE_LATCH_TRAVEL {
                return [latch.btn]
            }
            faceLatch[id] = nil
        }

        // 2. Geometry.
        let dA = hypot(x - g.ax, y - g.ay)
        let dB = hypot(x - g.bx, y - g.by)
        let thr = g.sep * FACE_THR
        let mine = facePointers[id]
        let hyst = { (own: BBButton) -> CGFloat in mine?.contains(own) == true ? FACE_HYST : 1 }

        var set: Set<BBButton> = []
        if dA < thr * hyst(.a) { set.insert(.a) }
        if dB < thr * hyst(.b) { set.insert(.b) }
        if set.isEmpty { set.insert(dA < dB ? .a : .b) } // nearest fallback
        return rollTap(id, set, mine, x, y, g, now)
    }

    /// input.mjs `rollTap` (NESTERM): while a pointer holds one face button, its motion along the
    /// axis toward the other decides the other button: a quick advance (ROLL_ENGAGE within
    /// ROLL_WINDOW_MS) or entering its radius presses, a retreat of ROLL_RETURN releases.
    /// Perpendicular motion is ignored. Leaving the original button entirely is a hand-over.
    private func rollTap(_ id: Int, _ setIn: Set<BBButton>, _ mine: Set<BBButton>?, _ x: CGFloat, _ y: CGFloat,
                         _ g: (ax: CGFloat, ay: CGFloat, bx: CGFloat, by: CGFloat, sep: CGFloat), _ now: Double) -> Set<BBButton> {
        var set = setIn
        let other = { (btn: BBButton) -> BBButton in btn == .a ? .b : .a }
        var rollOpt = faceRoll[id]
        if rollOpt == nil {
            // Seed at touchdown (mine is empty then) so the landing point anchors the travel.
            // Landing in the overlap takes the nearer button as the base with the other on.
            let held = (mine?.isEmpty == false) ? mine! : set
            if held.count == 1 {
                rollOpt = FaceRoll(base: held.first!, on: false)
            } else if held.count == 2 {
                let nearA = hypot(x - g.ax, y - g.ay) <= hypot(x - g.bx, y - g.by)
                rollOpt = FaceRoll(base: nearA ? .a : .b, on: true)
            } else {
                return set
            }
            faceRoll[id] = rollOpt
        }
        let roll = rollOpt!
        let base = roll.base, target = other(base)
        if !set.contains(base) {
            faceRoll[id] = nil
            return set
        }
        let (fx, fy, tx, ty) = base == .a ? (g.ax, g.ay, g.bx, g.by) : (g.bx, g.by, g.ax, g.ay)
        let s = ((x - fx) * (tx - fx) + (y - fy) * (ty - fy)) / (g.sep * g.sep)
        roll.hist.append((now, s))
        // The newest sample older than the window is where the thumb was at its start: keep it.
        while roll.hist.count > 1 && now - roll.hist[1].t > ROLL_WINDOW_MS { roll.hist.removeFirst() }
        roll.low = min(roll.low, s)
        if !roll.on {
            let windowLow = roll.hist.map(\.s).min() ?? s
            // After a release only a quick, deliberate advance presses again, never slow creep.
            let entered = !roll.released && set.contains(target) && s - roll.low >= ROLL_RETURN
            if s - windowLow >= ROLL_ENGAGE || entered {
                roll.on = true
                roll.ext = s
            }
        } else {
            roll.ext = max(roll.ext, s) // -Infinity on a both-held seed: starts here
            if roll.ext - s >= ROLL_RETURN {
                roll.on = false
                roll.released = true
                roll.low = s
                roll.hist = [(now, s)]
            }
        }
        roll.s = (s * 1000).rounded() / 1000
        if roll.on { set.insert(target) } else { set.remove(target) }
        return set
    }

    /// input.mjs `applyFace`.
    private func applyFace(_ id: Int, _ next: Set<BBButton>) {
        let prev = facePointers[id] ?? []
        for b in Self.ordered(prev) where !next.contains(b) { setBtn(b, false) }
        for b in Self.ordered(next) where !prev.contains(b) { setBtn(b, true) }
        facePointers[id] = next
        if !facePointerOrder.contains(id) { facePointerOrder.append(id) }
    }

    private func removeFacePointer(_ id: Int) {
        facePointers[id] = nil
        facePointerOrder.removeAll { $0 == id }
    }

    /// input.mjs `onFaceDown`.
    private func onFaceDown(_ e: PointerEvent) {
        hapticArmed = true
        // Second finger arriving during a committed hold: it means the other button.
        if let held = faceSoloHeldByOther(e.id) {
            let other: BBButton = held == .a ? .b : .a
            faceLatch[e.id] = (other, e.x, e.y)
        }
        applyFace(e.id, faceButtonsAt(e.x, e.y, e.id))
    }

    /// input.mjs `onFaceMove`.
    private func onFaceMove(_ e: PointerEvent) {
        guard facePointers[e.id] != nil else { return }
        hapticArmed = true
        applyFace(e.id, faceButtonsAt(e.x, e.y, e.id))
    }

    /// input.mjs `onFaceUp`.
    private func onFaceUp(_ e: PointerEvent) {
        guard facePointers[e.id] != nil else { return }
        applyFace(e.id, [])
        removeFacePointer(e.id)
        faceLatch[e.id] = nil
        faceRoll[e.id] = nil
    }

    /// A Set in a fixed order (JS Sets iterate in insertion order; the order only decides which
    /// button the one-per-batch feedback hook names).
    private static func ordered(_ s: Set<BBButton>) -> [BBButton] { BBButton.allCases.filter { s.contains($0) } }
}
