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
    /// The scene is in the foreground (true by default): DisplayTarget.visible, so the display
    /// watchdog (rnf_display_watchdog) does not restart the link while nothing can be presented.
    private var sceneVisible = true
    private var sceneObservers: [NSObjectProtocol] = []

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
        let nc = NotificationCenter.default
        sceneObservers = [
            nc.addObserver(forName: UIScene.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] n in
                self?.sceneChanged(n.object as? UIScene, visible: false)
            },
            nc.addObserver(forName: UIScene.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] n in
                self?.sceneChanged(n.object as? UIScene, visible: true)
            },
        ]
    }

    deinit { sceneObservers.forEach(NotificationCenter.default.removeObserver) }

    private func sceneChanged(_ scene: UIScene?, visible: Bool) {
        // Only this view's scene (any scene while it has no window yet).
        if let scene, let mine = window?.windowScene, scene !== mine { return }
        sceneVisible = visible
        displayTarget?.visible = visible
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateDrawableSize()
        if window != nil { startRendering() } else { stopRendering() }
        if let state = window?.windowScene?.activationState {
            sceneVisible = state != .background && state != .unattached
            displayTarget?.visible = sceneVisible
        }
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
        t.visible = sceneVisible
        displayTarget = t
        emu.setDisplayTarget(t)
        monitor.start(emu: emu, renderer: renderer, visible: { [weak self] in self?.sceneVisible ?? false })
    }

    func stopRendering() {
        if let t = displayTarget { emu?.clearDisplayTarget(t) }
        displayTarget = nil
        monitor.stop()
    }

    private let monitor = DisplayMonitor()
    /// -displayProbe: the monitor's counters (main thread, 10 Hz).
    var onDisplayProbe: ((String) -> Void)? { get { monitor.onProbe } set { monitor.onProbe = newValue } }
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
        if DisplayMonitor.probe {
            // DisplayRecoveryUITests: the display monitor's counters as an accessibility value.
            let p = UILabel(frame: CGRect(x: 0, y: 0, width: 4, height: 4))
            p.isAccessibilityElement = true
            p.accessibilityIdentifier = "displayProbe"
            p.alpha = 0.02
            p.isUserInteractionEnabled = false
            addSubview(p)
            game.onDisplayProbe = { [weak p] v in p?.accessibilityValue = v; p?.accessibilityLabel = v }
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

/// Main-thread check of the display path, independent of the emulation thread (whose display
/// watchdog cannot act while that thread itself is stuck): logs (DisplayLog) an emulation thread
/// that has not moved for a second and pictures that stop being confirmed on screen while the game
/// plays, and when either ends. `-displayStats <s>` also logs the display numbers every s seconds;
/// `-displayProbe YES` publishes the counters on an accessibility element (DisplayRecoveryUITests).
final class DisplayMonitor {
    private var timer: Timer?
    private weak var emu: EmulationController?
    private weak var renderer: GameRenderer?
    private var visible: () -> Bool = { false }
    private var lastSeq: UInt64 = 0, seqAt = 0.0, playingSince = 0.0
    private var lastConfirmed: UInt64 = 0, confirmedAt = 0.0
    private var threadStuckSince: Double?
    private var pictureStuckSince: Double?
    private var lastStats = 0.0
    private var statsConfirmed: UInt64 = 0, statsRepeats: UInt64 = 0
    private(set) var stalls = 0
    /// Longest time a published picture waited to be confirmed while playing (seconds).
    private(set) var longestWait = 0.0
    var onProbe: ((String) -> Void)?
    static let threshold = 1.0
    static let statsEvery = UserDefaults.standard.double(forKey: "displayStats")
    static let probe = UserDefaults.standard.bool(forKey: "displayProbe")

    func start(emu: EmulationController, renderer: GameRenderer, visible: @escaping () -> Bool) {
        stop()
        self.emu = emu
        self.renderer = renderer
        self.visible = visible
        let now = CACurrentMediaTime()
        seqAt = now; confirmedAt = now; playingSince = now
        let t = Timer(timeInterval: Self.probe ? 0.1 : 0.5, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() { timer?.invalidate(); timer = nil }

    private func tick() {
        guard let emu, let renderer else { return }
        let now = CACurrentMediaTime()
        let seq = emu.frames.sequence
        if seq != lastSeq {
            if now - seqAt > 0.3 { playingSince = now }   // play (re)started
            lastSeq = seq; seqAt = now
        }
        let h = renderer.health.snapshot
        if h.confirmedSequence != lastConfirmed { lastConfirmed = h.confirmedSequence; confirmedAt = now }
        let shown = visible()
        let (at, phase) = emu.probe.snapshot
        if shown && now - at > Self.threshold {
            if threadStuckSince == nil {
                threadStuckSince = at
                DisplayLog.write(String(format: "display monitor: emulation thread has not moved for %.1f s (in \"%@\"); GPU errors %d, last confirmed seq %llu of %llu",
                                        now - at, phase, h.gpuErrors, h.confirmedSequence, seq))
            }
        } else if let since = threadStuckSince {
            threadStuckSince = nil
            DisplayLog.write(String(format: "display monitor: emulation thread running again after %.1f s", now - since))
        }
        let playing = now - seqAt < 0.3
        // Waiting since the later of the last confirmation and the start of play.
        let waited = playing && shown ? now - max(confirmedAt, playingSince) : 0
        longestWait = max(longestWait, waited)
        if waited > Self.threshold {
            if pictureStuckSince == nil {
                pictureStuckSince = now - waited
                stalls += 1
                DisplayLog.write(String(format: "display monitor: no new picture confirmed on screen for %.1f s while playing (seq %llu, confirmed %llu, frame %llu; GPU errors %d, emulation thread in \"%@\")",
                                        waited, seq, h.confirmedSequence, h.confirmedFrame, h.gpuErrors, phase))
            }
        } else if let since = pictureStuckSince {
            pictureStuckSince = nil
            DisplayLog.write(String(format: "display monitor: pictures on screen again after %.1f s", now - since))
        }
        let st = (Self.statsEvery > 0 || Self.probe) ? emu.latency.snapshot(audio: nil) : nil
        if let st, Self.statsEvery > 0, playing, now - lastStats >= Self.statsEvery {
            let dt = max(0.001, now - lastStats)
            let onScreen = Double(h.confirmedSequence &- statsConfirmed) / dt
            let repeats = Double(st.repeatPresents &- statsRepeats) / dt
            lastStats = now; statsConfirmed = h.confirmedSequence; statsRepeats = st.repeatPresents
            // shown: new pictures on screen (own present or the repeat that showed a dropped one);
            // own: shown by their own present; confirmed: pictures the display watchdog saw on screen.
            DisplayLog.write(String(format: "display stats: %@, emu %.1f fps, shown %.1f fps (own %.1f), confirmed %.1f/s, repeats %.1f/s, dropped %llu, GPU %.1f ms (max %.1f), %@, watchdog %llu, GPU errors %d, layer %@",
                                    st.pacing, st.emulatedFPS, st.onScreenFPS, st.presentedFPS, onScreen, repeats, st.droppedFrames, st.displayGPUMs, st.displayGPUMaxMs,
                                    st.crtInfo.isEmpty ? "plain" : "CRT " + st.crtInfo, st.watchdogActions, st.gpuErrors, st.layerPixels))
        }
        if let st, Self.probe, let onProbe {
            onProbe(String(format: "seq=%llu confirmed=%llu confirmedAgo=%.2f playing=%d stalls=%d longestWait=%.2f watchdog=%llu gpuErrors=%d crt=%@",
                           seq, h.confirmedSequence, now - confirmedAt, playing ? 1 : 0, stalls, longestWait, st.watchdogActions, h.gpuErrors,
                           st.crtInfo.isEmpty ? "off" : "on"))
        }
    }
}
