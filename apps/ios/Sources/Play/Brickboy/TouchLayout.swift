// Where the picture and the on-screen controls go: the geometry of NESTERM's controller CSS
// (web/styles.css, derived from Brickboy; portrait = `#app:not(.bb-side)` rules, landscape =
// `.bb-side` grid) computed for a screen size and its safe area. Every number below is the CSS
// value it comes from; apps/ios/docs/TOUCH_PORT.md maps the rules. Pure geometry (points, origin
// top-left; UIFont only measures the pill labels), unit-tested in BrickboyTouchTests.
//
// Portions derived from Brickboy / NESTERM web/styles.css, Copyright 2026 Katsuya Hokamura,
// Apache-2.0 (apps/ios/ThirdParty/brickboy/LICENSE). The ReplayNES extras row (L2 / L / MENU / R /
// R2 / turbo) and TouchButton / TouchBindings are ReplayNES's own.
// SPDX-License-Identifier: Apache-2.0 AND GPL-2.0-or-later
import CoreGraphics
import Foundation
import UIKit

/// One on-screen button as the app sees it. Game buttons reach the engine as the physical ids
/// "touch:<name>" (bound like a controller's: TouchBindings); `menu` opens the Quick Menu.
enum TouchButton: String, CaseIterable, Hashable {
    case up, down, left, right
    case a, b, turboA, turboB
    case select, start
    case l, r, l2, r2
    case menu

    /// The engine input id ("touch:dpad.up"), nil for buttons handled by the app.
    var inputID: String? {
        switch self {
        case .up, .down, .left, .right: return "touch:dpad.\(rawValue)"
        case .menu: return nil
        default: return "touch:\(rawValue)"
        }
    }

    var isDirection: Bool { self == .up || self == .down || self == .left || self == .right }

    /// The Brickboy gamepad's buttons (input-router.mjs BUTTON_NAME: right, left, up, down, a, b,
    /// select, start).
    init(_ b: BBButton) {
        switch b {
        case .right: self = .right
        case .left: self = .left
        case .up: self = .up
        case .down: self = .down
        case .a: self = .a
        case .b: self = .b
        case .select: self = .select
        case .start: self = .start
        }
    }
}

/// Default bindings of the touch ids: the same actions as a controller's (frontend core
/// defaults: L2 rewind, R2 fast-forward, L slow, R pause; turbo A / B).
enum TouchBindings {
    static let defaults: [(input: String, action: String)] = [
        ("touch:dpad.up", "p1.up"), ("touch:dpad.down", "p1.down"),
        ("touch:dpad.left", "p1.left"), ("touch:dpad.right", "p1.right"),
        ("touch:a", "p1.a"), ("touch:b", "p1.b"),
        ("touch:turboA", "p1.turbo_a"), ("touch:turboB", "p1.turbo_b"),
        ("touch:select", "p1.select"), ("touch:start", "p1.start"),
        ("touch:l", "hk.slow"), ("touch:r", "hk.pause"),
        ("touch:l2", "hk.rewind"), ("touch:r2", "hk.fast_forward"),
    ]

    /// Bindings to add to a saved configuration that has none for the touch ids (first run or a
    /// configuration from before touch controls). An existing touch binding means the user's
    /// table is kept as it is.
    static func missing(existing: [(input: String, action: String)]) -> [(input: String, action: String)] {
        if existing.contains(where: { $0.input.hasPrefix("touch:") }) { return [] }
        return defaults
    }
}

struct TouchInsets: Equatable {
    var top: CGFloat = 0, left: CGFloat = 0, bottom: CGFloat = 0, right: CGFloat = 0
}

/// A pill of the extras row (TouchExtrasView): a ReplayNES button, or NESTERM's 4/8-way switch.
struct TouchExtra: Equatable {
    enum Kind: Equatable {
        case button(TouchButton)
        case ways       // #ways-switch (controller.mjs syncWays): toggles 8-way / 4-way
    }
    let kind: Kind
    let frame: CGRect
}

