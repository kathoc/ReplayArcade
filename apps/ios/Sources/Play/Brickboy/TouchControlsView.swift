// The on-screen gamepad: NESTERM's Brickboy controller (TouchGamepad, input.mjs) drawn with Core
// Animation in the look of web/styles.css, fed with raw UITouch events. Every touch is handled at
// once on the main thread (no gesture recognisers, no SwiftUI in the path); a press reaches the
// engine through onChange → AppModel.touchButtons → rn_input_set_pressed, which the emulation
// thread samples just in time for the next frame. Touches that land on no control fall through
// to the views below (the seek bar, the menu).
//
// DOM → UIKit (apps/ios/docs/TOUCH_PORT.md): pointerdown/move/up/cancel = touchesBegan/Moved/
// Ended/Cancelled (one PointerEvent per UITouch, its latest location: pointermove carries no
// coalesced samples either); setPointerCapture = UIKit keeps a touch with the view it began in
// (TouchGamepad remembers the region); requestAnimationFrame = a 60 Hz CADisplayLink (Safari's
// rAF rate, which SHARE_RAMP_TICKS and the per-tick decays assume).
//
// Portions derived from Brickboy / NESTERM (web/brickboy/input.mjs markup, web/styles.css),
// Copyright 2026 Katsuya Hokamura, Apache-2.0 (apps/ios/ThirdParty/brickboy/LICENSE).
// SPDX-License-Identifier: Apache-2.0 AND GPL-2.0-or-later
import QuartzCore
import UIKit

/// styles.css :root custom properties.
enum BBColor {
    static let bg = UIColor(rgb: 0x0c0f14)          // --bb-bg
    static let bg2 = UIColor(rgb: 0x14181f)         // --bb-bg-2
    static let bg3 = UIColor(rgb: 0x1b212b)         // --bb-bg-3
    static let line = UIColor(rgb: 0x262d38)        // --bb-line
    static let text = UIColor(rgb: 0xc7cedb)        // --bb-text
    static let textDim = UIColor(rgb: 0x7f8a9b)     // --bb-text-dim
    static let accent = UIColor(rgb: 0x6ee7b7)      // --bb-accent
    static let accentPress = UIColor(rgb: 0x34d399) // --bb-accent-press
    static let btn = UIColor(rgb: 0x232b36)         // --bb-btn
    static let btnPress = UIColor(rgb: 0x2f3a49)    // --bb-btn-press

    /// filter: brightness(k) (the gp-onset keyframe starts at brightness(2.4)).
    static func brightness(_ c: UIColor, _ k: CGFloat) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        return UIColor(red: min(1, r * k), green: min(1, g * k), blue: min(1, b * k), alpha: a)
    }
}

extension UIColor {
    convenience init(rgb: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((rgb >> 16) & 0xff) / 255, green: CGFloat((rgb >> 8) & 0xff) / 255,
                  blue: CGFloat(rgb & 0xff) / 255, alpha: alpha)
    }
}

/// Shared drawing helpers for the controller layers.
enum BBDraw {
    /// A CATextLayer with `text` centred on `centre` (one line, the font's line height).
    static func label(_ text: String, size: CGFloat, weight: UIFont.Weight, tracking: CGFloat = 0, color: UIColor,
                      centre: CGPoint, scale: CGFloat) -> CATextLayer {
        let font = UIFont.systemFont(ofSize: size, weight: weight)
        let t = CATextLayer()
        t.string = NSAttributedString(string: text, attributes: [.font: font, .kern: tracking, .foregroundColor: color.cgColor])
        t.alignmentMode = .center
        t.contentsScale = scale
        // The trailing letter-spacing CSS adds after the last character is not drawn: centre the
        // glyphs themselves.
        let w = ceil((text as NSString).size(withAttributes: [.font: font]).width + tracking * CGFloat(max(0, text.count - 1))) + 4
        let h = ceil(font.lineHeight)
        t.frame = CGRect(x: centre.x - w / 2, y: centre.y - h / 2, width: w, height: h)
        return t
    }

    static func setColor(_ t: CATextLayer, _ c: UIColor) {
        guard let s = t.string as? NSAttributedString else { return }
        let m = NSMutableAttributedString(attributedString: s)
        m.addAttribute(.foregroundColor, value: c.cgColor, range: NSRange(location: 0, length: m.length))
        t.string = m
    }

    /// The gp-onset keyframes: brightness(2.4) → brightness(1) over 130 ms, ease-out.
    static func onset(_ layer: CALayer, keyPath: String, from: CGColor, to: CGColor) {
        let a = CABasicAnimation(keyPath: keyPath)
        a.fromValue = from
        a.toValue = to
        a.duration = 0.13
        a.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(a, forKey: "gp-onset-" + keyPath)
    }
}

