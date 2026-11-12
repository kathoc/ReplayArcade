// Unlocks: what each paid feature adds, its (stubbed) purchase, and the prototype's
// "Unlock Everything (Test)" switch. No network: StubPurchaseStore (Entitlements/PurchaseStore.swift).
// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

enum Unlocks {
    static func title(_ f: PaidFeature) -> String {
        switch f {
        case .recording: return L("Recording")
        case .mp4Export: return L("MP4 Export")
        case .crt: return L("CRT Display")
        }
    }

    static func icon(_ f: PaidFeature) -> String {
        switch f {
        case .recording: return "record.circle"
        case .mp4Export: return "film"
        case .crt: return "tv"
        }
    }

    static func summary(_ f: PaidFeature) -> String {
        switch f {
        case .recording: return L("Keep every recording as a project: saved per game, listed in the library, openable on the Mac")
        case .mp4Export: return L("Export a take as an MP4 video (H.264 / HEVC)")
        case .crt: return L("The physical CRT TV model: scanlines, afterglow, RF signal")
        }
    }

    static func lockedMessage(_ f: PaidFeature) -> String {
        switch f {
        case .recording:
            return L("Without Recording you can play, rewind and practice; the current session is kept until you start another game. Recording keeps your recordings as projects.")
        case .mp4Export: return L("Exporting MP4 videos needs the MP4 Export unlock.")
        case .crt: return L("The CRT display model needs the CRT Display unlock.")
        }
    }
}

struct UnlocksView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var entitlements = Entitlements.shared
    @Environment(\.dismiss) private var dismiss
    @State private var busy: PaidFeature?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle(isOn: Binding(get: { entitlements.debugUnlockAll }, set: { entitlements.debugUnlockAll = $0 })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("Unlock Everything (Test)"))
                            Text(L("Prototype switch: every paid feature works without a purchase")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text(L("Free: play, rewind, fast-forward, practice and replay the current session. Nothing is sold in this test build: “Unlock” only simulates a purchase on this device."))
                }
                Section(L("Features")) {
                    ForEach(PaidFeature.allCases) { f in
                        HStack(spacing: 12) {
                            Image(systemName: Unlocks.icon(f)).frame(width: 26)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(Unlocks.title(f)).font(.headline)
                                Text(Unlocks.summary(f)).font(.caption).foregroundStyle(.secondary)
                                Text(ProductCatalog.ids[f] ?? "").font(.caption2.monospaced()).foregroundStyle(.tertiary)
                            }
                            Spacer()
                            if entitlements.isUnlocked(f) {
                                Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                            } else {
                                Button(busy == f ? "…" : L("Unlock")) {
                                    busy = f
                                    entitlements.purchase(f) { _ in busy = nil }
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                    }
                }
                if let e = entitlements.lastError {
                    Section { Text(e).foregroundStyle(.red) }
                }
                Section {
                    Button(L("Forget Simulated Purchases"), role: .destructive) { entitlements.resetStubPurchases() }
                }
            }
            .navigationTitle(L("Unlocks"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(String(localized: "Done")) { dismiss() } } }
        }
    }
}
