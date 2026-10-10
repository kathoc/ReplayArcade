// The ReplayNES buttons NESTERM's controller has no equivalent for - L2 (rewind, ⏪), frame step
// back / forward, L (slow), MENU (Quick Menu), R (pause), R2 (fast-forward, ⏩) and AA / BB (turbo
// A / B above A / B) - plus NESTERM's own 4/8-way switch (#ways-switch). A separate view on top of
// the ported gamepad, so the gamepad itself stays exactly Brickboy's: the pills in the style of
// NESTERM's sub bar switches (.bb-mode-switch / .bb-turbo-switch: pill, 1 px --bb-line border, dim
// 11 px semibold text or an SF Symbol; "pressed" = accent text and border on a green tint), AA / BB
// in the .gp-round style of A / B. Being on top, AA / BB take the touchdowns in the part of
// .gp-face's padding they cover; a touch that began on the face stays with the face (its roll
// logic is unchanged). Buttons are held while the finger stays down (UIKit keeps the touch with the
// control it began on); the ways switch toggles on release inside it, as a click does.
// SPDX-License-Identifier: GPL-2.0-or-later
import QuartzCore
import UIKit

final class TouchExtrasView: UIView {
    /// Pressed, released (main thread).
    var onChange: (([TouchButton], [TouchButton]) -> Void)?
    /// The ways switch was tapped.
    var onToggleWays: (() -> Void)?
    var haptics = true
    var controlOpacity: CGFloat = 1 { didSet { if controlOpacity != oldValue { layer.opacity = Float(controlOpacity) } } }
    var extras: [TouchExtra] = [] {
        didSet { if extras != oldValue { releaseAll(); rebuild() } }
    }
    var ways = 8 { didSet { if ways != oldValue { restyle() } } }