final class TouchControlsView: UIView {
    /// Pressed, released (main thread).
    var onChange: (([TouchButton], [TouchButton]) -> Void)?
    var haptics = true
    var controlOpacity: CGFloat = 1 { didSet { if controlOpacity != oldValue { layer.opacity = Float(controlOpacity) } } }
    var layoutModel: TouchLayout? {
        didSet {
            guard layoutModel != oldValue, let l = layoutModel else { return }
            pad.geometry = l.pad
            // input.mjs relayoutSignal / relayout(): a learned home re-clamped to the new geometry.
            pad.relayout()
            rebuild()
        }
    }

    /// The ported Brickboy gamepad (input.mjs TouchGamepad).
    private(set) var pad: TouchGamepad!
    private var link: CADisplayLink?
    private let impact = UIImpactFeedbackGenerator(style: .light)
    /// pointerId per UITouch.
    private var ids: [ObjectIdentifier: Int] = [:]
    private var nextID = 1

    // Layers (the DOM of input.mjs's constructor).
    private let dpadLayer = CALayer()             // .gp-dpad (transform: translate(ox, oy))
    private var arrows: [BBButton: CATextLayer] = [:] // .gp-arrow
    private var edges: [BBButton: CALayer] = [:]      // .gp-edge
    private var keys: [BBButton: (body: CALayer, label: CATextLayer)] = [:] // .gp-key (rounds, pills)
    private var shown: Set<BBButton> = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        isExclusiveTouch = false
        backgroundColor = .clear
        pad = TouchGamepad(press: { [weak self] b, down in
            let t = TouchButton(b)
            self?.onChange?(down ? [t] : [], down ? [] : [t])
        })
        pad.onHaptic = { [weak self] in
            guard let self, self.haptics else { return }
            // navigator.vibrate(HAPTIC_MS = 8) / the <input switch> Taptic tick: one light impact.
            self.impact.impactOccurred()
            self.impact.prepare()
        }
        pad.onVisual = { [weak self] in self?.restyle() }
        pad.onAnimationFrameRequest = { [weak self] in self?.startLink() }
        impact.prepare()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit { link?.invalidate() }

    // MARK: rAF

    private final class LinkTarget {
        weak var view: TouchControlsView?
        init(_ v: TouchControlsView) { view = v }
        @objc func step(_ l: CADisplayLink) { view?.frameTick(l) }
    }

    private func startLink() {
        if let link { link.isPaused = false; return }
        let l = CADisplayLink(target: LinkTarget(self), selector: #selector(LinkTarget.step(_:)))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
        l.add(to: .main, forMode: .common)
        link = l
    }

    private func frameTick(_ l: CADisplayLink) {
        pad.animationFrame(now: l.timestamp * 1000)
        if !pad.hasPendingAnimationFrame { l.isPaused = true }
    }

    // MARK: touches

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard !isHidden, layoutModel != nil else { return false }
        return pad.regionAt(point) != nil
    }

    private static let logEvents = UserDefaults.standard.bool(forKey: "logTouchEvents")