struct TouchLayout: Equatable {
    struct Options: Equatable {
        var showTurbo = false
        /// --bb-dpad (controller.mjs applySize: 130...210 px, CSS default 144px).
        var dpadSize: CGFloat = TouchLayout.dpadDefault
        /// 8 or 4: the label of the ways switch ("8-WAY").
        var ways = 8
    }

    var size: CGSize
    var landscape: Bool
    /// The area the game view covers (the renderer centres and scales the picture inside it).
    var gameArea: CGRect
    /// TouchGamepad's geometry (the D-pad at its natural place, A/B, SELECT/START, hit boxes).
    var pad: TouchGamepad.Geometry
    /// The A/B button diameter (--gp-btn).
    var faceButton: CGFloat
    /// SELECT / START pills (drawn; their hit areas are in `pad`).
    var select: CGRect
    var start: CGRect
    /// The ReplayNES extras row.
    var extras: [TouchExtra]

    static let dpadDefault: CGFloat = 144
    static let dpadRange: ClosedRange<CGFloat> = 130...210

    /// NES picture aspect with the overscan rows hidden (256 x 224).
    static let pictureAspect: CGFloat = 256.0 / 224.0

    // :root { font: 15px/1.4 system-ui }: buttons inherit the line height (1.4).
    static let lineHeight: CGFloat = 1.4
    // .gp-pill { padding: 8px 22px; font-size: 11px; font-weight: 600; letter-spacing: 1px }
    static let pillFont: CGFloat = 11
    static let pillTracking: CGFloat = 1
    static let pillPadX: CGFloat = 22
    static let pillPadY: CGFloat = 8
    // .bb-mode-switch, .bb-turbo-switch { padding: 5px 10px; border: 1px; font-size: 11px;
    //   font-weight: 600; letter-spacing: .4px } - the style of the extras row.
    static let switchTracking: CGFloat = 0.4
    static let switchPadX: CGFloat = 10
    static let switchPadY: CGFloat = 5
    static let switchBorder: CGFloat = 1
    // .bb-subbar { gap: 6px; min-height: 34px; padding: 0 8px 4px }
    static let subbarHeight: CGFloat = 34
    static let subbarPadX: CGFloat = 8
    static let subbarPadBottom: CGFloat = 4
    static let subbarGap: CGFloat = 6
    // .gp-face { --gp-gap: 2px; --gp-tilt: .4502 }
    static let faceGap: CGFloat = 2
    static let faceTilt: CGFloat = 0.4502

    static func make(size: CGSize, safe: TouchInsets, options: Options = Options()) -> TouchLayout {
        // controller.mjs syncViewport: root.classList.toggle('bb-side', width > height).
        size.width > size.height ? landscape(size, safe, options) : portrait(size, safe, options)
    }

    // MARK: text metrics

    /// Width of a label in the system font (system-ui), CSS letter-spacing added after every
    /// character.
    static func textWidth(_ s: String, size: CGFloat, weight: UIFont.Weight, tracking: CGFloat) -> CGFloat {
        let f = UIFont.systemFont(ofSize: size, weight: weight)
        return ceil((s as NSString).size(withAttributes: [.font: f]).width * 100) / 100 + tracking * CGFloat(s.count)
    }

    /// A .gp-pill's size (SELECT / START); `minHeight`: portrait's `.gp-pill { min-height: 40px }`.
    static func pillSize(_ label: String, minHeight: CGFloat) -> CGSize {
        let w = textWidth(label, size: pillFont, weight: .semibold, tracking: pillTracking) + 2 * pillPadX
        return CGSize(width: w, height: max(minHeight, pillFont * lineHeight + 2 * pillPadY))
    }

    /// A .bb-mode-switch-styled pill (the extras row).
    static func switchSize(_ label: String) -> CGSize {
        let w = textWidth(label, size: pillFont, weight: .semibold, tracking: switchTracking) + 2 * (switchPadX + switchBorder)
        return CGSize(width: w, height: pillFont * lineHeight + 2 * (switchPadY + switchBorder))
    }

