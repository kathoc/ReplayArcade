// The display path never stays frozen (docs/FRAME_PACING.md "Display watchdog"): the app runs the
// test cartridge with the CRT model on and one injected failure (-displayFault, -crtInjectGPUError,
// or a background / foreground trip, rotations), and the pictures confirmed on screen must keep
// coming: DisplayMonitor publishes its counters on the "displayProbe" accessibility element
// (-displayProbe YES), sampled here while the game plays.
// Reported (iPhone 17 Pro, CRT on): the picture stopped updating while the game played on.
// SPDX-License-Identifier: GPL-2.0-or-later
import XCTest

final class DisplayRecoveryUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-autoplayTestROM", "YES", "-setResumeCountdown", "NO", "-crtEnabled", "YES", "-displayProbe", "YES",
                               "-touchHideWithPad", "NO", "-debugUnlockAll", "YES", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    // MARK: helpers

    private func probe() -> [String: Double] {
        let e = app.descendants(matching: .any)["displayProbe"]
        guard e.exists else { return [:] }
        var out: [String: Double] = [:]
        for kv in e.label.split(separator: " ") {
            let p = kv.split(separator: "=", maxSplits: 1)
            guard p.count == 2 else { continue }
            out[String(p[0])] = p[1] == "on" ? 1 : p[1] == "off" ? 0 : Double(p[1])
        }
        return out
    }

    private struct Observation {
        var maxGap = 0.0          // longest time without a newly confirmed picture while playing
        var confirmedChanges = 0
        var crtSeenOn = false
        var last: [String: Double] = [:]
    }

    /// Samples the probe for `seconds` while playing.
    private func observe(_ seconds: Double) -> Observation {
        var o = Observation()
        var lastConfirmed = -1.0
        var lastChange = Date()
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            let p = probe()
            o.last = p
            let now = Date()
            if let c = p["confirmed"], c != lastConfirmed {
                if lastConfirmed >= 0 { o.confirmedChanges += 1 }
                lastConfirmed = c
                lastChange = now
            } else if p["playing"] == 1 {
                o.maxGap = max(o.maxGap, now.timeIntervalSince(lastChange))
            } else {
                lastChange = now   // paused: nothing is expected
            }
            if p["crt"] == 1 { o.crtSeenOn = true }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return o
    }

    private func start(_ extra: [String] = []) {
        app.launchArguments += extra
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["displayProbe"].waitForExistence(timeout: 20), "playing with the display probe")
        let end = Date().addingTimeInterval(15)
        while Date() < end && probe()["playing"] != 1 { Thread.sleep(forTimeInterval: 0.2) }
        XCTAssertEqual(probe()["playing"], 1, "the game plays")
        Thread.sleep(forTimeInterval: 2)   // the CRT tube plan and the display link settle
    }

    /// Runs one failure for `seconds`: no freeze longer than `maxGap` seconds, and the watchdog
    /// acted when the failure needs it.
    private func check(_ name: String, _ extra: [String], seconds: Double = 14, maxGap: Double, watchdog: Bool) {
        start(extra)
        let o = observe(seconds)
        XCTContext.runActivity(named: "\(name): \(o.last)") { _ in }
        XCTAssertLessThan(o.maxGap, maxGap, "\(name): the picture froze for \(o.maxGap) s")
        XCTAssertGreaterThan(o.confirmedChanges, Int(seconds * 2), "\(name): pictures kept coming")
        if watchdog { XCTAssertGreaterThan(o.last["watchdog"] ?? 0, 0, "\(name): the watchdog acted") }
    }

    // MARK: tests

    func testHealthyCRTNeedsNoRecovery() {
        start()
        let o = observe(8)
        XCTAssertLessThan(o.maxGap, 1)
        XCTAssertTrue(o.crtSeenOn)
        XCTAssertEqual(o.last["watchdog"], 0, "no recovery without a failure")
    }

    /// CRT builds silently stop (a stale tube output, no GPU error): RECOVER, RESTART, then the
    /// plain picture (FALLBACK), the CRT model retried after the hold.
    func testStaleCRTOutputFallsBackToThePlainPicture() {
        check("crtStale", ["-displayFault", "crtStale"], maxGap: 2.5, watchdog: true)
    }

    /// Drawables that never reach the screen although their command buffers complete.
    func testPicturesThatNeverReachTheScreen() {
        check("noPresent", ["-displayFault", "noPresent"], maxGap: 2.5, watchdog: true)
    }

    /// Every CRT build fails on the GPU (error / timeout path).
    func testGPUErrors() {
        check("crtInjectGPUError", ["-crtInjectGPUError", "1"], maxGap: 2.5, watchdog: true)
    }

    /// A GPU queue that hangs for 3 s: the emulation thread never blocks, pictures come back.
    func testHungGPUQueue() {
        check("gpuHang", ["-displayFault", "gpuHang"], seconds: 16, maxGap: 5, watchdog: true)
    }

    /// The display link stops calling back for a while (drawable starvation).
    func testLostDisplayLink() {
        check("linkStall", ["-displayFault", "linkStall"], seconds: 16, maxGap: 1.5, watchdog: true)
    }

    /// The display link recreated every 2 s: each new link must start (it often never called back
    /// when created while the emulation thread was on the host clock).
    func testRecreatedDisplayLinks() {
        check("linkRestart", ["-displayFault", "linkRestart"], maxGap: 1.5, watchdog: false)
    }

    /// Tube sizes that keep changing (adaptive scale, thermal steps): the CRT picture still shows.
    func testTubeSizeChurn() {
        start(["-displayFault", "adaptiveFlip"])
        let o = observe(10)
        XCTAssertLessThan(o.maxGap, 1.5)
        XCTAssertTrue(o.crtSeenOn, "the CRT model is shown despite the churn")
    }

    /// Background and back: the game is paused by the trip; resumed, pictures come at once.
    func testBackgroundAndForeground() {
        start()
        for _ in 0..<2 {
            XCUIDevice.shared.press(.home)
            Thread.sleep(forTimeInterval: 2)
            app.activate()
            let resume = app.buttons["seekResume"]
            XCTAssertTrue(resume.waitForExistence(timeout: 10), "paused by the trip")
            resume.tap()
            Thread.sleep(forTimeInterval: 1)
            let o = observe(5)
            XCTAssertLessThan(o.maxGap, 1.5)
            XCTAssertGreaterThan(o.confirmedChanges, 8)
        }
    }

    /// Size changes: rotations while playing.
    func testRotationsWhilePlaying() {
        start()
        for o in [UIDeviceOrientation.landscapeLeft, .portrait, .landscapeRight, .portrait] {
            XCUIDevice.shared.orientation = o
            let obs = observe(3)
            XCTAssertLessThan(obs.maxGap, 1.5, "\(o.rawValue)")
            XCTAssertGreaterThan(obs.confirmedChanges, 5)
        }
    }
}
