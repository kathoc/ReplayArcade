// The play surface: the game's CAMetalLayer (driven by the emulation thread's CAMetalDisplayLink,
// shared GameRenderer / EmulationController: one emulated frame per NES frame, presented on the
// nearest refresh; at 120 Hz ProMotion every 2nd refresh starts a frame, the other repeats it)
// and the touch controls (NESTERM's Brickboy gamepad, ported: Play/Brickboy), laid out by TouchLayout.
// UIKit, not SwiftUI, so touches reach the controls directly (UITouch, no gesture recognisers) and
// nothing SwiftUI does delays a frame.
// SPDX-License-Identifier: GPL-2.0-or-later
import Metal
import QuartzCore
import SwiftUI
import UIKit

/// iOS counterpart of the macOS GameLayerView (MetalView.swift): a view whose CAMetalLayer the
/// emulation thread presents to.
final class GameLayerView: UIView {
    override class var layerClass: AnyClass { CAMetalLayer.self }
    private var metalLayer: CAMetalLayer { layer as! CAMetalLayer }
    let renderer: GameRenderer?
    private weak var emu: EmulationController?
    private var displayTarget: DisplayTarget?

    init(emu: EmulationController) {
        self.emu = emu
        renderer = GameRenderer(frames: emu.frames, latency: emu.latency)
        super.init(frame: CGRect(x: 0, y: 0, width: 256, height: 240))
        metalLayer.device = renderer?.device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = true
        // Opaque and untransformed: the layer can go to the display without extra composition.
        metalLayer.isOpaque = true
        metalLayer.backgroundColor = UIColor.black.cgColor
        metalLayer.maximumDrawableCount = 3
        metalLayer.presentsWithTransaction = false
        isOpaque = true
        backgroundColor = .black
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateDrawableSize()
        if window != nil { startRendering() } else { stopRendering() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateDrawableSize()
    }

    private func updateDrawableSize() {
        let scale = window?.screen.nativeScale ?? traitCollection.displayScale
        let size = CGSize(width: max(1, (bounds.width * scale).rounded()), height: max(1, (bounds.height * scale).rounded()))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        metalLayer.contentsScale = scale
        if metalLayer.drawableSize != size { metalLayer.drawableSize = size }
        CATransaction.commit()
    }

    func setOptions(_ o: DisplayOptions) {
        guard let renderer, renderer.options != o else { return }
        renderer.options = o
    }

    private func startRendering() {
        guard let renderer, let emu, displayTarget == nil else { return }
        let screen = window?.screen ?? UIScreen.main
        let maxFPS = screen.maximumFramesPerSecond
        let t = DisplayTarget(layer: metalLayer, renderer: renderer, maxFPS: maxFPS, variableRefresh: maxFPS > 60)
        displayTarget = t
        emu.setDisplayTarget(t)
    }

    func stopRendering() {
        if let t = displayTarget { emu?.clearDisplayTarget(t) }
        displayTarget = nil
    }
}

/// Game view + touch controls in one UIKit container that lays both out from its own safe area:
/// the ported NESTERM gamepad (TouchControlsView) and the ReplayNES extras row (TouchExtrasView,
/// on top: its pills win the hit test like NESTERM's z-index 3 switches).
final class PlaySurfaceView: UIView {
    let game: GameLayerView
    let controls = TouchControlsView()
    let extras = TouchExtrasView()
    var options = TouchLayout.Options() { didSet { if options != oldValue { setNeedsLayout() } } }
    var controlsVisible = true {
        didSet {
            controls.isHidden = !controlsVisible
            extras.isHidden = !controlsVisible
            if !controlsVisible { controls.releaseAll(); extras.releaseAll() }
        }
    }
    /// Main thread, after each layout change: where things are (for the SwiftUI overlays).
    var onLayout: ((TouchLayout) -> Void)?
    private var lastLayout: TouchLayout?
    /// TestHooks -logTouch: an accessibility element for the UI tests (ReplayNESUITests): its label
    /// is where the controls are, its value every press / release edge so far.
    private var probe: UIView?
    private var probeLog: [String] = []

    init(emu: EmulationController) {
        game = GameLayerView(emu: emu)
        super.init(frame: .zero)
        // .bb-root { background: var(--bb-bg) }
        backgroundColor = BBColor.bg
        addSubview(game)
        addSubview(controls)
        addSubview(extras)
        if UserDefaults.standard.bool(forKey: "logTouch") {
            let p = UIView(frame: CGRect(x: 0, y: 0, width: 2, height: 2))
            p.isAccessibilityElement = true
            p.accessibilityIdentifier = "touchProbe"
            p.alpha = 0.02
            p.isUserInteractionEnabled = false
            addSubview(p)
            probe = p
        }
    }

