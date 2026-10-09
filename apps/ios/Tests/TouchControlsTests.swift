// Touch controls: layout (no overlaps, inside the screen, picture area) and multi-touch routing.
// SPDX-License-Identifier: GPL-2.0-or-later
import CoreGraphics
import XCTest

final class TouchLayoutTests: XCTestCase {
    // iPhone 16 Pro (points) with its safe areas.
    let portrait = TouchLayout.make(size: CGSize(width: 402, height: 874), safe: TouchInsets(top: 62, left: 0, bottom: 34, right: 0))
    let landscape = TouchLayout.make(size: CGSize(width: 874, height: 402), safe: TouchInsets(top: 0, left: 62, bottom: 21, right: 62))
    let small = TouchLayout.make(size: CGSize(width: 375, height: 667), safe: TouchInsets(top: 20, left: 0, bottom: 0, right: 0),
                                 options: TouchLayout.Options(showTurbo: true, scale: 1.3))
    let landscapeTurbo = TouchLayout.make(size: CGSize(width: 667, height: 375), safe: TouchInsets(),
                                          options: TouchLayout.Options(showTurbo: true, scale: 1.3))

    private func button(_ l: TouchLayout, _ b: TouchButton) -> TouchControl? { l.controls.first { $0.buttons.contains(b) } }

    func testEveryButtonOnceAndInsideTheSafeArea() {
        for (l, safe) in [(portrait, CGRect(x: 0, y: 62, width: 402, height: 874 - 96)),
                          (landscape, CGRect(x: 62, y: 0, width: 874 - 124, height: 402 - 21)),
                          (small, CGRect(x: 0, y: 20, width: 375, height: 647))] {
            var seen: [TouchButton] = []
            for c in l.controls {
                seen += c.buttons
                XCTAssertTrue(safe.insetBy(dx: -0.5, dy: -0.5).contains(c.frame), "\(c.buttons) at \(c.frame) outside \(safe)")
            }
            let expected = TouchButton.allCases.filter { ![.turboA, .turboB].contains($0) || l == small }
            XCTAssertEqual(Set(seen), Set(expected))
            XCTAssertEqual(seen.count, expected.count, "a button appears twice")
        }
    }

    func testControlsDoNotOverlap() {
        for l in [portrait, landscape, small, landscapeTurbo] {
            for (i, a) in l.controls.enumerated() {
                for b in l.controls[(i + 1)...] {
                    XCTAssertFalse(a.frame.insetBy(dx: 1, dy: 1).intersects(b.frame), "\(a.buttons) overlaps \(b.buttons)")
                }
            }
        }
    }

    func testPortraitPictureOnTopControlsBelow() {
        XCTAssertEqual(portrait.gameArea.minY, 62)
        XCTAssertEqual(portrait.gameArea.width, 402)
        XCTAssertEqual(portrait.gameArea.height, (402 / TouchLayout.pictureAspect).rounded())
        for c in portrait.controls { XCTAssertGreaterThanOrEqual(c.frame.minY, portrait.gameArea.maxY) }
    }

    func testLandscapeControlsBesideThePicture() {
        let picW = (402 * TouchLayout.pictureAspect).rounded()
        let pic = CGRect(x: (874 - picW) / 2, y: 0, width: picW, height: 402)
        XCTAssertEqual(landscape.gameArea, CGRect(x: 0, y: 0, width: 874, height: 402))
        for c in landscape.controls where c.kind == .dpad || c.kind == .face {
            XCTAssertFalse(c.frame.intersects(pic), "\(c.buttons) covers the picture")
        }
    }

    func testDpadDirectionsAndDeadZone() {
        let d = button(portrait, .up)!
        let c = d.center, r = d.radius
        XCTAssertEqual(TouchLayout.directions(c, dpad: d), [])
        XCTAssertEqual(TouchLayout.directions(CGPoint(x: c.x, y: c.y - r * 0.8), dpad: d), [.up])
        XCTAssertEqual(TouchLayout.directions(CGPoint(x: c.x + r * 0.8, y: c.y), dpad: d), [.right])
        XCTAssertEqual(TouchLayout.directions(CGPoint(x: c.x - r * 0.6, y: c.y + r * 0.6), dpad: d), [.down, .left])
        XCTAssertEqual(TouchLayout.directions(CGPoint(x: c.x + r * 0.6, y: c.y - r * 0.6), dpad: d), [.up, .right])
        // Far outside the pad (a thumb that slid off) still steers.
        XCTAssertEqual(TouchLayout.directions(CGPoint(x: c.x, y: c.y + r * 3), dpad: d), [.down])
    }

