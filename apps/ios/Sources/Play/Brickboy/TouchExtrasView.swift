// The ReplayNES buttons NESTERM's controller has no equivalent for - L2 (rewind), L (slow),
// MENU (Quick Menu), R (pause), R2 (fast-forward) and the optional turbo B / A - plus NESTERM's own
// 4/8-way switch (#ways-switch). A separate small view in the place and style of NESTERM's sub bar
// switches (.bb-mode-switch / .bb-turbo-switch: pill, 1 px --bb-line border, dim 11 px semibold
// text; "pressed" = accent text and border on a green tint), so the ported gamepad itself stays
// exactly Brickboy's. Buttons are held while the finger stays down (UIKit keeps the touch with the
// pill it began on); the ways switch toggles on release inside it, as a click does.
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
    private var layers: [(body: CALayer, label: CATextLayer)] = []
    private let impact = UIImpactFeedbackGenerator(style: .light)

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
        impact.prepare()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func index(at p: CGPoint) -> Int? { extras.firstIndex { $0.frame.contains(p) } }

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
        let scale = window?.screen.scale ?? traitCollection.displayScale
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for e in extras {
            let body = CALayer()
            body.frame = e.frame
            body.cornerRadius = e.frame.height / 2
            body.borderWidth = TouchLayout.switchBorder
            let label = BBDraw.label(TouchLayout.label(e.kind, ways: ways), size: TouchLayout.pillFont, weight: .semibold,
                                     tracking: TouchLayout.switchTracking, color: BBColor.textDim,
                                     centre: CGPoint(x: e.frame.width / 2, y: e.frame.height / 2), scale: scale)
            body.addSublayer(label)
            layer.addSublayer(body)
            layers.append((body, label))
        }
        CATransaction.commit()
        restyle()
    }

    private func restyle() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (i, e) in extras.enumerated() where layers.indices.contains(i) {
            let (body, label) = layers[i]
            // [aria-pressed="true"]: the ways switch in 4-way mode, a button while it is held.
            let on: Bool
            switch e.kind {
            case .ways:
                on = ways == 4
                label.string = NSAttributedString(string: TouchLayout.label(e.kind, ways: ways), attributes: [
                    .font: UIFont.systemFont(ofSize: TouchLayout.pillFont, weight: .semibold), .kern: TouchLayout.switchTracking,
                ])
            case .button:
                on = held.values.contains(i)
            }
            body.backgroundColor = on ? UIColor(red: 52 / 255, green: 211 / 255, blue: 153 / 255, alpha: 0.14).cgColor
                : UIColor(red: 20 / 255, green: 24 / 255, blue: 31 / 255, alpha: 0.82).cgColor
            body.borderColor = (on ? BBColor.accentPress : BBColor.line).cgColor
            BBDraw.setColor(label, on ? BBColor.accent : BBColor.textDim)
        }
        CATransaction.commit()
    }
}
