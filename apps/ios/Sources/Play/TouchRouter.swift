// Multi-touch -> held buttons. Each finger is tracked on its own (UITouch identity) and the held
// set is the union over all fingers, so D-pad + A + B at once just works. Rules:
//  - a finger that lands on the D-pad keeps steering it until lifted, also after sliding off it;
//  - a finger on a face button may slide to the neighbouring one (or between A and B: both);
//  - a finger on SELECT / START / L / R / menu holds it while inside its reach, sliding off releases;
//  - a finger that lands on nothing stays inert.
// Pure value logic (no UIKit), unit-tested in TouchRouterTests.
// SPDX-License-Identifier: GPL-2.0-or-later
import CoreGraphics
import Foundation

struct TouchRouter {
    private struct Finger {
        var control: Int?           // index into layout.controls the finger landed on
        var buttons: Set<TouchButton> = []
    }

    private var fingers: [Int: Finger] = [:]

    /// Everything held right now.
    var held: Set<TouchButton> { fingers.values.reduce(into: Set<TouchButton>()) { $0.formUnion($1.buttons) } }

    var activeFingers: Int { fingers.count }

    /// A finger touched down at `p`. Returns the held set afterwards.
    @discardableResult
    mutating func began(_ id: Int, at p: CGPoint, layout: TouchLayout) -> Set<TouchButton> {
        let c = layout.control(at: p)
        var f = Finger(control: c)
        f.buttons = Self.buttons(for: c, at: p, layout: layout)
        fingers[id] = f
        return held
    }

    @discardableResult
    mutating func moved(_ id: Int, to p: CGPoint, layout: TouchLayout) -> Set<TouchButton> {
        guard var f = fingers[id] else { return held }
        f.buttons = Self.buttons(for: f.control, at: p, layout: layout)
        fingers[id] = f
        return held
    }

    @discardableResult
    mutating func ended(_ id: Int) -> Set<TouchButton> {
        fingers[id] = nil
        return held
    }

    /// Layout change / app in the background: every finger is forgotten.
    mutating func reset() { fingers.removeAll() }

    private static func buttons(for control: Int?, at p: CGPoint, layout: TouchLayout) -> Set<TouchButton> {
        guard let i = control, layout.controls.indices.contains(i) else { return [] }
        let c = layout.controls[i]
        switch c.kind {
        case .dpad:
            return TouchLayout.directions(p, dpad: c)
        case .face:
            return layout.faceButtons(at: p)
        case .pill, .shoulder:
            return layout.distance(p, c) <= TouchLayout.slop * 2 ? Set(c.buttons) : []
        }
    }

    /// What changed between two held sets (pressed, released), in a stable order.
    static func diff(from old: Set<TouchButton>, to new: Set<TouchButton>) -> (pressed: [TouchButton], released: [TouchButton]) {
        let order = TouchButton.allCases
        return (order.filter { new.contains($0) && !old.contains($0) }, order.filter { old.contains($0) && !new.contains($0) })
    }
}
