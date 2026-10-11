// The resume countdown on iPhone (rules: ResumeCountdownLogic.swift). Behind ResumeCountdownDriver
// so AppModel does not care who counts: today the iOS one below (a main-thread timer while the game
// stays paused, drawn by ResumeCountdownView with the practice countdown's CountdownOverlay); when the
// shared core gets a resume countdown, a driver over the emulation thread (drawn by MetalView like the
// practice one) takes its place.
// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI
import QuartzCore

protocol ResumeCountdownDriver: AnyObject {
    var isActive: Bool { get }
    /// Starts 3, 2, 1; `finish` runs on the main thread when it reaches zero (never after abort()).
    func begin(finish: @escaping () -> Void)
    /// Back to paused (nothing runs).
    func abort()
}

/// The iOS-local countdown: the game stays paused; the view reads `start` and draws the numeral.
final class LocalResumeCountdown: ObservableObject, ResumeCountdownDriver {
    /// CACurrentMediaTime() when it started; nil = not counting.
    @Published private(set) var start: Double?
    private var timer: Timer?
    private var finish: (() -> Void)?

    var isActive: Bool { start != nil }

    func begin(finish: @escaping () -> Void) {
        abort()
        let t0 = CACurrentMediaTime()
        start = t0
        self.finish = finish
        let t = Timer(timeInterval: ResumeCountdownClock.seconds, repeats: false) { [weak self] _ in self?.fire() }
        t.tolerance = 0
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func abort() {
        timer?.invalidate()
        timer = nil
        finish = nil
        if start != nil { start = nil }
    }

    private func fire() {
        let f = finish
        timer = nil
        finish = nil
        start = nil
        f?()
    }
}

/// 3, 2, 1 centred on the picture over the paused game. A tap on the picture or ✕ goes back to paused.
struct ResumeCountdownView: View {
    @ObservedObject var countdown: LocalResumeCountdown
    let picture: CGRect
    let onAbort: () -> Void

    var body: some View {
        if let start = countdown.start {
            let side = max(48, min(picture.width, picture.height) * 0.34)
            ZStack(alignment: .topTrailing) {
                Color.black.opacity(0.001)   // takes the taps on the picture
                    .contentShape(Rectangle())
                    .onTapGesture { onAbort() }
                TimelineView(.animation) { ctx in
                    numeral(start: start, now: ctx.date, side: side)
                        .frame(width: picture.width, height: picture.height)
                }
                .allowsHitTesting(false)
                Button(action: onAbort) {
                    Image(systemName: "xmark").font(.system(size: 14, weight: .bold))
                        .frame(width: 32, height: 32)
                        .background(.black.opacity(0.55), in: Circle())
                        .foregroundStyle(.white.opacity(0.85))
                        .touchTarget(width: 32, height: 32)
                }
                .padding(8)
                .accessibilityLabel(L("Cancel Countdown"))
                .accessibilityIdentifier("countdownCancel")
            }
            .frame(width: picture.width, height: picture.height)
            .offset(x: picture.minX, y: picture.minY)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("resumeCountdown")
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private func numeral(start: Double, now: Date, side: CGFloat) -> some View {
        // TimelineView's date is wall time; the countdown runs on the media clock.
        let t = CACurrentMediaTime()
        if case .counting(let n, let f) = ResumeCountdownClock(start: start).state(at: t),
           let img = Self.image(PracticeLoop.countdownVisual(count: n, fraction: f), side: side) {
            Image(decorative: img, scale: UIScreen.main.scale)
                .resizable()
                .frame(width: side, height: side)
                .accessibilityElement()
                .accessibilityLabel(String(n))
                .accessibilityIdentifier("countdownNumber")
        }
    }

    /// The practice countdown's picture (CountdownOverlay, premultiplied BGRA) as a CGImage.
    private static func image(_ v: rnf_countdown_visual, side: CGFloat) -> CGImage? {
        guard v.number > 0, v.alpha > 0.01 else { return nil }
        let px = max(16, Int((side * UIScreen.main.scale).rounded()))
        guard let bytes = CountdownOverlay.render(v, side: px) else { return nil }
        let data = Data(bytes) as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }
        return CGImage(width: px, height: px, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: px * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}
