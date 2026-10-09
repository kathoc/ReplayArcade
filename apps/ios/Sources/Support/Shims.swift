// Stand-ins for the few macOS-only symbols that the shared app-layer files (referenced in place from
// apps/macos, see project.yml) mention, so those files compile unchanged on iOS.
// SPDX-License-Identifier: GPL-2.0-or-later
import AudioToolbox
import CoreGraphics
import Foundation
import UIKit

/// Runtime.swift (AudioOutput) asks the macOS audio HAL for a 256-frame IO buffer through this
/// property. On iOS the IO buffer belongs to the audio session (AudioSessionSetup); setting the
/// property on RemoteIO just fails, which AudioOutput ignores.
let kAudioDevicePropertyBufferFrameSize: AudioUnitPropertyID = 0x6673_697A  // 'fsiz'

/// QuickMenuController beeps on a disabled item; on iPhone that is a short warning haptic.
enum NSSound {
    static func beep() {
        DispatchQueue.main.async { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    }
}

/// GameRenderer (MetalView.swift) can draw the macOS "menu pill" into the game picture. iPhone
/// has an on-screen Menu button instead, so the pill is never visible here.
final class MenuPillOverlay {
    static let shared = MenuPillOverlay()
    struct State {
        var image: CGImage?
        var generation = 0
        var pixelSize = CGSize.zero
        var scale: CGFloat = 2
        var visible = false
        var activity = 0.0
    }
    var state: State { State() }
}

#if targetEnvironment(simulator)
import Metal

/// The simulator SDK has no MTLDrawable.addPresentedHandler / presentedTime (the device SDK has).
/// GameRenderer (MetalView.swift) uses them for its latency / pacing statistics only, so in the
/// simulator the handler runs about a refresh later and reports "now": functional, not a measurement.
extension MTLDrawable {
    func addPresentedHandler(_ block: @escaping (MTLDrawable) -> Void) {
        let d = self
        DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + 1.0 / 60) { block(d) }
    }

    var presentedTime: CFTimeInterval { CACurrentMediaTime() }
}
#endif

#if targetEnvironment(simulator)
import AVFoundation

/// Simulator only: AudioOutput (Runtime.swift, shared) gets this silent stand-in instead of
/// AVFoundation's AVAudioEngine (a module's own type shadows the imported one). On the Mac this
/// prototype was built on, the simulator's audio service deadlocks any AVAudioEngine output
/// ("AURemoteIO::Cleanup: RPC timeout. Apparently deadlocked", also for a five-line engine in a
/// unit test), which aborts the app. Simulator builds are therefore silent; the emulation, the
/// audio ring and its statistics still run. Device builds use the real engine (no shim there).
final class AVAudioEngine {
    final class Mixer { var outputVolume: Float = 1 }
    final class Output {
        var audioUnit: AudioUnit? { nil }
        var presentationLatency: TimeInterval { 0 }
    }
    let mainMixerNode = Mixer()
    let outputNode = Output()
    func attach(_ node: AVAudioNode) {}
    func connect(_ node: AVAudioNode, to mixer: Mixer, format: AVAudioFormat?) {}
    func prepare() {}
    func start() throws {}
    func stop() {}
}
#endif