    /// The UI tests' record of the touch edges (see `probe`).
    func recordTouch(_ pressed: [TouchButton], _ released: [TouchButton]) {
        guard let probe else { return }
        probeLog += pressed.map { $0.rawValue + "+" } + released.map { $0.rawValue + "-" }
        probe.accessibilityValue = probeLog.joined(separator: " ")
    }

    private func updateProbe(_ l: TouchLayout) {
        guard let probe else { return }
        let g = l.pad
        var pts: [String: [CGFloat]] = [
            "dpad": [g.dpad.midX, g.dpad.midY, g.dpad.width], "a": [g.a.x, g.a.y], "b": [g.b.x, g.b.y],
            "select": [g.select.midX, g.select.midY], "start": [g.start.midX, g.start.midY], "size": [l.size.width, l.size.height],
            "game": [l.gameArea.minX, l.gameArea.minY, l.gameArea.width, l.gameArea.height],
        ]
        for (k, b) in [("aa", TouchButton.turboA), ("bb", .turboB), ("l2", .l2), ("r2", .r2), ("stepBack", .stepBack), ("stepForward", .stepForward),
                      ("menu", .menu), ("l", .l), ("r", .r)] {
            if let e = l.extra(b) { pts[k] = [e.frame.midX, e.frame.midY] }
        }
        if let d = try? JSONSerialization.data(withJSONObject: pts.mapValues { $0.map(Double.init) }), let s = String(data: d, encoding: .utf8) {
            probe.accessibilityLabel = s
        }
        bringSubviewToFront(probe)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let s = safeAreaInsets
        let l = TouchLayout.make(size: bounds.size, safe: TouchInsets(top: s.top, left: s.left, bottom: s.bottom, right: s.right),
                                 options: options)
        game.frame = l.gameArea
        controls.frame = bounds
        extras.frame = bounds
        if let old = lastLayout, old.landscape != l.landscape { extras.releaseAll() }
        controls.layoutModel = l
        extras.ways = options.ways
        extras.extras = l.extras
        if l != lastLayout {
            updateProbe(l)
            if UserDefaults.standard.bool(forKey: "logLayout") {
                NSLog("ReplayNES: layout bounds=\(bounds) inWindow=\(convert(bounds, to: nil)) window=\(window?.bounds ?? .zero) safe=\(s)")
            }
            lastLayout = l
            let cb = onLayout
            DispatchQueue.main.async { cb?(l) }
        }
    }
}

struct PlaySurface: UIViewRepresentable {
    let model: AppModel
    var displayOptions: DisplayOptions
    var touchOptions: TouchLayout.Options
    var controlsVisible: Bool
    var opacity: Double
    var haptics: Bool
    /// controller.mjs applyGain (追従 ↔ / ↕): TouchGamepad.setHomeGain.
    var followX: Double
    var followY: Double

    func makeUIView(context: Context) -> PlaySurfaceView {
        let v = PlaySurfaceView(emu: model.emu)
        v.controls.onChange = { [weak model, weak v] pressed, released in
            v?.recordTouch(pressed, released)
            model?.touchButtons(pressed: pressed, released: released)
        }
        v.extras.onChange = { [weak model, weak v] pressed, released in
            v?.recordTouch(pressed, released)
            model?.touchButtons(pressed: pressed, released: released)
        }
        v.extras.onToggleWays = { [weak model] in model?.toggleTouchWays() }
        v.onLayout = { [weak model] l in if model?.playLayout != l { model?.playLayout = l } }
        update(v)
        return v
    }

    func updateUIView(_ v: PlaySurfaceView, context: Context) { update(v) }

    private func update(_ v: PlaySurfaceView) {
        v.game.setOptions(displayOptions)
        v.options = touchOptions
        v.controls.setWays(touchOptions.ways)
        v.controls.setHomeGain(x: CGFloat(followX), y: CGFloat(followY))
        v.controlsVisible = controlsVisible
        v.controls.controlOpacity = CGFloat(opacity)
        v.extras.controlOpacity = CGFloat(opacity)
        v.controls.haptics = haptics
        v.extras.haptics = haptics
    }

    static func dismantleUIView(_ v: PlaySurfaceView, coordinator: ()) {
        v.game.stopRendering()
        v.controls.releaseAll()
        v.extras.releaseAll()
    }
}
