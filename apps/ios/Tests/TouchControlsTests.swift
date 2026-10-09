// The ported NESTERM touch controller: layout against NESTERM's CSS (numbers measured from
// web/styles.css in a browser at 390 x 844 and 844 x 390, see apps/ios/docs/TOUCH_PORT.md), the
// pure input.mjs helpers, NESTERM's own controller acceptance checks (scripts/controller-check.mjs,
// same positions and expectations) on the iPhone layout, and the touch bindings.
// Exact step-by-step equality with the JS implementation: BrickboyGoldenTests.
// SPDX-License-Identifier: Apache-2.0 AND GPL-2.0-or-later
import CoreGraphics
import XCTest

final class TouchLayoutTests: XCTestCase {
    let portrait = TouchLayout.make(size: CGSize(width: 390, height: 844), safe: TouchInsets())
    let landscape = TouchLayout.make(size: CGSize(width: 844, height: 390), safe: TouchInsets())
    // iPhone 16 Pro (points) with its safe areas.
    let phonePortrait = TouchLayout.make(size: CGSize(width: 402, height: 874), safe: TouchInsets(top: 62, left: 0, bottom: 34, right: 0),
                                         options: TouchLayout.Options(showTurbo: true))
    let phoneLandscape = TouchLayout.make(size: CGSize(width: 874, height: 402), safe: TouchInsets(top: 0, left: 62, bottom: 21, right: 62),
                                          options: TouchLayout.Options(showTurbo: true))

    /// Browser measurements of NESTERM's controller (getBoundingClientRect, 390 x 844). Blink rounds
    /// layout boxes to 1/64 px (LayoutUnit): ±0.05 for derived sizes.
    func testPortraitMatchesNESTERMCSS() {
        let g = portrait.pad
        XCTAssertEqual(g.dpad.width, 144)                       // min(--bb-dpad 144, max(112, 844 * .24))
        XCTAssertEqual(g.dpad.minX, 19.546875, accuracy: 0.01)  // padding-inline 4.5vw + margin-left 2px
        XCTAssertEqual(g.face.minX, 214.265625, accuracy: 0.05)
        XCTAssertEqual(g.face.width, 158.1875, accuracy: 0.05)
        XCTAssertEqual(g.face.height, 150.59375, accuracy: 0.05)
        XCTAssertEqual(portrait.faceButton, 74.1, accuracy: 0.05) // clamp(48, min(19vw, el-h * .13), 78)
        XCTAssertEqual(g.a.x - g.b.x, 331.40625 - 255.3125, accuracy: 0.05)
        XCTAssertEqual(g.a.y - g.b.y, 580.5522766113281 - 649.07275390625, accuracy: 0.05)
        XCTAssertEqual(hypot(g.a.x - g.b.x, g.a.y - g.b.y), 102.3978251614086, accuracy: 0.05)
        XCTAssertEqual(g.face.midY, g.dpad.midY, accuracy: 0.01, "both centred in the first grid row")
        XCTAssertEqual(g.system?.minX ?? 0, 17.546875, accuracy: 0.01)
        XCTAssertEqual(g.system?.width ?? 0, 354.90625, accuracy: 0.01)
        XCTAssertEqual(g.system?.height ?? 0, 48)
        XCTAssertEqual(g.select.height, 40)
        XCTAssertEqual(g.select.width, 92.65625, accuracy: 1.5, "SELECT: label (system font) + 44")
        XCTAssertEqual(g.start.width, 85.421875, accuracy: 1.5)
        XCTAssertEqual(g.start.minX - g.select.maxX, 22, accuracy: 0.01)
        XCTAssertEqual((g.select.minX + g.start.maxX) / 2, 195, accuracy: 0.01, "pills centred")
        // Rows: 6 px padding, row gap 4, system row 48, bottom padding 6.
        let clip = g.dpadClip!
        XCTAssertEqual(g.system!.maxY, clip.maxY - 6, accuracy: 0.01)
        XCTAssertEqual(g.dpad.midY, (clip.minY + 6 + g.system!.minY - 4) / 2, accuracy: 0.01)
        XCTAssertEqual(g.frame, CGRect(x: 0, y: 0, width: 390, height: 844))
        XCTAssertEqual(portrait.gameArea.width, 390)
        XCTAssertLessThanOrEqual(portrait.gameArea.maxY + TouchLayout.subbarHeight, clip.minY + 0.01)
    }