    private var held: [ObjectIdentifier: Int] = [:] // touch → index into extras
    /// Per extra: the body and its foreground (a CATextLayer label, or a symbol drawn as a mask).
    private var layers: [(body: CALayer, fg: CALayer)] = []
    private var shown: Set<Int> = []
    private let impact = UIImpactFeedbackGenerator(style: .light)

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
        impact.prepare()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func index(at p: CGPoint) -> Int? { extras.firstIndex { $0.hit(p) } }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        !isHidden && index(at: point) != nil
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            guard let i = index(at: t.location(in: self)) else { continue }
            held[ObjectIdentifier(t)] = i
            if case .button(let b) = extras[i].kind, !isHeld(i, except: t) {
                onChange?([b], [])
                if haptics { impact.impactOccurred(); impact.prepare() }
            }
        }
        restyle()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { lift(touches, click: true) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { lift(touches, click: false) }

    private func lift(_ touches: Set<UITouch>, click: Bool) {
        for t in touches {
            guard let i = held.removeValue(forKey: ObjectIdentifier(t)), extras.indices.contains(i) else { continue }
            switch extras[i].kind {
            case .button(let b):
                if !isHeld(i, except: nil) { onChange?([], [b]) }
            case .ways:
                if click, extras[i].frame.contains(t.location(in: self)) {
                    if haptics { impact.impactOccurred(); impact.prepare() }
                    onToggleWays?()
                }
            }
        }
        restyle()
    }

    private func isHeld(_ i: Int, except t: UITouch?) -> Bool {
        held.contains { $0.value == i && (t == nil || $0.key != ObjectIdentifier(t!)) }
    }

    func releaseAll() {
        let was = Set(held.values)
        held.removeAll()
        shown.removeAll()
        let released = was.compactMap { i -> TouchButton? in
            guard extras.indices.contains(i), case .button(let b) = extras[i].kind else { return nil }
            return b
        }
        if !released.isEmpty { onChange?([], released) }
        restyle()
    }

    private func rebuild() {
        layer.sublayers?.forEach { $0.removeFromSuperlayer() }
        layers.removeAll()
        shown.removeAll()
        let scale = window?.screen.scale ?? traitCollection.displayScale
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for e in extras {
            let body = CALayer()
            body.frame = e.frame
            body.cornerRadius = e.frame.height / 2
            let centre = CGPoint(x: e.frame.width / 2, y: e.frame.height / 2)
            let fg: CALayer
            switch e.style {
            case .pill:
                body.borderWidth = TouchLayout.switchBorder
                fg = BBDraw.label(TouchLayout.label(e.kind, ways: ways), size: TouchLayout.pillFont, weight: .semibold,
                                  tracking: TouchLayout.switchTracking, color: BBColor.textDim, centre: centre, scale: scale)
            case .icon(let name):
                body.borderWidth = TouchLayout.switchBorder
                // L2 / R2 a size larger than the frame-step glyphs.
                let big = e.frame.height > TouchLayout.switchSize("L").height + 0.5
                fg = Self.symbol(name, pointSize: big ? 15 : 11, centre: centre, scale: scale)
            case .round:
                // .gp-round (A / B) with a smaller label.
                fg = BBDraw.label(TouchLayout.label(e.kind, ways: ways), size: TouchLayout.turboFont, weight: .bold,
                                  color: BBColor.text, centre: centre, scale: scale)
            }
            body.addSublayer(fg)
            layer.addSublayer(body)
            layers.append((body, fg))
        }
        CATransaction.commit()
        restyle(animated: false)
    }

    /// An SF Symbol as a layer whose background colour is the glyph's colour (the symbol is its mask).
    private static func symbol(_ name: String, pointSize: CGFloat, centre: CGPoint, scale: CGFloat) -> CALayer {
        let cfg = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        let fg = CALayer()
        guard let img = UIImage(systemName: name, withConfiguration: cfg)?.withTintColor(.black, renderingMode: .alwaysOriginal) else { return fg }
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = scale
        let cg = UIGraphicsImageRenderer(size: img.size, format: fmt).image { _ in img.draw(at: .zero) }.cgImage
        fg.frame = CGRect(x: centre.x - img.size.width / 2, y: centre.y - img.size.height / 2, width: img.size.width, height: img.size.height)
        let mask = CALayer()
        mask.frame = fg.bounds
        mask.contents = cg
        mask.contentsScale = scale
        fg.mask = mask
        fg.backgroundColor = BBColor.textDim.cgColor
        return fg
    }

    private static func setColor(_ fg: CALayer, _ c: UIColor) {
        if let t = fg as? CATextLayer { BBDraw.setColor(t, c) } else { fg.backgroundColor = c.cgColor }
    }

    private func restyle(animated: Bool = true) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        var now: Set<Int> = []
        for (i, e) in extras.enumerated() where layers.indices.contains(i) {
            let (body, fg) = layers[i]
            // [aria-pressed="true"]: the ways switch in 4-way mode, a button while it is held.
            let on: Bool
            switch e.kind {
            case .ways:
                on = ways == 4
                (fg as? CATextLayer)?.string = NSAttributedString(string: TouchLayout.label(e.kind, ways: ways), attributes: [
                    .font: UIFont.systemFont(ofSize: TouchLayout.pillFont, weight: .semibold), .kern: TouchLayout.switchTracking,
                ])
            case .button:
                on = held.values.contains(i)
            }
            if on { now.insert(i) }
            if e.style == .round {
                // .gp-key / .gp-key.gp-active / .gp-round.gp-active, as TouchControlsView draws A / B.
                body.backgroundColor = (on ? BBColor.btnPress : BBColor.btn).cgColor
                body.shadowColor = (on ? BBColor.accent : UIColor.black).cgColor
                body.shadowOffset = on ? .zero : CGSize(width: 0, height: 2)
                body.shadowRadius = on ? 4 : 3
                body.shadowOpacity = on ? 0.7 : 0.4
                body.transform = on ? CATransform3DScale(CATransform3DMakeTranslation(0, -3, 0), 0.94, 0.94, 1) : CATransform3DIdentity
                Self.setColor(fg, on ? BBColor.accent : BBColor.text)
                if animated && on && !shown.contains(i) {
                    BBDraw.onset(body, keyPath: "backgroundColor", from: BBColor.brightness(BBColor.btnPress, 2.4).cgColor, to: BBColor.btnPress.cgColor)
                }
                continue
            }
            body.backgroundColor = on ? UIColor(red: 52 / 255, green: 211 / 255, blue: 153 / 255, alpha: 0.14).cgColor
                : UIColor(red: 20 / 255, green: 24 / 255, blue: 31 / 255, alpha: 0.82).cgColor
            body.borderColor = (on ? BBColor.accentPress : BBColor.line).cgColor
            Self.setColor(fg, on ? BBColor.accent : BBColor.textDim)
        }
        shown = now
        CATransaction.commit()
    }
}
