// Share › Export MP4 (paid: .mp4Export): the shared exporter (Core/MP4Exporter.swift, AVFoundation,
// the same presets as macOS) writes Documents/Exports/<name>.mp4 (visible in the Files app), then
// the share sheet offers it to Photos, AirDrop, ...
// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI
import UIKit

struct ExportView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var codec = ExportSettings.Codec.h264
    @State private var preset = ExportSettings.SizePreset.canvas(1280, 960)
    @State private var par87 = false
    @State private var flash = true
    @State private var useCRT = false
    @State private var shareURL: URL?

    var body: some View {
        NavigationStack {
            Form {
                if let job = model.exportJob, !job.finished || job.result != nil || job.error != nil {
                    ExportProgressSection(job: job, share: { shareURL = $0 })
                } else {
                    Section {
                        Picker(L("Size"), selection: $preset) {
                            ForEach(ExportSettings.SizePreset.all) { p in Text(p.label).tag(p) }
                        }
                        Picker(L("Codec"), selection: $codec) {
                            ForEach(ExportSettings.Codec.allCases) { c in Text(c.label).tag(c) }
                        }
                        Toggle("8:7", isOn: $par87)
                        Toggle(String(localized: "Reduce Flashing"), isOn: $flash)
                        if FeatureGate.exportCRTAllowed(model.entitlements.state) {
                            Toggle(String(localized: "CRT"), isOn: $useCRT)
                        }
                    } footer: {
                        Text(L("The whole active take (%@) is exported.", Engine.timecode(forFrame: model.status.takeLength)))
                    }
                    Section {
                        Button(L("Export")) { start() }.disabled(model.status.takeLength == 0)
                    }
                }
            }
            .navigationTitle(String(localized: "Export MP4"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Close")) { model.exportJob?.cancel(); model.exportJob = nil; dismiss() }
                }
            }
            .sheet(item: Binding(get: { shareURL.map(ShareItem.init) }, set: { shareURL = $0?.url })) { item in
                ShareSheet(items: [item.url])
            }
        }
    }

    private func start() {
        var s = ExportSettings()
        s.codec = codec
        s.preset = preset
        s.pixelAspect87 = par87
        s.flashReduction = flash ? model.flashLevel : .off
        s.crt = useCRT && FeatureGate.exportCRTAllowed(model.entitlements.state) ? CRTSettingsModel.shared.settings : nil
        let dir = model.library.paths.root.appendingPathComponent("Exports", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = URL(fileURLWithPath: model.status.romPath).deletingPathExtension().lastPathComponent
        let url = dir.appendingPathComponent("\(name) \(LibraryScanner.timestamp(Date())).mp4")
        do { try s.validate() } catch { model.showError(String(localized: "Export MP4"), error.localizedDescription); return }
        model.startExport(s, to: url)
    }
}

private struct ExportProgressSection: View {
    @ObservedObject var job: ExportJob
    let share: (URL) -> Void

    var body: some View {
        Section {
            if let e = job.error {
                Text(e).foregroundStyle(.red)
            } else if job.result != nil {
                Label(L("Exported to Files › ReplayNES › Exports"), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                Button(L("Share…")) { share(job.url) }
            } else {
                ProgressView(value: job.total > 0 ? Double(job.done) / Double(job.total) : 0)
                Text(verbatim: "\(job.done) / \(job.total)").font(.caption.monospacedDigit())
                Button(String(localized: "Cancel"), role: .destructive) { job.cancel() }
            }
        }
    }
}

struct ShareItem: Identifiable {
    let url: URL
    var id: String { url.path }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
