// The app's view of the entitlements (main thread): the state the UI and the gates read, the
// prototype's "unlock everything" switch and the purchase store behind it.
// SPDX-License-Identifier: GPL-2.0-or-later
import Combine
import Foundation

final class Entitlements: ObservableObject {
    static let shared = Entitlements(store: Entitlements.defaultStore(), defaults: .standard)

    @Published private(set) var state: EntitlementState
    @Published private(set) var lastError: String?

    let store: PurchaseStore
    private let defaults: UserDefaults
    static let debugKey = "debugUnlockAll"

    init(store: PurchaseStore, defaults: UserDefaults) {
        self.store = store
        self.defaults = defaults
        // Prototype: everything is unlocked until the switch is turned off (nothing is sold yet).
        let debug = defaults.object(forKey: Self.debugKey) == nil ? true : defaults.bool(forKey: Self.debugKey)
        state = EntitlementState(purchased: [], debugUnlockAll: debug)
    }

    static func defaultStore() -> PurchaseStore {
        UserDefaults.standard.bool(forKey: "storeKitLive") ? StoreKitPurchaseStore() : StubPurchaseStore(defaults: .standard)
    }

    func isUnlocked(_ f: PaidFeature) -> Bool { state.isUnlocked(f) }
    func allows(_ a: GatedAction) -> Bool { FeatureGate.allows(a, state) }

    /// Settings › System › Unlocks › "Unlock Everything (Test)".
    var debugUnlockAll: Bool {
        get { state.debugUnlockAll }
        set {
            defaults.set(newValue, forKey: Self.debugKey)
            state.debugUnlockAll = newValue
        }
    }

    /// Launch: what the store says was bought.
    func refresh() {
        let store = self.store
        Task { @MainActor in
            let bought = await store.currentEntitlements()
            self.state.purchased = bought
        }
    }

    func purchase(_ f: PaidFeature, done: ((Bool) -> Void)? = nil) {
        let store = self.store
        Task { @MainActor in
            do {
                self.state.purchased = try await store.purchase(f)
                self.lastError = nil
                done?(true)
            } catch {
                self.lastError = (error as? LocalizedError)?.errorDescription ?? "\(error)"
                done?(false)
            }
        }
    }

    /// Test builds: forget simulated purchases.
    func resetStubPurchases() {
        (store as? StubPurchaseStore)?.reset()
        state.purchased = []
    }
}