    /// Browser measurements at 844 x 390 (.bb-side).
    func testLandscapeMatchesNESTERMCSS() {
        let g = landscape.pad
        XCTAssertEqual(g.dpad, CGRect(x: 16, y: g.dpad.minY, width: 144, height: 144))
        XCTAssertEqual(g.face, CGRect(x: 654, y: g.face.minY, width: 190, height: 174))
        XCTAssertEqual(g.a.x, 789, accuracy: 0.01)
        XCTAssertEqual(g.b.x, 709, accuracy: 0.01)
        XCTAssertEqual(g.b.y - g.a.y, 241.5159912109375 - 169.4840087890625, accuracy: 0.01)
        XCTAssertEqual(g.face.midY, g.dpad.midY, accuracy: 0.01)
        XCTAssertNil(g.system, "display: contents: only the pills take touches")
        XCTAssertNil(g.dpadClip)
        XCTAssertEqual(g.select.maxY, 390 - 8, accuracy: 0.01)
        XCTAssertEqual(g.select.height, 31.390625, accuracy: 0.01)
        XCTAssertEqual(g.select.midX, 25.671875 + 92.65625 / 2, accuracy: 0.01, "centred in the 144 px column")
        XCTAssertEqual(g.start.midX, 729.28125 + 85.421875 / 2, accuracy: 0.01)
        XCTAssertEqual(landscape.gameArea, CGRect(x: 0, y: 0, width: 844, height: 390))
    }

    func testSafeAreasMoveTheControlsIn() {
        let l = phoneLandscape.pad
        XCTAssertEqual(l.dpad.minX, 62 + 16)
        XCTAssertEqual(l.face.maxX, 874 - 62, accuracy: 0.01)
        XCTAssertEqual(l.select.maxY, 402 - 8 - 21, accuracy: 0.01)
        XCTAssertEqual(l.frame, CGRect(x: 62, y: 0, width: 874 - 124, height: 402))
        let p = phonePortrait.pad
        XCTAssertEqual(phonePortrait.gameArea.minY, 62)
        XCTAssertEqual(p.system!.maxY, 874 - 34 - 6, accuracy: 0.01)
    }

    func testEverythingOnScreenAndApart() {
        for l in [portrait, landscape, phonePortrait, phoneLandscape] {
            let screen = CGRect(origin: .zero, size: l.size)
            var boxes: [(String, CGRect)] = [("dpad", l.pad.dpad), ("face", l.pad.face), ("select", l.select), ("start", l.start)]
            boxes += l.extras.map { ("\($0.kind)", $0.frame) }
            for (n, r) in boxes { XCTAssertTrue(screen.contains(r), "\(n) \(r) off \(screen)") }
            for i in boxes.indices { for j in boxes.indices where j > i {
                XCTAssertFalse(boxes[i].1.intersects(boxes[j].1), "\(boxes[i].0) overlaps \(boxes[j].0) in \(l.size)")
            } }
            let kinds = l.extras.map(\.kind)
            for b in [TouchButton.l2, .l, .r, .r2, .menu] { XCTAssertTrue(kinds.contains(.button(b)), "\(b) in \(l.size)") }
            XCTAssertTrue(kinds.contains(.ways))
        }
        XCTAssertTrue(phonePortrait.extras.contains { $0.kind == .button(.turboA) })
        XCTAssertFalse(portrait.extras.contains { $0.kind == .button(.turboA) })
    }

    func testDpadSizeSetting() {
        let big = TouchLayout.make(size: CGSize(width: 844, height: 390), safe: TouchInsets(), options: TouchLayout.Options(dpadSize: 210))
        XCTAssertEqual(big.pad.dpad.width, 210)
        // Portrait caps it: min(--bb-dpad, max(112px, el-h * .24)).
        let small = TouchLayout.make(size: CGSize(width: 320, height: 568), safe: TouchInsets(), options: TouchLayout.Options(dpadSize: 210))
        XCTAssertEqual(small.pad.dpad.width, 568 * 0.24, accuracy: 0.01)
    }

