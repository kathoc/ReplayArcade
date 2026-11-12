// Share › Make Video (paid: .mp4Export; docs/design/VTR_UX.md "Make Video dialog"): range (All /
// Up to here / Section n), quality preset (Standard / High / Small), the length and an estimated
// size, Details (size, codec, 8:7, flash reduction, CRT). The shared exporter (Core/MP4Exporter.swift,
// AVFoundation, the same presets as macOS) writes Documents/Exports/<name>.mp4 (visible in the Files
// app), then the share sheet offers it to Photos, AirDrop, ...
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
    @State private var range: MakeVideo.Range = .all
    @State private var quality = ExportSettings.Quality.standard
    @ObservedObject private var clock = AppModel.shared.clock

    var body: some View {
        NavigationStack {
            Form {
                if let job = model.exportJob, !job.finished || job.result != nil || job.error != nil {
                    ExportProgressSection(job: job, share: { shareURL = $0 })
                } else {
                    let rs = ranges
                    let fr = frames
                    Section {
                        Picker(String(localized: "Range"), selection: $range) {
                            ForEach(rs, id: \.0) { r in Text(r.1).tag(r.0) }
                        }
                        Picker(String(localized: "Quality (video)"), selection: $quality) {
                            ForEach(0..<MakeVideo.qualityPresets, id: \.self) { i in
                                Text(MakeVideo.qualityLabel(i)).tag(MakeVideo.quality(i))
                            }
                        }
                        LabeledContent(String(localized: "Length")) {
                            Text(verbatim: fr.map { f in
                                let n = f.end - f.start
                                return MakeVideo.summary(frames: n, bytes: ExportGeometry(settings()).predictedBytes(
                                    hevc: codec == .hevc, quality: quality, frames: n))
                            } ?? "–")
                            .font(.callout.monospacedDigit())
                        }
                    }
                    Section(L("Details")) {
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
                    }
                    Section {
                        Button(String(localized: "Export")) { start() }.disabled(fr == nil)
                    }
                }
            }
            .navigationTitle(String(localized: "Make Video"))
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

    /// The A/B sections on the active take with both A and B.
    private var sections: [TimelineRange] {
        let st = clock.status
        return TimelineEditing.visibleRanges(slots: model.practiceSlots, takes: model.takes, activeTake: st.activeTake,
                                             takeLength: st.takeLength).filter { $0.b != nil }
    }

    private var ranges: [(MakeVideo.Range, String)] {
        [(.all, String(localized: "All (range)")), (.toHere, String(localized: "Up to here"))]
            + sections.map { (.section($0.slot), String(localized: "Section \($0.slot + 1)")) }
    }

    private var frames: (start: UInt64, end: UInt64)? {
        let st = clock.status
        var section: TimelineRange?
        if case .section(let n) = range { section = sections.first { $0.slot == n } }
        return MakeVideo.frames(range, cursor: st.frame, takeLength: st.takeLength, section: section)
    }

    private func settings() -> ExportSettings {
        var s = ExportSettings()
        s.codec = codec
        s.preset = preset
        s.quality = quality
        s.pixelAspect87 = par87
        return s
    }

    private func start() {
        guard let fr = frames else { return }
        var s = settings()
        s.startFrame = fr.start
        s.endFrame = fr.end
        s.flashReduction = flash ? model.flashLevel : .off
        s.crt = useCRT && FeatureGate.exportCRTAllowed(model.entitlements.state) ? CRTSettingsModel.shared.settings : nil
        let dir = model.library.paths.root.appendingPathComponent("Exports", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = URL(fileURLWithPath: model.status.romPath).deletingPathExtension().lastPathComponent
        let url = dir.appendingPathComponent("\(name) \(LibraryScanner.timestamp(Date())).mp4")
        do { try s.validate() } catch { model.showError(String(localized: "Couldn’t make the video"), error.localizedDescription); return }
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
                Label(L("Exported to Files › %@ › Exports", RNProduct.name), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
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