    static func label(_ k: TouchExtra.Kind, ways: Int) -> String {
        switch k {
        case .ways: return ways == 4 ? "4-WAY" : "8-WAY"
        case .button(let b):
            switch b {
            case .l2: return "L2"
            case .l: return "L"
            case .r: return "R"
            case .r2: return "R2"
            case .menu: return "MENU"
            case .turboA: return "A ⟳"
            case .turboB: return "B ⟳"
            default: return b.rawValue.uppercased()
            }
        }
    }

    /// Lays `kinds` out left to right from `x`, vertically centred on `midY`.
    private static func row(_ kinds: [TouchExtra.Kind], x: CGFloat, midY: CGFloat, ways: Int) -> [TouchExtra] {
        var out: [TouchExtra] = []
        var cx = x
        for k in kinds {
            let s = switchSize(label(k, ways: ways))
            out.append(TouchExtra(kind: k, frame: CGRect(x: cx, y: midY - s.height / 2, width: s.width, height: s.height)))
            cx += s.width + subbarGap
        }
        return out
    }

    private static func rowWidth(_ kinds: [TouchExtra.Kind], ways: Int) -> CGFloat {
        kinds.isEmpty ? 0 : kinds.map { switchSize(label($0, ways: ways)).width }.reduce(0, +) + subbarGap * CGFloat(kinds.count - 1)
    }

    /// The A/B pad: `.gp-face` box (padding included) at (x, y) and the centres of the rounds.
    /// display: flex; align-items: center; B first; .gp-b translateY(+off), .gp-a translateY(-off).
    private static func face(x: CGFloat, midY: CGFloat, btn: CGFloat, padX: CGFloat, padY: CGFloat) -> (box: CGRect, a: CGPoint, b: CGPoint) {
        let off = (btn + faceGap) * faceTilt
        let w = 2 * padX + 2 * btn + faceGap
        let h = btn + 2 * padY
        let box = CGRect(x: x, y: midY - h / 2, width: w, height: h)
        let b = CGPoint(x: x + padX + btn / 2, y: midY + off)
        let a = CGPoint(x: x + padX + btn + faceGap + btn / 2, y: midY - off)
        return (box, a, b)
    }

    // MARK: portrait (#app:not(.bb-side))