    func testTouchBindingsCoverEveryGameButtonOnce() {
        let ids = TouchButton.allCases.compactMap(\.inputID)
        XCTAssertEqual(Set(TouchBindings.defaults.map(\.input)), Set(ids))
        XCTAssertEqual(TouchBindings.defaults.count, ids.count)
        XCTAssertNil(TouchButton.menu.inputID)
        XCTAssertEqual(TouchBindings.missing(existing: [("kb:1", "p1.a")]).count, TouchBindings.defaults.count)
        XCTAssertTrue(TouchBindings.missing(existing: [("touch:a", "p1.b")]).isEmpty, "a customised touch table is kept")
        // input-router.mjs BUTTON_NAME: every Brickboy id reaches the NES button of the same name.
        XCTAssertEqual(BBButton.allCases.map { TouchButton($0).inputID! },
                       ["touch:dpad.right", "touch:dpad.left", "touch:dpad.up", "touch:dpad.down", "touch:a", "touch:b", "touch:select", "touch:start"])
    }

    func testTouchBindingsAreAcceptedByTheEngine() {
        let input = rn_input_new()!
        defer { rn_input_free(input) }
        for b in TouchBindings.defaults { XCTAssertEqual(rn_input_bind(input, b.input, b.action), RN_OK, "\(b)") }
        rn_input_set_pressed(input, "touch:a", 1)
        rn_input_set_pressed(input, "touch:dpad.left", 1)
        var p1: UInt8 = 0, p2: UInt8 = 0
        rn_input_sample_game(input, 0, &p1, &p2)
        XCTAssertNotEqual(p1, 0)
        XCTAssertEqual(p2, 0)
        rn_input_release_prefix(input, "touch:")
        rn_input_sample_game(input, 1, &p1, &p2)
        XCTAssertEqual(p1, 0)
    }
}

/// input.mjs's pure helpers.
final class BrickboyHelperTests: XCTestCase {
    func testSectors() {
        XCTAssertEqual(norm360(-90), 270)
        XCTAssertEqual(norm360(725), 5)
        XCTAssertEqual(angularDist(350, 10), 20)
        XCTAssertEqual(angularDist(-170, 170), 20)
        // First read: cardinals own 65% of the circle (half-width 29.25°).
        XCTAssertEqual(sectorRaw(29.25, CARD_HALF_ENGAGE), .R)
        XCTAssertEqual(sectorRaw(29.3, CARD_HALF_ENGAGE), .DR)
        XCTAssertEqual(sectorRaw(270 + 29.2, CARD_HALF_ENGAGE), .U)
        XCTAssertEqual(sectorRaw(315, CARD_HALF_ENGAGE), .UR)
        // Held: an even split.
        XCTAssertEqual(sectorRaw(22.5, CARD_HALF_HELD), .R)
        XCTAssertEqual(sectorRaw(22.6, CARD_HALF_HELD), .DR)
        // 4-way: no diagonal can be produced (the first band in DIR8_ORDER takes the tie).
        for a in stride(from: CGFloat(0), to: 360, by: 0.5) { XCTAssertEqual(sectorRaw(a, CARD_HALF_4WAY).btns.count, 1, "\(a)") }
        XCTAssertEqual(sectorRaw(45, CARD_HALF_4WAY), .R)
        XCTAssertEqual(sectorRaw(45.01, CARD_HALF_4WAY), .D)
        XCTAssertEqual(DIR8_SETS[.UL], [.up, .left])
    }

    func testRadiiFromReach() {
        let pad = TouchGamepad(press: { _, _ in })
        // No taps yet: REACH_DEFAULT (0.45 r) of a 72 px radius.
        XCTAssertEqual(pad.engageDeadzone(72), 8.1, accuracy: 1e-9)   // clamp(32.4 * .25, 5.76, 14.4)
        XCTAssertEqual(pad.commitRadius(72), 19.44, accuracy: 1e-9)   // clamp(32.4 * .6, 8.64, 21.6)
        pad.setWays(4)
        XCTAssertEqual(pad.commitRadius(72), 31.104, accuracy: 1e-9)  // x R_COMMIT_4WAY
        XCTAssertEqual(pad.engageDeadzone(72), 12.96, accuracy: 1e-9)
        XCTAssertNil(pad.restEstimate())
    }

    func testCSSEase() {
        XCTAssertEqual(TouchGamepad.cssEase(0), 0, accuracy: 1e-6)
        XCTAssertEqual(TouchGamepad.cssEase(1), 1, accuracy: 1e-6)
        XCTAssertEqual(TouchGamepad.cssEase(0.5), 0.8024, accuracy: 1e-3) // cubic-bezier(.25,.1,.25,1) at 0.5
    }
}

