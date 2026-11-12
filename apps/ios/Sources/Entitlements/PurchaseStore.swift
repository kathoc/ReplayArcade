// Purchases behind the entitlements. The prototype uses StubPurchaseStore (in memory, no
// network). StoreKitPurchaseStore is the StoreKit 2 shape of the real thing; it is compiled but
// only created with the launch argument `-storeKitLive YES` (it then asks the App Store, which needs
// real product ids in App Store Connect; the ids below are placeholders).
// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import StoreKit

/// Product ids (placeholders until the App Store Connect products exist).
enum ProductCatalog {
    static let ids: [PaidFeature: String] = [
        .recording: "io.github.replaynes.unlock.recording",
        .mp4Export: "io.github.replaynes.unlock.mp4export",
        .crt: "io.github.replaynes.unlock.crt",
    ]

    static func feature(forProduct id: String) -> PaidFeature? { ids.first { $0.value == id }?.key }
}

struct ProductInfo: Equatable, Identifiable {
    let feature: PaidFeature
    let productID: String
    let displayPrice: String
    var id: String { productID }
}

enum PurchaseError: Error, LocalizedError, Equatable {
    case unavailable
    case cancelled
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable: return L("Purchases aren’t available in this test build")
        case .cancelled: return L("The purchase was cancelled")
        case .failed(let m): return m
        }
    }
}

protocol PurchaseStore: AnyObject {
    /// The features this store says were bought (restored at launch).
    func currentEntitlements() async -> Set<PaidFeature>
    func products() async throws -> [ProductInfo]
    /// Buys the feature's product; returns the new set of bought features.
    func purchase(_ f: PaidFeature) async throws -> Set<PaidFeature>
}

/// No network, no App Store: "buying" records the feature in memory (and in UserDefaults when a
/// suite is given, so a test build can simulate a restored purchase).
final class StubPurchaseStore: PurchaseStore {
    private let defaults: UserDefaults?
    private let key = "stubPurchases"
    private let lock = NSLock()
    private var bought: Set<PaidFeature>

    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults
        let raw = defaults?.stringArray(forKey: key) ?? []
        bought = Set(raw.compactMap(PaidFeature.init(rawValue:)))
    }

    private func locked<T>(_ f: () -> T) -> T { lock.lock(); defer { lock.unlock() }; return f() }

    func currentEntitlements() async -> Set<PaidFeature> { locked { bought } }

    func products() async throws -> [ProductInfo] {
        PaidFeature.allCases.map { ProductInfo(feature: $0, productID: ProductCatalog.ids[$0] ?? "", displayPrice: "—") }
    }

    func purchase(_ f: PaidFeature) async throws -> Set<PaidFeature> {
        let out = locked { bought.insert(f); return bought }
        defaults?.set(out.map(\.rawValue).sorted(), forKey: key)
        return out
    }

    func reset() {
        locked { bought = [] }
        defaults?.removeObject(forKey: key)
    }
}

/// StoreKit 2 (non-consumable unlocks). Not used by default; see the header.
final class StoreKitPurchaseStore: PurchaseStore {
    func currentEntitlements() async -> Set<PaidFeature> {
        var out: Set<PaidFeature> = []
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result, t.revocationDate == nil, let f = ProductCatalog.feature(forProduct: t.productID) {
                out.insert(f)
            }
        }
        return out
    }

    func products() async throws -> [ProductInfo] {
        let ps = try await Product.products(for: Array(ProductCatalog.ids.values))
        return ps.compactMap { p in
            ProductCatalog.feature(forProduct: p.id).map { ProductInfo(feature: $0, productID: p.id, displayPrice: p.displayPrice) }
        }
    }

    func purchase(_ f: PaidFeature) async throws -> Set<PaidFeature> {
        guard let id = ProductCatalog.ids[f], let p = try await Product.products(for: [id]).first else { throw PurchaseError.unavailable }
        switch try await p.purchase() {
        case .success(let v):
            guard case .verified(let t) = v else { throw PurchaseError.failed("unverified transaction") }
            await t.finish()
            return await currentEntitlements()
        case .userCancelled: throw PurchaseError.cancelled
        case .pending: throw PurchaseError.failed(L("The purchase is pending approval"))
        @unknown default: throw PurchaseError.unavailable
        }
    }
}
