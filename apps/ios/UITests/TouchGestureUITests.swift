// End-to-end touches on the ported NESTERM controller in the running app (simulator): the app
// plays the engine's test ROM with -logTouch YES, which exposes an accessibility element
// "touchProbe" (label: where the controls are, value: every press / release edge so far). Each
// test synthesises real multi-touch paths with timing (XCTest's event synthesis, EventSynthesis.h)
// and checks the edges that reached AppModel.touchButtons - the same expectations as NESTERM's
// scripts/controller-check.mjs (D-pad slide + diagonal, B→A slide, two-finger latch, roll tap,
// START+SELECT overlap).
// SPDX-License-Identifier: GPL-2.0-or-later
import XCTest

final class TouchGestureUITests: XCTestCase {
    private var app: XCUIApplication!
    private var geo: [String: [Double]] = [:]
    private var probe: XCUIElement { app.otherElements["touchProbe"] }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-autoplayTestROM", "YES", "-logTouch", "YES", "-logTouchEvents", "YES", "-touchHideWithPad", "NO"]
    }

    private func start(_ orientation: UIDeviceOrientation) throws {
        XCUIDevice.shared.orientation = orientation
        app.launch()
        XCTAssertTrue(probe.waitForExistence(timeout: 15))
        // The layout settles after the session starts (the probe's label follows it).
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if let d = probe.label.data(using: .utf8), let g = try? JSONSerialization.jsonObject(with: d) as? [String: [Double]],
               let size = g["size"], (size[0] > size[1]) == orientation.isLandscape {
                geo = g
                break
            }
            Thread.sleep(forTimeInterval: 0.3)
        }
        XCTAssertFalse(geo.isEmpty, "probe geometry")
        Thread.sleep(forTimeInterval: 1.5) // the game is running
    }

    private func edges() -> [String] { ((probe.value as? String) ?? "").split(separator: " ").map(String.init) }

    private func point(_ key: String) -> CGPoint { CGPoint(x: geo[key]![0], y: geo[key]![1]) }

    /// App (window) points → the screen points the synthesiser takes, through XCUICoordinate.
    private func screen(_ p: CGPoint) -> CGPoint {
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: p.x, dy: p.y)).screenPoint
    }

    /// One gesture: `paths` = per finger [(app point, time offset s)], first = touchdown, last = lift.
    private func perform(_ name: String, _ paths: [[(CGPoint, Double)]]) throws -> [String] {
        let before = edges().count
        let record = XCSynthesizedEventRecord(name: name, interfaceOrientation: .portrait)
        for steps in paths {
            let path = XCPointerEventPath(forTouchAt: screen(steps[0].0), offset: steps[0].1)
            for s in steps.dropFirst().dropLast() { path.move(to: screen(s.0), atOffset: s.1) }
            let last = steps[steps.count - 1]
            path.move(to: screen(last.0), atOffset: last.1 - 0.01)
            path.liftUp(atOffset: last.1)
            record.add(path)
        }
        try record.synthesize()
        Thread.sleep(forTimeInterval: 0.3)
        return Array(edges().dropFirst(before))
    }

    private func along(_ f: Double) -> CGPoint {
        let a = point("a"), b = point("b")
        return CGPoint(x: b.x + (a.x - b.x) * f, y: b.y + (a.y - b.y) * f)
    }

    private func checkAll() throws {
        let d = geo["dpad"]!, c = CGPoint(x: d[0], y: d[1]), w = d[2]
        // controller-check: adaptive D-pad right slide, then the 8-way diagonal; lift releases.
        let dpad = try perform("dpad", [[(c, 0), (CGPoint(x: c.x + w * 0.4, y: c.y), 0.12),
                                         (CGPoint(x: c.x + w * 0.34, y: c.y - w * 0.34), 0.3), (CGPoint(x: c.x + w * 0.34, y: c.y - w * 0.34), 0.6)]])
        XCTAssertEqual(dpad.first, "right+", "D-pad: right first: \(dpad)")
        XCTAssertTrue(dpad.contains("up+"), "D-pad: the diagonal adds Up: \(dpad)")
        XCTAssertFalse(dpad.contains("down+") || dpad.contains("left+"), "\(dpad)")
        XCTAssertEqual(Set(dpad.filter { $0.hasSuffix("-") }), ["right-", "up-"], "\(dpad)")

        // Face B → overlap → A.
        let slide = try perform("slide", [[(along(0), 0), (along(0.5), 0.15), (along(1), 0.3), (along(1), 0.45)]])
        XCTAssertEqual(slide, ["b+", "a+", "b-", "a-"], "B→A slide")

        // Second finger during a committed hold means the other button, wherever it lands (here: on
        // A itself). XCTest's synthesiser also emits a zero-length touch for a later path at offset
        // 0 (began + ended at one timestamp, seen in -logTouchEvents): that phantom tap is the first
        // b+ b- pair, latched the same way.
        let two = try perform("two", [[(along(1), 0), (along(1), 0.7)], [(along(1), 0.2), (along(1), 0.4)]])
        XCTAssertEqual(two, ["a+", "b+", "b-", "b+", "b-", "a-"], "two-finger latch")

        // Roll tap: holding B, roll into the overlap and back part of the way, twice.
        let roll = try perform("roll", [[(along(0), 0), (along(0.55), 0.15), (along(0.40), 0.3), (along(0.56), 0.45), (along(0.42), 0.6), (along(0.42), 0.75)]])
        XCTAssertEqual(roll, ["b+", "a+", "a-", "a+", "a-", "b-"], "roll tap")

        // START + SELECT between the pills (portrait: .gp-system is one hit area).
        if !(geo["size"]![0] > geo["size"]![1]) {
            let s = point("select"), t = point("start"), m = CGPoint(x: (s.x + t.x) / 2, y: (s.y + t.y) / 2)
            let sys = try perform("system", [[(m, 0), (m, 0.3)]])
            XCTAssertEqual(Set(sys), ["select+", "start+", "select-", "start-"], "START+SELECT")
        }
    }

    func testPortraitGestures() throws {
        try start(.portrait)
        try checkAll()
    }

    func testLandscapeGestures() throws {
        try start(.landscapeLeft)
        try checkAll()
    }
}