    private func event(_ t: UITouch, id: Int) -> PointerEvent {
        let p = t.location(in: self)
        if Self.logEvents { NSLog("ReplayNES touch event: %d phase %d (%.1f, %.1f) t %.1f", id, t.phase.rawValue, p.x, p.y, t.timestamp * 1000) }
        return PointerEvent(id: id, x: p.x, y: p.y, t: t.timestamp * 1000)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard layoutModel != nil else { return }
        for t in touches.sorted(by: { $0.timestamp < $1.timestamp }) {
            let id = nextID
            nextID += 1
            if pad.pointerDown(self.event(t, id: id)) != nil { ids[ObjectIdentifier(t)] = id }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches.sorted(by: { $0.timestamp < $1.timestamp }) {
            guard let id = ids[ObjectIdentifier(t)] else { continue }
            pad.pointerMove(self.event(t, id: id))
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { lift(touches) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { lift(touches) }

    private func lift(_ touches: Set<UITouch>) {
        for t in touches {
            guard let id = ids.removeValue(forKey: ObjectIdentifier(t)) else { continue }
            pad.pointerUp(self.event(t, id: id))
        }
    }

    /// input.mjs releaseAll (menu opened, controls hidden, app in the background).
    func releaseAll() {
        ids.removeAll()
        pad.releaseAll()
    }

    func setWays(_ n: Int) { pad.setWays(n) }
    func setHomeGain(x: CGFloat, y: CGFloat) { pad.setHomeGain(x, y) }

    // MARK: drawing (input.mjs constructor markup + styles.css)

    private func rebuild() {
        layer.sublayers?.forEach { $0.removeFromSuperlayer() }
        arrows.removeAll()
        edges.removeAll()
        keys.removeAll()
        dpadLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
        guard let l = layoutModel else { return }
        let scale = window?.screen.scale ?? traitCollection.displayScale
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        // .gp-dpad: the cross (::before / ::after), hub, arrows, perimeter edges.
        let d = l.pad.dpad.width
        dpadLayer.frame = l.pad.dpad
        dpadLayer.actions = ["position": NSNull(), "bounds": NSNull()]
        let bar = d * 0.34
        for r in [CGRect(x: (d - bar) / 2, y: 0, width: bar, height: d),   // ::before { width: 34%; height: 100% }
                  CGRect(x: 0, y: (d - bar) / 2, width: d, height: bar)] { // ::after { width: 100%; height: 34% }
            let s = CALayer()
            s.frame = r
            s.backgroundColor = BBColor.btn.cgColor
            s.cornerRadius = 12
            dpadLayer.addSublayer(s)
        }
        // box-shadow: inset 0 1px 0 rgb(255 255 255 / 4%): a 1 px highlight along the bars' tops.
        for r in [CGRect(x: (d - bar) / 2 + 6, y: 0, width: bar - 12, height: 1),
                  CGRect(x: 6, y: (d - bar) / 2, width: (d - bar) / 2 - 6, height: 1),
                  CGRect(x: (d + bar) / 2, y: (d - bar) / 2, width: (d - bar) / 2 - 6, height: 1)] {
            let h = CALayer()
            h.frame = r
            h.backgroundColor = UIColor(white: 1, alpha: 0.04).cgColor
            dpadLayer.addSublayer(h)
        }
        // .gp-hub { width: 22%; height: 22%; border-radius: 50%; background: var(--bb-bg-3) }
        let hub = CALayer()
        hub.frame = CGRect(x: d * 0.39, y: d * 0.39, width: d * 0.22, height: d * 0.22)
        hub.cornerRadius = d * 0.11
        hub.backgroundColor = BBColor.bg3.cgColor
        dpadLayer.addSublayer(hub)
        // .gp-arrow { font-size: 13px; line-height: 1 }: up/down at 7% from the top/bottom, centred;
        // left/right at 7% from the sides.
        let arrowDefs: [(BBButton, String, CGPoint)] = [
            (.up, "▲", CGPoint(x: d / 2, y: d * 0.07 + 6.5)),
            (.down, "▼", CGPoint(x: d / 2, y: d * 0.93 - 6.5)),
            (.left, "◀", CGPoint(x: d * 0.07 + 6.5, y: d / 2)),
            (.right, "▶", CGPoint(x: d * 0.93 - 6.5, y: d / 2)),
        ]
        for (b, s, c) in arrowDefs {
            let t = BBDraw.label(s, size: 13, weight: .regular, color: BBColor.textDim, centre: c, scale: scale)
            t.shadowColor = BBColor.accentPress.cgColor
            t.shadowOffset = .zero
            t.shadowRadius = 4 // text-shadow: 0 0 8px
            t.shadowOpacity = 0
            dpadLayer.addSublayer(t)
            arrows[b] = t
        }
        // .gp-edge: up/down { left: 22%; right: 22%; height: 5px; top/bottom: -4px },
        // left/right { top: 22%; bottom: 22%; width: 5px; left/right: -4px }.
        let edgeDefs: [(BBButton, CGRect)] = [
            (.up, CGRect(x: d * 0.22, y: -4, width: d * 0.56, height: 5)),
            (.down, CGRect(x: d * 0.22, y: d - 1, width: d * 0.56, height: 5)),
            (.left, CGRect(x: -4, y: d * 0.22, width: 5, height: d * 0.56)),
            (.right, CGRect(x: d - 1, y: d * 0.22, width: 5, height: d * 0.56)),
        ]
        for (b, r) in edgeDefs {
            let e = CALayer()
            e.frame = r
            e.cornerRadius = 2.5 // border-radius: 5px on a 5 px bar
            e.backgroundColor = BBColor.accentPress.cgColor
            // box-shadow: 0 0 12px 3px var(--bb-accent-press)
            e.shadowColor = BBColor.accentPress.cgColor
            e.shadowOffset = .zero
            e.shadowRadius = 6
            e.shadowOpacity = 1
            e.shadowPath = UIBezierPath(roundedRect: CGRect(origin: .zero, size: r.size).insetBy(dx: -3, dy: -3), cornerRadius: 5.5).cgPath
            e.opacity = 0
            dpadLayer.addSublayer(e)
            edges[b] = e
        }
        layer.addSublayer(dpadLayer)

        // .gp-face: .gp-round B, A (font-size: 20px; font-weight: 700).
        let btn = l.faceButton
        for (b, c, s) in [(BBButton.b, l.pad.b, "B"), (BBButton.a, l.pad.a, "A")] {
            let body = CALayer()
            body.frame = CGRect(x: c.x - btn / 2, y: c.y - btn / 2, width: btn, height: btn)
            body.cornerRadius = btn / 2
            let t = BBDraw.label(s, size: 20, weight: .bold, color: BBColor.text, centre: CGPoint(x: btn / 2, y: btn / 2), scale: scale)
            body.addSublayer(t)
            layer.addSublayer(body)
            keys[b] = (body, t)
        }
        // .gp-system: .gp-pill SELECT, START.
        for (b, r, s) in [(BBButton.select, l.select, "SELECT"), (BBButton.start, l.start, "START")] {
            let body = CALayer()
            body.frame = r
            body.cornerRadius = r.height / 2
            let t = BBDraw.label(s, size: TouchLayout.pillFont, weight: .semibold, tracking: TouchLayout.pillTracking,
                                 color: BBColor.text, centre: CGPoint(x: r.width / 2, y: r.height / 2), scale: scale)
            body.addSublayer(t)
            layer.addSublayer(body)
            keys[b] = (body, t)
        }
        CATransaction.commit()
        shown = []
        restyle(animated: false)
    }

    /// The gp-active classes and the pad's transform, with the CSS transitions (.gp-key:
    /// background / transform .06s; .gp-arrow: color .06s; .gp-edge: opacity .05s) and the
    /// gp-onset keyframes on each activation.
    private func restyle(animated: Bool = true) {
        guard layoutModel != nil else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dpadLayer.setAffineTransform(CGAffineTransform(translationX: pad.ox, y: pad.oy))
        CATransaction.commit()

        var now: Set<BBButton> = []
        for b in BBButton.allCases where pad.isActive(b) { now.insert(b) }
        let changed = now.symmetricDifference(shown)
        guard !changed.isEmpty || !animated else { return }
        let onsets = now.subtracting(shown)
        shown = now

        for (b, t) in arrows {
            let on = now.contains(b)
            CATransaction.begin()
            CATransaction.setAnimationDuration(animated ? 0.06 : 0)
            CATransaction.setDisableActions(!animated)
            BBDraw.setColor(t, on ? BBColor.accentPress : BBColor.textDim)
            t.shadowOpacity = on ? 1 : 0
            CATransaction.commit()
        }
        for (b, e) in edges {
            let on = now.contains(b)
            CATransaction.begin()
            CATransaction.setAnimationDuration(animated ? 0.05 : 0)
            CATransaction.setDisableActions(!animated)
            e.opacity = on ? 0.95 : 0
            CATransaction.commit()
            if animated && onsets.contains(b) {
                BBDraw.onset(e, keyPath: "backgroundColor", from: BBColor.brightness(BBColor.accentPress, 2.4).cgColor, to: BBColor.accentPress.cgColor)
            }
        }
        for (b, k) in keys {
            let on = now.contains(b)
            let round = b == .a || b == .b
            CATransaction.begin()
            CATransaction.setAnimationDuration(animated ? 0.06 : 0)
            CATransaction.setDisableActions(!animated)
            // .gp-key { box-shadow: inset 0 1px 0 rgb(255 255 255 / 5%), 0 2px 6px rgb(0 0 0 / 40%) }
            // .gp-key.gp-active { --gp-scale: .94; color: accent; background: btn-press;
            //   box-shadow: inset 0 2px 6px rgb(0 0 0 / 50%), 0 0 10px -2px accent }
            // .gp-round.gp-active { --gp-press: -3px }
            k.body.backgroundColor = (on ? BBColor.btnPress : BBColor.btn).cgColor
            k.body.shadowColor = (on ? BBColor.accent : UIColor.black).cgColor
            k.body.shadowOffset = on ? .zero : CGSize(width: 0, height: 2)
            k.body.shadowRadius = on ? 4 : 3
            k.body.shadowOpacity = on ? 0.7 : 0.4
            var tr = CATransform3DIdentity
            if on {
                if round { tr = CATransform3DTranslate(tr, 0, -3, 0) }
                tr = CATransform3DScale(tr, 0.94, 0.94, 1)
            }
            k.body.transform = tr
            BBDraw.setColor(k.label, on ? BBColor.accent : BBColor.text)
            CATransaction.commit()
            if animated && onsets.contains(b) {
                BBDraw.onset(k.body, keyPath: "backgroundColor", from: BBColor.brightness(BBColor.btnPress, 2.4).cgColor, to: BBColor.btnPress.cgColor)
            }
        }
    }
}