    private static func portrait(_ size: CGSize, _ safe: TouchInsets, _ o: Options) -> TouchLayout {
        let W = size.width, H = size.height
        // The picture on top, full width (ReplayNES; NESTERM's top bar is not used, see
        // TOUCH_PORT.md). app.mjs resizeScreen shrinks the screen row to the picture so the
        // controls get the rest.
        let gameH = (W / pictureAspect).rounded()
        let game = CGRect(x: 0, y: safe.top, width: W, height: gameH)

        // .bb-subbar under the picture: the extras row.
        let subbar = CGRect(x: 0, y: game.maxY, width: W, height: subbarHeight)
        let midY = subbar.minY + (subbarHeight - subbarPadBottom) / 2
        let left: [TouchExtra.Kind] = [.ways]
        let centre: [TouchExtra.Kind] = [.button(.l2), .button(.l), .button(.menu), .button(.r), .button(.r2)]
        let right: [TouchExtra.Kind] = o.showTurbo ? [.button(.turboB), .button(.turboA)] : []
        var extras = row(left, x: subbarPadX, midY: midY, ways: o.ways)
        let rightW = rowWidth(right, ways: o.ways)
        let rightX = W - subbarPadX - rightW
        // The middle group is centred like .bb-grid-caption (flex: 1 1 auto; text-align: center)
        // between the side items.
        let cw = rowWidth(centre, ways: o.ways)
        let lo = (extras.last?.frame.maxX ?? subbarPadX) + subbarGap
        let hi = right.isEmpty ? W - subbarPadX : rightX - subbarGap
        extras += row(centre, x: min(max(lo, (W - cw) / 2), max(lo, hi - cw)), midY: midY, ways: o.ways)
        extras += row(right, x: rightX, midY: midY, ways: o.ways)

        // #app:not(.bb-side) > .bb-root > .bb-gamepad { flex: 1 1 auto;
        //   grid-template-rows: minmax(0, 1fr) auto; padding: 6px 12px calc(6px + safe-bottom);
        //   padding-inline: clamp(12px, 4.5vw, 24px); gap: 4px 8px; clip-path: inset(0) }
        let gamepad = CGRect(x: 0, y: subbar.maxY, width: W, height: max(0, H - subbar.maxY))
        let pi = min(max(12, 0.045 * W), 24)
        let contentTop = gamepad.minY + 6
        let contentBottom = gamepad.maxY - (6 + safe.bottom)
        // Row 2: .gp-system { padding: 4px 0 } around the pills (min-height: 40px).
        let sel = pillSize("SELECT", minHeight: 40), sta = pillSize("START", minHeight: 40)
        let systemH = max(sel.height, sta.height) + 8
        let row1 = CGRect(x: pi, y: contentTop, width: W - 2 * pi, height: max(0, contentBottom - contentTop - 4 - systemH))
        let row2 = CGRect(x: pi, y: row1.maxY + 4, width: W - 2 * pi, height: systemH)

        // #app:not(.bb-side) .gp-dpad { width: min(var(--bb-dpad, 144px), max(112px, el-h * .24)) };
        // .gp-dpad { justify-self: start; margin-left: 2px }; align-items: center.
        let d = min(o.dpadSize, max(112, H * 0.24))
        let dpad = CGRect(x: pi + 2, y: row1.midY - d / 2, width: d, height: d)

        // #app:not(.bb-side) .gp-face { justify-self: end;
        //   --gp-btn: clamp(48px, min(19vw, el-h * .13), 78px); padding: calc(var(--gp-off) + 4px) 4px }
        let btn = min(max(48, min(0.19 * W, 0.13 * H)), 78)
        let off = (btn + faceGap) * faceTilt
        let faceW = 2 * 4 + 2 * btn + faceGap
        let f = face(x: W - pi - faceW, midY: row1.midY, btn: btn, padX: 4, padY: off + 4)

        // .gp-system { display: flex; justify-content: center; gap: 22px }.
        let total = sel.width + 22 + sta.width
        let px = row2.minX + (row2.width - total) / 2
        let select = CGRect(x: px, y: row2.minY + 4, width: sel.width, height: sel.height)
        let start = CGRect(x: select.maxX + 22, y: row2.minY + 4, width: sta.width, height: sta.height)

        var g = TouchGamepad.Geometry()
        g.viewport = size
        g.frame = CGRect(origin: .zero, size: size) // .bb-root has no padding in portrait
        g.dpad = dpad
        g.dpadClip = gamepad
        g.face = f.box
        g.a = f.a
        g.b = f.b
        g.system = row2
        g.select = select
        g.start = start
        return TouchLayout(size: size, landscape: false, gameArea: game, pad: g, faceButton: btn,
                           select: select, start: start, extras: extras)
    }

    // MARK: landscape (.bb-side)

