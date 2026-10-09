// AVAudioSession for game audio: playback category (the mute switch does not silence the game,
// like other game apps), 48 kHz, a small IO buffer for low latency (~5 ms; the shared AudioOutput
// then keeps ~21 ms in its ring with dynamic rate control, docs/FRAME_PACING.md). Interruptions
// (calls, Siri) and route changes restart the audio engine.
// SPDX-License-Identifier: GPL-2.0-or-later
import AVFoundation
import Foundation

final class AudioSessionSetup {
    /// Main thread: the audio engine must be rebuilt (interruption ended, media services reset).
    var onRestart: (() -> Void)?
    private var observers: [NSObjectProtocol] = []
    /// Requested IO buffer (seconds): 256 frames at 48 kHz.
    static let ioBufferDuration = 256.0 / 48_000

    func activate() {
        let s = AVAudioSession.sharedInstance()
        let level = UserDefaults.standard.object(forKey: "audioSessionLevel") == nil ? 3 : UserDefaults.standard.integer(forKey: "audioSessionLevel")
        do {
            if level >= 1 { try s.setCategory(.playback, mode: .default, options: []) }
            if level >= 3 { try s.setPreferredSampleRate(48_000) }
            if level >= 3 { try s.setPreferredIOBufferDuration(Self.ioBufferDuration) }
            if level >= 2 { try s.setActive(true) }
        } catch {
            NSLog("ReplayNES: audio session: \(error)")
        }
        guard observers.isEmpty else { return }
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: AVAudioSession.interruptionNotification, object: s, queue: .main) { [weak self] n in
            guard let raw = n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .ended else { return }
            try? AVAudioSession.sharedInstance().setActive(true)
            self?.onRestart?()
        })
        observers.append(nc.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: s, queue: .main) { [weak self] _ in
            self?.activate()
            self?.onRestart?()
        })
    }

    /// Back in the foreground: the session may have been deactivated by the system meanwhile.
    func reactivate() {
        do { try AVAudioSession.sharedInstance().setActive(true) } catch { NSLog("ReplayNES: audio session: \(error)") }
    }

    /// For the latency overlay / README measurements.
    var describe: String {
        let s = AVAudioSession.sharedInstance()
        return String(format: "%.0f Hz, IO %.1f ms, out %.1f ms", s.sampleRate, s.ioBufferDuration * 1000, s.outputLatency * 1000)
    }
}
