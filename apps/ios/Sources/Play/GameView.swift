// The play surface: the game's CAMetalLayer (driven by the emulation thread's CAMetalDisplayLink,
// shared GameRenderer / EmulationController: one emulated frame per NES frame, presented on the
// nearest refresh; at 120 Hz ProMotion every 2nd refresh starts a frame, the other repeats it)
// and the touch controls, laid out by TouchLayout. UIKit, not SwiftUI, so touches reach the
// controls directly (UITouch, no gesture recognisers) and nothing SwiftUI does delays a frame.
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

/// Game view + touch controls in one UIKit container that lays both out from its own safe area.
final class PlaySurfaceView: UIView {
    let game: GameLayerView
    let controls = TouchControlsView()
    var options = TouchLayout.Options() { didSet { if options != oldValue { setNeedsLayout() } } }
    var controlsVisible = true { didSet { controls.isHidden = !controlsVisible; if !controlsVisible { controls.releaseAll() } } }
    /// Main thread, after each layout change: where things are (for the SwiftUI overlays).
    var onLayout: ((TouchLayout) -> Void)?
    private var lastLayout: TouchLayout?

    init(emu: EmulationController) {
        game = GameLayerView(emu: emu)
        super.init(frame: .zero)
        backgroundColor = .black
        addSubview(game)
        addSubview(controls)
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
        controls.layoutModel = l
        if l != lastLayout {
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

    func makeUIView(context: Context) -> PlaySurfaceView {
        let v = PlaySurfaceView(emu: model.emu)
        v.controls.onChange = { [weak model] pressed, released in model?.touchButtons(pressed: pressed, released: released) }
        v.onLayout = { [weak model] l in if model?.playLayout != l { model?.playLayout = l } }
        update(v)
        return v
    }

    func updateUIView(_ v: PlaySurfaceView, context: Context) { update(v) }

    private func update(_ v: PlaySurfaceView) {
        v.game.setOptions(displayOptions)
        v.options = touchOptions
        v.controlsVisible = controlsVisible
        v.controls.controlOpacity = CGFloat(opacity)
        v.controls.haptics = haptics
    }

    static func dismantleUIView(_ v: PlaySurfaceView, coordinator: ()) {
        v.game.stopRendering()
        v.controls.releaseAll()
    }
}
