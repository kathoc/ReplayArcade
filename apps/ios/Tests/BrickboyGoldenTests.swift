// The Swift TouchGamepad against NESTERM's own: Tests/Fixtures/golden-{portrait,landscape}.json
// were recorded by running the unmodified web/brickboy/input.mjs in a browser on NESTERM's DOM and
// styles.css (apps/ios/docs/nesterm-golden: 390 x 844 and 844 x 390 CSS px, manual
// requestAnimationFrame / performance.now, CSS transitions off). Each scenario replays the same
// pointer events and display frames here and must give, after every step, the same held buttons,
// the same region for every touchdown, and the same home offset (ox, oy).
// Scenarios: the D-pad slide / diagonal / cancel of scripts/controller-check.mjs, 16 taps around a
// biased rest point (touchdown estimator + home return), a long hold (perpendicular / along-axis
// calibration, the left-edge clamp), a fast horizontal sweep, 4-way, two fingers and the .gp-ext
// hit areas, every A/B sequence of controller-check.mjs (slide, overlap, second-finger latch, roll
// tap, motion roll, slow drift, mirror, creep after a release, touchdown in the overlap) plus a
// latch that walks off and a wobbling roll, and SELECT / START.
// SPDX-License-Identifier: Apache-2.0
import CoreGraphics
import XCTest

final class BrickboyGoldenTests: XCTestCase {
    private struct Golden: Decodable {
        struct Op: Decodable {
            let op: String
            let id: Int?
            let x: Double?
            let y: Double?
            let t: Double?
            let n: Int?
        }
        struct Step: Decodable {
            let mask: Int
            let ox: Double
            let oy: Double
            let region: String?
        }
        struct Geo: Decodable {
            let viewport: [Double]
            let frame: [Double]
            let dpad: [Double]
            let dpadClip: [Double]?
            let face: [Double]
            let a: [Double]
            let b: [Double]
            let system: [Double]?
            let select: [Double]
            let start: [Double]
        }
        struct Scenario: Decodable {
            let name: String
            let geometry: Geo
            let ops: [Op]
            let trace: [Step]
        }
        let label: String
        let scenarios: [Scenario]
    }

    private func load(_ name: String) throws -> Golden {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "json"), "fixture \(name).json")
        return try JSONDecoder().decode(Golden.self, from: Data(contentsOf: url))
    }

    private static func rect(_ a: [Double]) -> CGRect { CGRect(x: a[0], y: a[1], width: a[2], height: a[3]) }

    private static func geometry(_ g: Golden.Geo) -> TouchGamepad.Geometry {
        var o = TouchGamepad.Geometry()
        o.viewport = CGSize(width: g.viewport[0], height: g.viewport[1])
        o.frame = rect(g.frame)
        o.dpad = rect(g.dpad)
        o.dpadClip = g.dpadClip.map(rect)
        o.face = rect(g.face)
        o.a = CGPoint(x: g.a[0], y: g.a[1])
        o.b = CGPoint(x: g.b[0], y: g.b[1])
        o.system = g.system.map(rect)
        o.select = rect(g.select)
        o.start = rect(g.start)
        // The recording ran with CSS transitions off: the 3 px press offset applies at once.
        o.pressTransitionMs = 0
        return o
    }

    private func replay(_ s: Golden.Scenario, label: String) {
        let pad = TouchGamepad(press: { _, _ in })
        pad.geometry = Self.geometry(s.geometry)
        pad.setHomeGain(0.3, 1) // controller.mjs applyGain defaults (recentre-x 0.3, recentre-y 1)
        XCTAssertEqual(s.ops.count, s.trace.count)
        var mismatches = 0
        for (i, (op, want)) in zip(s.ops, s.trace).enumerated() {
            var region: TouchGamepad.Region??
            switch op.op {
            case "frame": pad.animationFrame(now: op.t!)
            case "ways": pad.setWays(op.n!)
            default:
                let e = PointerEvent(id: op.id!, x: op.x!, y: op.y!, t: op.t!)
                switch op.op {
                case "down": region = .some(pad.pointerDown(e))
                case "move": pad.pointerMove(e)
                default: pad.pointerUp(e)
                }
            }
            var mask = 0
            for b in BBButton.allCases where pad.isActive(b) { mask |= 1 << b.rawValue }
            let where_ = "\(label) \(s.name) step \(i) (\(op.op) t=\(op.t ?? 0))"
            if mask != want.mask { mismatches += 1 }
            XCTAssertEqual(mask, want.mask, "held buttons, \(where_)")
            // 1e-4 px: Chrome's getBoundingClientRect of the translated pad carries single-precision
            // rounding (measured up to 8e-6 px); everything else is the same double arithmetic.
            XCTAssertEqual(Double(pad.ox), want.ox, accuracy: 1e-4, "ox, \(where_)")
            XCTAssertEqual(Double(pad.oy), want.oy, accuracy: 1e-4, "oy, \(where_)")
            if let region {
                let name: String? = region.map { r in r == .dpad ? "dpad" : r == .face ? "face" : "system" }
                XCTAssertEqual(name, want.region, "touchdown region, \(where_)")
            }
            if mismatches > 5 { return } // one divergence cascades; keep the log readable
        }
    }

    func testPortraitTracesMatchNESTERM() throws {
        let g = try load("golden-portrait")
        XCTAssertEqual(g.scenarios.count, 8)
        for s in g.scenarios { replay(s, label: g.label) }
    }

    func testLandscapeTracesMatchNESTERM() throws {
        let g = try load("golden-landscape")
        XCTAssertEqual(g.scenarios.count, 8)
        for s in g.scenarios { replay(s, label: g.label) }
    }
}