    private static func landscape(_ size: CGSize, _ safe: TouchInsets, _ o: Options) -> TouchLayout {
        let W = size.width, H = size.height
        // .bb-root > .bb-screen-wrap { position: absolute; inset: 0 }: the picture is centred in
        // the whole screen, the controls are drawn over the side columns.
        let game = CGRect(origin: .zero, size: size)
        // .bb-side > .bb-root { padding: 0 calc(safe-right + edge-gap) 0 calc(safe-left + edge-gap);
        //   grid-template-columns: minmax(144px, 16%) 1fr minmax(144px, 16%);
        //   grid-template-rows: auto auto 1fr auto;
        //   grid-template-areas: "info screen icons" "ways screen repeat" "dpad screen face" "select screen start" }
        // (--bb-edge-gap-* resolve to 0 on iOS: min(0px, inset * 1000).)
        let content = CGRect(x: safe.left, y: 0, width: max(0, W - safe.left - safe.right), height: H)
        let col = max(144, 0.16 * content.width)
        let leftCol = CGRect(x: content.minX, y: 0, width: col, height: H)
        let rightCol = CGRect(x: content.maxX - col, y: 0, width: col, height: H)

        // Row 1 (info / icons, margin-top: safe-top): the extras row, in .bb-quick's padding (4px).
        let pillH = switchSize("L").height
        let row1H = safe.top + 4 + pillH + 4
        // Row 2 (ways / repeat): the switches.
        let row2 = CGRect(x: 0, y: row1H, width: W, height: pillH)
        // Row 4 (select / start): .gp-pill { align-self: end; margin-bottom: calc(8px + safe-bottom) }.
        let sel = pillSize("SELECT", minHeight: 0), sta = pillSize("START", minHeight: 0)
        let row4H = max(sel.height, sta.height) + 8 + safe.bottom
        let row3 = CGRect(x: 0, y: row2.maxY, width: W, height: max(0, H - row2.maxY - row4H))

        let ways = o.ways
        let r1Left: [TouchExtra.Kind] = [.button(.l2), .button(.l)]
        let r1Right: [TouchExtra.Kind] = [.button(.r), .button(.r2), .button(.menu)]
        let r2Right: [TouchExtra.Kind] = o.showTurbo ? [.button(.turboB), .button(.turboA)] : []
        let r1Mid = safe.top + 4 + pillH / 2
        func centred(_ k: [TouchExtra.Kind], in c: CGRect, midY: CGFloat) -> [TouchExtra] {
            row(k, x: c.midX - rowWidth(k, ways: ways) / 2, midY: midY, ways: ways)
        }
        var extras = centred(r1Left, in: leftCol, midY: r1Mid)
        extras += centred(r1Right, in: rightCol, midY: r1Mid)
        // #ways-switch / #turbo-switch { justify-self: center; align-self: center }.
        extras += centred([.ways], in: leftCol, midY: row2.midY)
        extras += centred(r2Right, in: rightCol, midY: row2.midY)

        // .bb-side > .bb-root .gp-dpad { justify-self: start; margin-inline-start: var(--bb-ctl-inset)
        //   (16px); align-self: center; width: var(--bb-dpad, 144px) }
        let d = o.dpadSize
        let dpad = CGRect(x: leftCol.minX + 16, y: row3.midY - d / 2, width: d, height: d)
        // .gp-face { --gp-btn: min(19vw, 78px); padding: 48px 16px }; justify-self: end; align-self: center.
        let btn = min(0.19 * W, 78)
        let faceW = 2 * 16 + 2 * btn + faceGap
        let f = face(x: rightCol.maxX - faceW, midY: row3.midY, btn: btn, padX: 16, padY: 48)

        let pillBottom = H - 8 - safe.bottom
        let select = CGRect(x: leftCol.midX - sel.width / 2, y: pillBottom - sel.height, width: sel.width, height: sel.height)
        let start = CGRect(x: rightCol.midX - sta.width / 2, y: pillBottom - sta.height, width: sta.width, height: sta.height)

        var g = TouchGamepad.Geometry()
        g.viewport = size
        g.frame = content // the .bb-root content box (its padding is the safe area)
        g.dpad = dpad
        g.dpadClip = nil // .bb-gamepad is display: contents: no clip
        g.face = f.box
        g.a = f.a
        g.b = f.b
        g.system = nil // .gp-system is display: contents: only the pills take touches
        g.select = select
        g.start = start
        return TouchLayout(size: size, landscape: true, gameArea: game, pad: g, faceButton: btn,
                           select: select, start: start, extras: extras)
    }
}
