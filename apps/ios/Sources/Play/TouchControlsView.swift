// On-screen controls: draws TouchLayout's controls with Core Animation layers and turns raw
// UITouch events into held buttons (TouchRouter). Every change is reported at once on the main
// thread (AppModel.touchButtons -> rn_input_set_pressed, which the emulation thread samples just
// in time for the next frame): no gesture recognisers, no SwiftUI in the path. A light haptic on
// each press. Touches that land on no control fall through to the views below.
// SPDX-License-Identifier: GPL-2.0-or-later
import UIKit

final class TouchControlsView: UIView {
    /// Pressed, released (main thread).
    var onChange: (([TouchButton], [TouchButton]) -> Void)?
    var haptics = true
    var controlOpacity: CGFloat = 0.55 { didSet { if controlOpacity != oldValue { restyle() } } }
    var layoutModel: TouchLayout? {
        didSet {
            guard layoutModel != oldValue else { return }
            releaseAll()
            rebuild()
        }
    }

    private var router = TouchRouter()
    private var held: Set<TouchButton> = []
    private var shapes: [(button: TouchButton, layer: CAShapeLayer)] = []
    private let impact = UIImpactFeedbackGenerator(style: .light)

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        isExclusiveTouch = false
        backgroundColor = .clear
        impact.prepare()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: touches

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard !isHidden, let l = layoutModel else { return false }
        return l.control(at: point) != nil
    }

    private static func key(_ t: UITouch) -> Int { ObjectIdentifier(t).hashValue }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let l = layoutModel else { return }
        for t in touches { router.began(Self.key(t), at: t.location(in: self), layout: l) }
        apply()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let l = layoutModel else { return }
        for t in touches { router.moved(Self.key(t), to: t.location(in: self), layout: l) }
        apply()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches { router.ended(Self.key(t)) }
        apply()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches { router.ended(Self.key(t)) }
        apply()
    }

    func releaseAll() {
        router.reset()
        apply()
    }

    private func apply() {
        let now = router.held
        guard now != held else { return }
        let d = TouchRouter.diff(from: held, to: now)
        held = now
        onChange?(d.pressed, d.released)
        if haptics && !d.pressed.isEmpty {
            impact.impactOccurred(intensity: d.pressed.allSatisfy(\.isDirection) ? 0.45 : 0.8)
            impact.prepare()
        }
        restyle()
    }

    // MARK: drawing

    private func rebuild() {
        layer.sublayers?.forEach { $0.removeFromSuperlayer() }
        shapes.removeAll()
        guard let l = layoutModel else { return }
        let scale = window?.screen.scale ?? traitCollection.displayScale
        for c in l.controls {
            switch c.kind {
            case .dpad:
                // Four arms around a centre square; each arm lights for its direction.
                let r = c.frame
                let w = r.width / 3
                let arms: [(TouchButton, CGRect)] = [
                    (.up, CGRect(x: r.minX + w, y: r.minY, width: w, height: w * 1.05)),
                    (.down, CGRect(x: r.minX + w, y: r.maxY - w * 1.05, width: w, height: w * 1.05)),
                    (.left, CGRect(x: r.minX, y: r.minY + w, width: w * 1.05, height: w)),
                    (.right, CGRect(x: r.maxX - w * 1.05, y: r.minY + w, width: w * 1.05, height: w)),
                ]
                let hub = CAShapeLayer()
                hub.path = UIBezierPath(rect: CGRect(x: r.minX + w - 0.5, y: r.minY + w - 0.5, width: w + 1, height: w + 1)).cgPath
                hub.fillColor = UIColor(white: 1, alpha: 0.10).cgColor
                layer.addSublayer(hub)
                for (b, rect) in arms {
                    let s = CAShapeLayer()
                    s.path = UIBezierPath(roundedRect: rect, cornerRadius: w * 0.18).cgPath
                    layer.addSublayer(s)
                    shapes.append((b, s))
                    addLabel(b.label, in: rect, size: w * 0.32, scale: scale)
                }
            case .face:
                let s = CAShapeLayer()
                s.path = UIBezierPath(ovalIn: c.frame).cgPath
                layer.addSublayer(s)
                shapes.append((c.buttons[0], s))
                addLabel(c.buttons[0].label, in: c.frame, size: c.frame.height * (c.frame.height > 50 ? 0.36 : 0.3), scale: scale)
            case .pill, .shoulder:
                let s = CAShapeLayer()
                s.path = UIBezierPath(roundedRect: c.frame, cornerRadius: c.kind == .pill ? c.frame.height / 2 : 9).cgPath
                layer.addSublayer(s)
                shapes.append((c.buttons[0], s))
                addLabel(c.buttons[0].label, in: c.frame, size: min(15, c.frame.height * 0.42), scale: scale)
            }
        }
        restyle()
    }

    private func addLabel(_ text: String, in rect: CGRect, size: CGFloat, scale: CGFloat) {
        let t = CATextLayer()
        t.string = text
        t.font = UIFont.systemFont(ofSize: size, weight: .semibold)
        t.fontSize = size
        t.alignmentMode = .center
        t.contentsScale = scale
        t.foregroundColor = UIColor(white: 1, alpha: 0.85).cgColor
        let h = size * 1.25
        t.frame = CGRect(x: rect.minX, y: rect.midY - h / 2, width: rect.width, height: h)
        t.name = "label"
        layer.addSublayer(t)
    }

    private func restyle() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = Float(controlOpacity)
        for (b, s) in shapes {
            let on = held.contains(b)
            s.fillColor = UIColor(white: 1, alpha: on ? 0.55 : 0.16).cgColor
            s.strokeColor = UIColor(white: 1, alpha: on ? 0.9 : 0.45).cgColor
            s.lineWidth = 1.5
        }
        CATransaction.commit()
    }
}
