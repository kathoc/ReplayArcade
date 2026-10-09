// On-screen controls: where the picture and each control go for a screen size (portrait: picture
// on top, controls below it; landscape: picture centred, controls in the side columns) and what a
// touch point hits. Pure geometry (points, origin top-left), unit-tested in TouchLayoutTests.
// SPDX-License-Identifier: GPL-2.0-or-later
import CoreGraphics
import Foundation

/// One on-screen button. Game buttons reach the engine as the physical ids "touch:<name>" (bound
/// like a controller's: TouchBindings); `menu` opens the Quick Menu directly.
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

    var label: String {
        switch self {
        case .up: return "▲"
        case .down: return "▼"
        case .left: return "◀"
        case .right: return "▶"
        case .a: return "A"
        case .b: return "B"
        case .turboA: return "TA"
        case .turboB: return "TB"
        case .select: return "SELECT"
        case .start: return "START"
        case .l: return "L"
        case .r: return "R"
        case .l2: return "L2"
        case .r2: return "R2"
        case .menu: return "☰"
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

struct TouchControl: Equatable {
    enum Kind: Equatable {
        case dpad       // four directions (and diagonals) around the centre
        case face       // round A / B / turbo: neighbouring face buttons can be pressed together
        case pill       // SELECT / START / menu
        case shoulder   // L / R / L2 / R2
    }
    let kind: Kind
    let frame: CGRect
    let buttons: [TouchButton]

    var center: CGPoint { CGPoint(x: frame.midX, y: frame.midY) }
    var radius: CGFloat { min(frame.width, frame.height) / 2 }
}

struct TouchInsets: Equatable {
    var top: CGFloat = 0, left: CGFloat = 0, bottom: CGFloat = 0, right: CGFloat = 0
}

struct TouchLayout: Equatable {
    struct Options: Equatable {
        var showTurbo = false
        /// Control size multiplier (Settings: Touch Controls size).
        var scale: CGFloat = 1
    }

    var size: CGSize
    var landscape: Bool
    /// The area the game view covers (the renderer centres and scales the picture inside it).
    var gameArea: CGRect
    var controls: [TouchControl]

    /// Extra reach around a control that still counts as hitting it (fingers are imprecise).
    static let slop: CGFloat = 12
    /// D-pad: no direction within this fraction of the radius from the centre.
    static let deadZone: CGFloat = 0.22

    static func make(size: CGSize, safe: TouchInsets, options: Options = Options()) -> TouchLayout {
        size.width > size.height ? landscape(size, safe, options) : portrait(size, safe, options)
    }

    /// NES picture aspect with the overscan rows hidden (256 x 224).
    static let pictureAspect: CGFloat = 256.0 / 224.0

    // MARK: portrait

    private static func portrait(_ size: CGSize, _ safe: TouchInsets, _ o: Options) -> TouchLayout {
        let w = size.width
        let top = safe.top
        let gameH = (w / pictureAspect).rounded()
        let game = CGRect(x: 0, y: top, width: w, height: gameH)
        let area = CGRect(x: safe.left, y: game.maxY, width: w - safe.left - safe.right,
                          height: max(0, size.height - safe.bottom - game.maxY))
        let s = min(o.scale * min(1, area.height / 430), 1.35)
        let m: CGFloat = 18
        var c: [TouchControl] = []
        // Shoulder row.
        let sh = CGSize(width: 64 * s, height: 36 * s)
        let rowY = area.minY + 12
        c.append(TouchControl(kind: .shoulder, frame: CGRect(x: area.minX + m, y: rowY, width: sh.width, height: sh.height), buttons: [.l2]))
        c.append(TouchControl(kind: .shoulder, frame: CGRect(x: area.minX + m + sh.width + 10, y: rowY, width: sh.width, height: sh.height), buttons: [.l]))
        c.append(TouchControl(kind: .shoulder, frame: CGRect(x: area.maxX - m - 2 * sh.width - 10, y: rowY, width: sh.width, height: sh.height), buttons: [.r]))
        c.append(TouchControl(kind: .shoulder, frame: CGRect(x: area.maxX - m - sh.width, y: rowY, width: sh.width, height: sh.height), buttons: [.r2]))
        let menuW = 52 * s
        c.append(TouchControl(kind: .pill, frame: CGRect(x: area.midX - menuW / 2, y: rowY, width: menuW, height: sh.height), buttons: [.menu]))
        // D-pad and face buttons share the middle band.
        let bottomRowH = 34 * s
        let bandTop = rowY + sh.height + 10
        let bandBottom = area.maxY - bottomRowH - 22
        let bandMid = (bandTop + bandBottom) / 2
        let d = min(168 * s, bandBottom - bandTop, area.width * 0.44)
        c.append(TouchControl(kind: .dpad, frame: CGRect(x: area.minX + m, y: bandMid - d / 2, width: d, height: d),
                              buttons: [.up, .down, .left, .right]))
        let f = min(76 * s, d * 0.48)
        let ax = area.maxX - m - f, bx = ax - f * 1.18
        var ay = bandMid - f * 0.85, by = bandMid - f * 0.15
        if o.showTurbo {
            // The turbo row above A / B must stay below the shoulder row: move the pair down.
            let need = bandTop - (ay - f * 0.62 - 14)
            if need > 0 { ay += need; by += need }
        }
        c.append(TouchControl(kind: .face, frame: CGRect(x: bx, y: by, width: f, height: f), buttons: [.b]))
        c.append(TouchControl(kind: .face, frame: CGRect(x: ax, y: ay, width: f, height: f), buttons: [.a]))
        if o.showTurbo {
            let t = f * 0.62
            c.append(TouchControl(kind: .face, frame: CGRect(x: bx + (f - t) / 2, y: by - t - 14, width: t, height: t), buttons: [.turboB]))
            c.append(TouchControl(kind: .face, frame: CGRect(x: ax + (f - t) / 2, y: ay - t - 14, width: t, height: t), buttons: [.turboA]))
        }
        // SELECT / START.
        let pw = 84 * s
        let py = area.maxY - bottomRowH - 12
        c.append(TouchControl(kind: .pill, frame: CGRect(x: area.midX - pw - 8, y: py, width: pw, height: bottomRowH), buttons: [.select]))
        c.append(TouchControl(kind: .pill, frame: CGRect(x: area.midX + 8, y: py, width: pw, height: bottomRowH), buttons: [.start]))
        return TouchLayout(size: size, landscape: false, gameArea: game, controls: c)
    }

    // MARK: landscape

    private static func landscape(_ size: CGSize, _ safe: TouchInsets, _ o: Options) -> TouchLayout {
        let game = CGRect(origin: .zero, size: size)   // full screen; the picture is centred
        let picH = size.height, picW = (picH * pictureAspect).rounded()
        let side = max(0, (size.width - picW) / 2)
        let left = CGRect(x: safe.left, y: safe.top, width: max(120, side - safe.left), height: size.height - safe.top - safe.bottom)
        let right = CGRect(x: size.width - max(120, side - safe.right) - safe.right, y: safe.top,
                           width: max(120, side - safe.right), height: size.height - safe.top - safe.bottom)
        let s = min(o.scale * min(1, size.height / 390), 1.3)
        let m: CGFloat = 12
        var c: [TouchControl] = []
        let sh = CGSize(width: min(60 * s, (left.width - 3 * m) / 2), height: 34 * s)
        let rowY = left.minY + 10
        c.append(TouchControl(kind: .shoulder, frame: CGRect(x: left.minX + m, y: rowY, width: sh.width, height: sh.height), buttons: [.l2]))
        c.append(TouchControl(kind: .shoulder, frame: CGRect(x: left.minX + 2 * m + sh.width, y: rowY, width: sh.width, height: sh.height), buttons: [.l]))
        c.append(TouchControl(kind: .shoulder, frame: CGRect(x: right.maxX - 2 * m - 2 * sh.width, y: rowY, width: sh.width, height: sh.height), buttons: [.r]))
        c.append(TouchControl(kind: .shoulder, frame: CGRect(x: right.maxX - m - sh.width, y: rowY, width: sh.width, height: sh.height), buttons: [.r2]))
        let pillH = 32 * s
        let pillY = left.maxY - pillH - 10
        let d = min(158 * s, left.width - 2 * m, pillY - (rowY + sh.height) - 16)
        let mid = (rowY + sh.height + pillY) / 2 + 6
        c.append(TouchControl(kind: .dpad, frame: CGRect(x: left.midX - d / 2, y: mid - d / 2, width: d, height: d),
                              buttons: [.up, .down, .left, .right]))
        let f = min(72 * s, (right.width - 2 * m) / 2.25)
        let ax = right.maxX - m - f, ay = mid - f * 0.85
        let bx = ax - f * 1.15, by = mid - f * 0.1
        c.append(TouchControl(kind: .face, frame: CGRect(x: bx, y: by, width: f, height: f), buttons: [.b]))
        c.append(TouchControl(kind: .face, frame: CGRect(x: ax, y: ay, width: f, height: f), buttons: [.a]))
        if o.showTurbo {
            let t = f * 0.6
            c.append(TouchControl(kind: .face, frame: CGRect(x: bx + (f - t) / 2, y: by + f + 10, width: t, height: t), buttons: [.turboB]))
            c.append(TouchControl(kind: .face, frame: CGRect(x: ax + (f - t) / 2, y: ay - t - 8, width: t, height: t), buttons: [.turboA]))
        }
        let pw = min(76 * s, (left.width - 3 * m) / 2)
        c.append(TouchControl(kind: .pill, frame: CGRect(x: left.minX + m, y: pillY, width: pw, height: pillH), buttons: [.select]))
        c.append(TouchControl(kind: .pill, frame: CGRect(x: left.maxX - m - pw, y: pillY, width: pw, height: pillH), buttons: [.menu]))
        c.append(TouchControl(kind: .pill, frame: CGRect(x: right.maxX - m - pw, y: pillY, width: pw, height: pillH), buttons: [.start]))
        return TouchLayout(size: size, landscape: true, gameArea: game, controls: c)
    }

    // MARK: hit testing

    /// The control a new touch at `p` lands on (index into `controls`), nil for none. Inside a
    /// control wins; otherwise the nearest one within `slop`.
    func control(at p: CGPoint) -> Int? {
        var best: Int?, bestDist = CGFloat.greatestFiniteMagnitude
        for (i, c) in controls.enumerated() {
            let d = distance(p, c)
            if d <= 0 { return i }
            if d <= Self.slop && d < bestDist { best = i; bestDist = d }
        }
        return best
    }

    /// Distance from `p` to the control's shape (<= 0 inside).
    func distance(_ p: CGPoint, _ c: TouchControl) -> CGFloat {
        switch c.kind {
        case .dpad, .face:
            return hypot(p.x - c.center.x, p.y - c.center.y) - c.radius
        case .pill, .shoulder:
            let dx = max(c.frame.minX - p.x, 0, p.x - c.frame.maxX)
            let dy = max(c.frame.minY - p.y, 0, p.y - c.frame.maxY)
            return dx == 0 && dy == 0 ? -1 : hypot(dx, dy)
        }
    }

    /// Directions of a D-pad touch at `p`: 8-way (a diagonal = two directions); none in the
    /// dead zone. Works outside the pad too (a thumb that slid off keeps steering).
    static func directions(_ p: CGPoint, dpad c: TouchControl) -> Set<TouchButton> {
        let dx = p.x - c.center.x, dy = p.y - c.center.y
        guard hypot(dx, dy) >= c.radius * deadZone else { return [] }
        // 0° = right, counter-clockwise (screen y grows downwards).
        var deg = atan2(-dy, dx) * 180 / .pi
        if deg < 0 { deg += 360 }
        let sector = Int(((deg + 22.5).truncatingRemainder(dividingBy: 360)) / 45)
        switch sector {
        case 0: return [.right]
        case 1: return [.up, .right]
        case 2: return [.up]
        case 3: return [.up, .left]
        case 4: return [.left]
        case 5: return [.down, .left]
        case 6: return [.down]
        default: return [.down, .right]
        }
    }

    /// Face buttons under `p`: the one touched; both of a pair (B+A, turbo B+A) in the band
    /// between the two (one thumb on both, as on the real pad); else the nearest within `slop`.
    func faceButtons(at p: CGPoint) -> Set<TouchButton> {
        let faces = controls.filter { $0.kind == .face }
        for c in faces where distance(p, c) <= 0 { return Set(c.buttons) }
        let pairs: [(TouchButton, TouchButton)] = [(.b, .a), (.turboB, .turboA)]
        for (x, y) in pairs {
            guard let a = faces.first(where: { $0.buttons == [x] }), let b = faces.first(where: { $0.buttons == [y] }) else { continue }
            let vx = b.center.x - a.center.x, vy = b.center.y - a.center.y
            let len2 = vx * vx + vy * vy
            guard len2 > 0 else { continue }
            let t = ((p.x - a.center.x) * vx + (p.y - a.center.y) * vy) / len2
            let px = a.center.x + t * vx, py = a.center.y + t * vy
            if t > 0, t < 1, hypot(p.x - px, p.y - py) <= min(a.radius, b.radius) * 0.75 { return [x, y] }
        }
        var best: TouchControl?, bestDist = CGFloat.greatestFiniteMagnitude
        for c in faces {
            let d = distance(p, c)
            if d <= Self.slop && d < bestDist { best = c; bestDist = d }
        }
        return best.map { Set($0.buttons) } ?? []
    }
}