/// NESTERM scripts/controller-check.mjs, the portrait group: the same touches (positions relative
/// to the controls) and the same expectations, on the iPhone layout.
final class NESTERMControllerCheckTests: XCTestCase {
    private var pad: TouchGamepad!
    private var t: Double = 1000
    private var held: Set<BBButton> { Set(BBButton.allCases.filter { pad.isActive($0) }) }
    private var g: TouchGamepad.Geometry { pad.geometry }

    override func setUp() {
        let l = TouchLayout.make(size: CGSize(width: 390, height: 844), safe: TouchInsets())
        pad = TouchGamepad(press: { _, _ in })
        pad.geometry = l.pad
        pad.setHomeGain(0.3, 1)
    }

    private func at(_ dt: Double = 40) -> Double { t += dt; return t }
    private func down(_ id: Int, _ p: CGPoint, _ dt: Double = 40) { pad.pointerDown(PointerEvent(id: id, x: p.x, y: p.y, t: at(dt))) }
    private func move(_ id: Int, _ p: CGPoint, _ dt: Double = 40) { pad.pointerMove(PointerEvent(id: id, x: p.x, y: p.y, t: at(dt))) }
    private func up(_ id: Int, _ p: CGPoint = .zero, _ dt: Double = 40) { pad.pointerUp(PointerEvent(id: id, x: p.x, y: p.y, t: at(dt))) }
    private func frames(_ ms: Double) {
        let end = t + ms
        while t < end { t += 1000 / 60; pad.animationFrame(now: t) }
    }
    private func along(_ f: CGFloat) -> CGPoint { CGPoint(x: g.b.x + (g.a.x - g.b.x) * f, y: g.b.y + (g.a.y - g.b.y) * f) }
    private func fromA(_ f: CGFloat) -> CGPoint { CGPoint(x: g.a.x + (g.b.x - g.a.x) * f, y: g.a.y + (g.b.y - g.a.y) * f) }

    func testAdaptiveDpadAndCancel() {
        let d = g.dpad, c = CGPoint(x: d.midX, y: d.midY)
        down(1, c)
        move(1, CGPoint(x: c.x + d.width * 0.40, y: c.y))
        XCTAssertEqual(held, [.right], "adaptive D-pad right slide")
        move(1, CGPoint(x: c.x + d.width * 0.34, y: c.y - d.height * 0.34))
        frames(50)
        XCTAssertEqual(held, [.right, .up], "8-way diagonal")
        up(1) // pointercancel
        XCTAssertEqual(held, [], "pointercancel must release D-pad")
    }

    func testFourAndEightWay() {
        let d = g.dpad, c = CGPoint(x: d.midX, y: d.midY)
        pad.setWays(4)
        down(2, c)
        move(2, CGPoint(x: c.x + d.width * 0.34, y: c.y - d.height * 0.34))
        XCTAssertEqual(held.count, 1, "4-way: exactly one direction")
        up(2)
        XCTAssertEqual(held, [])
        pad.setWays(8)
        XCTAssertEqual(pad.wayCount, 8)
    }

    func testFaceSlideOverlapAndTwoFinger() {
        down(3, along(0)); XCTAssertEqual(held, [.b], "face B")
        move(3, along(0.5)); XCTAssertEqual(held, [.a, .b], "face overlap A+B")
        move(3, along(1)); XCTAssertEqual(held, [.a], "face slide B to A")
        up(3); XCTAssertEqual(held, [], "face slide release")
        down(4, along(1)); XCTAssertEqual(held, [.a], "first face finger")
        down(5, along(0)); XCTAssertEqual(held, [.a, .b], "second face finger must latch other button")
        up(5); XCTAssertEqual(held, [.a], "first face finger must remain")
        up(4); XCTAssertEqual(held, [], "two-finger face release")
    }

    func testRollTap() {
        down(6, along(0)); XCTAssertEqual(held, [.b], "roll: B held")
        move(6, along(0.55)); XCTAssertEqual(held, [.a, .b], "roll: into overlap presses A")
        move(6, along(0.40)); XCTAssertEqual(held, [.b], "roll: partial return releases A while B stays")
        move(6, along(0.56)); XCTAssertEqual(held, [.a, .b], "roll: second roll re-taps A")
        move(6, along(0.42)); XCTAssertEqual(held, [.b], "roll: second partial return releases A")
        up(6); XCTAssertEqual(held, [], "roll: release")
    }