    func testFaceButtonsAloneAndTogether() {
        let a = button(portrait, .a)!, b = button(portrait, .b)!
        XCTAssertEqual(portrait.faceButtons(at: a.center), [.a])
        XCTAssertEqual(portrait.faceButtons(at: b.center), [.b])
        let mid = CGPoint(x: (a.center.x + b.center.x) / 2, y: (a.center.y + b.center.y) / 2)
        XCTAssertEqual(portrait.faceButtons(at: mid), [.a, .b])
        XCTAssertEqual(portrait.faceButtons(at: CGPoint(x: 5, y: 5)), [])
    }

    func testHitTestPrefersInsideAndAllowsSlop() {
        let start = button(portrait, .start)!
        let i = portrait.controls.firstIndex { $0.buttons == [.start] }!
        XCTAssertEqual(portrait.control(at: CGPoint(x: start.frame.midX, y: start.frame.midY)), i)
        XCTAssertEqual(portrait.control(at: CGPoint(x: start.frame.maxX + TouchLayout.slop - 2, y: start.frame.midY)), i)
        XCTAssertNil(portrait.control(at: CGPoint(x: portrait.size.width / 2, y: portrait.gameArea.midY)))
    }

    func testTouchBindingsCoverEveryGameButtonOnce() {
        let ids = TouchButton.allCases.compactMap(\.inputID)
        XCTAssertEqual(Set(TouchBindings.defaults.map(\.input)), Set(ids))
        XCTAssertEqual(TouchBindings.defaults.count, ids.count)
        XCTAssertNil(TouchButton.menu.inputID)
        XCTAssertEqual(TouchBindings.missing(existing: [("kb:1", "p1.a")]).count, TouchBindings.defaults.count)
        XCTAssertTrue(TouchBindings.missing(existing: [("touch:a", "p1.b")]).isEmpty, "a customised touch table is kept")
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

final class TouchRouterTests: XCTestCase {
    let l = TouchLayout.make(size: CGSize(width: 402, height: 874), safe: TouchInsets(top: 62, left: 0, bottom: 34, right: 0))
    private func c(_ b: TouchButton) -> TouchControl { l.controls.first { $0.buttons.contains(b) }! }

    func testMultiTouchUnion() {
        var r = TouchRouter()
        let d = c(.up)
        r.began(1, at: CGPoint(x: d.center.x + d.radius * 0.8, y: d.center.y), layout: l)
        r.began(2, at: c(.a).center, layout: l)
        r.began(3, at: c(.start).center, layout: l)
        XCTAssertEqual(r.held, [.right, .a, .start])
        r.ended(2)
        XCTAssertEqual(r.held, [.right, .start])
        r.reset()
        XCTAssertEqual(r.held, [])
    }

    func testDpadFingerKeepsSteeringAfterSlidingOff() {
        var r = TouchRouter()
        let d = c(.up)
        r.began(1, at: CGPoint(x: d.center.x, y: d.center.y - d.radius * 0.7), layout: l)
        XCTAssertEqual(r.held, [.up])
        r.moved(1, to: CGPoint(x: d.center.x + d.radius * 2.5, y: d.center.y), layout: l)
        XCTAssertEqual(r.held, [.right])
    }

    func testFaceFingerSlidesToTheOtherButton() {
        var r = TouchRouter()
        r.began(1, at: c(.b).center, layout: l)
        XCTAssertEqual(r.held, [.b])
        r.moved(1, to: c(.a).center, layout: l)
        XCTAssertEqual(r.held, [.a])
    }

    func testPillReleasesWhenTheFingerLeaves() {
        var r = TouchRouter()
        let s = c(.select)
        r.began(1, at: s.center, layout: l)
        XCTAssertEqual(r.held, [.select])
        r.moved(1, to: CGPoint(x: s.frame.midX, y: s.frame.minY - 80), layout: l)
        XCTAssertEqual(r.held, [])
    }

    func testFingerOnNothingStaysInert() {
        var r = TouchRouter()
        r.began(1, at: CGPoint(x: 200, y: 200), layout: l)   // the picture
        r.moved(1, to: c(.a).center, layout: l)
        XCTAssertEqual(r.held, [])
    }

    func testDiffIsOrderedAndComplete() {
        let d = TouchRouter.diff(from: [.a, .up], to: [.a, .left, .start])
        XCTAssertEqual(d.pressed, [.left, .start])
        XCTAssertEqual(d.released, [.up])
    }
}
