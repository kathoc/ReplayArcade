// Feature gating (Sources/Entitlements): the free / paid policy documented in README.md.
// SPDX-License-Identifier: GPL-2.0-or-later
import XCTest

final class FeatureGateTests: XCTestCase {
    func testEveryGatedActionNeedsItsFeature() {
        for a in GatedAction.allCases {
            var e = EntitlementState.free
            XCTAssertFalse(FeatureGate.allows(a, e), "\(a) must be locked in free mode")
            e.purchased = [a.feature]
            XCTAssertTrue(FeatureGate.allows(a, e), "\(a) must open with \(a.feature)")
            e.purchased = Set(PaidFeature.allCases).subtracting([a.feature])
            XCTAssertFalse(FeatureGate.allows(a, e), "\(a) must not open with the other features")
        }
    }

    func testDebugSwitchUnlocksEverything() {
        let e = EntitlementState(purchased: [], debugUnlockAll: true)
        for f in PaidFeature.allCases { XCTAssertTrue(e.isUnlocked(f)) }
        for a in GatedAction.allCases { XCTAssertTrue(FeatureGate.allows(a, e)) }
    }

    func testFreeLibraryPlayUsesTheTemporarySlot() {
        XCTAssertEqual(FeatureGate.sessionTarget(forLibraryPlay: .free), .temporary)
        XCTAssertEqual(FeatureGate.sessionTarget(forLibraryPlay: EntitlementState(purchased: [.recording], debugUnlockAll: false)), .newProject)
        XCTAssertEqual(FeatureGate.sessionTarget(forLibraryPlay: EntitlementState(purchased: [.crt, .mp4Export], debugUnlockAll: false)), .temporary)
    }

    func testPreviousTemporarySession() {
        XCTAssertEqual(FeatureGate.previousSession(hasContent: false, .free), .nothingToAsk)
        XCTAssertEqual(FeatureGate.previousSession(hasContent: false, .allUnlocked), .nothingToAsk)
        XCTAssertEqual(FeatureGate.previousSession(hasContent: true, .free), .replace)
        XCTAssertEqual(FeatureGate.previousSession(hasContent: true, .allUnlocked), .askKeep)
    }

    func testCRTChoiceIsKeptButHasNoEffectWhileLocked() {
        XCTAssertFalse(FeatureGate.effectiveCRT(stored: true, .free))
        XCTAssertTrue(FeatureGate.effectiveCRT(stored: true, EntitlementState(purchased: [.crt], debugUnlockAll: false)))
        XCTAssertFalse(FeatureGate.effectiveCRT(stored: false, .allUnlocked))
    }

    func testExportWithCRTNeedsBothUnlocks() {
        XCTAssertFalse(FeatureGate.exportCRTAllowed(EntitlementState(purchased: [.mp4Export], debugUnlockAll: false)))
        XCTAssertFalse(FeatureGate.exportCRTAllowed(EntitlementState(purchased: [.crt], debugUnlockAll: false)))
        XCTAssertTrue(FeatureGate.exportCRTAllowed(EntitlementState(purchased: [.crt, .mp4Export], debugUnlockAll: false)))
    }

    func testStateRoundTripsThroughCodable() throws {
        let e = EntitlementState(purchased: [.recording, .crt], debugUnlockAll: false)
        let back = try JSONDecoder().decode(EntitlementState.self, from: JSONEncoder().encode(e))
        XCTAssertEqual(back, e)
    }
}

final class EntitlementsTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "replaynes.tests.entitlements"

    override func setUp() {
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() { defaults.removePersistentDomain(forName: suite) }

    func testPrototypeDefaultsToEverythingUnlocked() {
        let e = Entitlements(store: StubPurchaseStore(), defaults: defaults)
        XCTAssertTrue(e.debugUnlockAll)
        XCTAssertTrue(e.isUnlocked(.recording) && e.isUnlocked(.mp4Export) && e.isUnlocked(.crt))
    }

    func testSwitchIsPersisted() {
        let e = Entitlements(store: StubPurchaseStore(), defaults: defaults)
        e.debugUnlockAll = false
        XCTAssertFalse(e.isUnlocked(.recording))
        let again = Entitlements(store: StubPurchaseStore(), defaults: defaults)
        XCTAssertFalse(again.debugUnlockAll)
    }

    func testStubPurchaseUnlocksOnlyThatFeatureWithoutNetwork() {
        let store = StubPurchaseStore(defaults: defaults)
        let e = Entitlements(store: store, defaults: defaults)
        e.debugUnlockAll = false
        let done = expectation(description: "purchase")
        e.purchase(.crt) { ok in XCTAssertTrue(ok); done.fulfill() }
        wait(for: [done], timeout: 2)
        XCTAssertTrue(e.isUnlocked(.crt))
        XCTAssertFalse(e.isUnlocked(.recording))
        // Restored by a new store on the same defaults (a relaunch).
        let restored = Entitlements(store: StubPurchaseStore(defaults: defaults), defaults: defaults)
        let refreshed = expectation(description: "refresh")
        restored.refresh()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { refreshed.fulfill() }
        wait(for: [refreshed], timeout: 2)
        XCTAssertTrue(restored.isUnlocked(.crt))
        e.resetStubPurchases()
        XCTAssertFalse(e.isUnlocked(.crt))
    }

    func testProductIDsAreDistinctPlaceholders() {
        let ids = PaidFeature.allCases.compactMap { ProductCatalog.ids[$0] }
        XCTAssertEqual(ids.count, PaidFeature.allCases.count)
        XCTAssertEqual(Set(ids).count, ids.count)
        for f in PaidFeature.allCases { XCTAssertEqual(ProductCatalog.feature(forProduct: ProductCatalog.ids[f]!), f) }
    }
}