    func testMotionRoll() {
        down(7, along(0)); XCTAssertEqual(held, [.b], "motion: B held")
        move(7, along(0.18), 60); XCTAssertEqual(held, [.a, .b], "motion: quick shallow roll presses A")
        move(7, along(0.04)); XCTAssertEqual(held, [.b], "motion: retreat releases A")
        up(7); XCTAssertEqual(held, [], "motion: release")
        down(8, along(0), 300); XCTAssertEqual(held, [.b], "drift: B held")
        for k in 1...6 { move(8, along(0.03 * CGFloat(k)), 150) }
        XCTAssertEqual(held, [.b], "drift: slow thumb drift must not press A")
        up(8); XCTAssertEqual(held, [], "drift: release")
    }

    func testRememberedRoll() {
        down(9, fromA(0)); XCTAssertEqual(held, [.a], "mirror: A held")
        move(9, fromA(0.55)); XCTAssertEqual(held, [.a, .b], "mirror: roll presses B")
        move(9, fromA(0.40)); XCTAssertEqual(held, [.a], "mirror: retreat releases B")
        up(9); XCTAssertEqual(held, [], "mirror: release")
        down(10, along(0), 300); XCTAssertEqual(held, [.b], "creep: B held")
        move(10, along(0.55)); XCTAssertEqual(held, [.a, .b], "creep: roll presses A")
        move(10, along(0.42)); XCTAssertEqual(held, [.b], "creep: retreat releases A")
        for f in [0.45, 0.48, 0.51] as [CGFloat] { move(10, along(f), 150) }
        XCTAssertEqual(held, [.b], "creep: slow drift after a release must not re-press A")
        move(10, along(0.65), 120); XCTAssertEqual(held, [.a, .b], "creep: a quick advance re-presses A")
        up(10); XCTAssertEqual(held, [], "creep: release")
        down(11, along(0.45), 300); XCTAssertEqual(held, [.a, .b], "middle: touchdown in the overlap presses both")
        move(11, along(0.35)); XCTAssertEqual(held, [.b], "middle: retreat toward B releases A")
        up(11); XCTAssertEqual(held, [], "middle: release")
    }

    func testSystemOverlap() {
        let s = CGPoint(x: g.select.midX, y: g.select.midY), st = CGPoint(x: g.start.midX, y: g.start.midY)
        down(6, CGPoint(x: (s.x + st.x) / 2, y: (s.y + st.y) / 2))
        XCTAssertEqual(held, [.select, .start], "system overlap must press START+SELECT")
        up(6); XCTAssertEqual(held, [], "system overlap release")
    }

    func testRapidDpadRetapPassesThroughZero() {
        // input.mjs onDpadDown: the newest finger owns the pad, so a re-tap before the old finger
        // lifts still produces a release and a press edge.
        var edges: [(BBButton, Bool)] = []
        let p = TouchGamepad(press: { edges.append(($0, $1)) })
        p.geometry = pad.geometry
        let d = g.dpad, right = CGPoint(x: d.midX + d.width * 0.4, y: d.midY)
        p.pointerDown(PointerEvent(id: 1, x: right.x, y: right.y, t: 1000))
        p.pointerDown(PointerEvent(id: 2, x: right.x, y: right.y, t: 1040))
        p.pointerUp(PointerEvent(id: 1, x: right.x, y: right.y, t: 1050))
        XCTAssertEqual(edges.map { "\($0.0)\($0.1 ? "+" : "-")" }, ["right+", "right-", "right+"])
    }

    func testReleaseAllKeepsTheHand() {
        let d = g.dpad
        for i in 0..<4 { // a few taps: the rest estimate learns
            down(20 + i, CGPoint(x: d.midX + 10, y: d.midY - d.width * 0.3))
            frames(40)
            up(20 + i)
            frames(40)
        }
        XCTAssertNotNil(pad.restEstimate())
        down(30, CGPoint(x: d.midX, y: d.midY - d.width * 0.4))
        pad.releaseAll()
        XCTAssertEqual(held, [])
        XCTAssertEqual(pad.ox, 0)
        XCTAssertEqual(pad.oy, 0)
        XCTAssertNotNil(pad.restEstimate(), "the rest estimate describes the hand: kept")
    }
}
