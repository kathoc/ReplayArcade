// Share Extension "Add to ReplayNES": takes every file of a share (Files › select several › Share,
// other apps), copies them into the App Group's ShareInbox (Sources/Shared/ShareInbox.swift) and
// tells the app, which imports them through its ROM import queue when it becomes active (or at once
// if it is running). A minimal confirmation: "Add N file(s) to ReplayNES" with Add / Cancel.
// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Strings of this extension (ShareExtension/Share.xcstrings, table "Share").
private func S(_ key: String) -> String { Bundle.main.localizedString(forKey: key, value: key, table: "Share") }
private func S(_ key: String, _ args: CVarArg...) -> String { String(format: S(key), arguments: args) }

final class ShareViewController: UIViewController {
    private let model = ShareModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        model.load(extensionContext?.inputItems as? [NSExtensionItem] ?? [])
        model.onFinish = { [weak self] added in
            guard let ctx = self?.extensionContext else { return }
            if added {
                ctx.completeRequest(returningItems: nil)
            } else {
                ctx.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
            }
        }
        let host = UIHostingController(rootView: ShareView(model: model))
        host.view.backgroundColor = .clear
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }
}

final class ShareModel: ObservableObject {
    enum Phase: Equatable { case ready, copying, failed(String) }

    @Published private(set) var names: [String] = []
    @Published private(set) var phase = Phase.ready
    var onFinish: ((Bool) -> Void)?
    private var providers: [NSItemProvider] = []

    func load(_ items: [NSExtensionItem]) {
        providers = items.flatMap { $0.attachments ?? [] }
        names = providers.enumerated().map { i, p in p.suggestedName ?? S("Item %lld", Int64(i + 1)) }
        // Files hands file URLs without a suggested name: show the file names once known.
        for (i, p) in providers.enumerated() where p.suggestedName == nil && p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            p.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { [weak self] item, _ in
                let url = (item as? URL) ?? (item as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
                guard let name = url?.lastPathComponent, !name.isEmpty else { return }
                DispatchQueue.main.async { if let self, self.names.indices.contains(i) { self.names[i] = name } }
            }
        }
    }

    var count: Int { providers.count }

    func cancel() { onFinish?(false) }

    /// Copies every item into a new ShareInbox batch, commits it and notifies the app.
    func add() {
        guard phase != .copying else { return }
        guard let root = ShareInbox.standardRoot() else {
            phase = .failed(S("The shared folder isn’t available (App Group)."))
            return
        }
        phase = .copying
        let batch: URL
        do { batch = try ShareInbox.beginBatch(root: root) } catch {
            phase = .failed(error.localizedDescription)
            return
        }
        let group = DispatchGroup()
        let lock = NSLock()
        var copied = 0
        var errors: [String] = []
        for (i, p) in providers.enumerated() {
            group.enter()
            Self.copy(p, index: i, into: batch) { result in
                lock.lock()
                switch result {
                case .success(true): copied += 1
                case .success(false): break // skipped (too large)
                case .failure(let e): errors.append(e.localizedDescription)
                }
                lock.unlock()
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            if copied == 0 {
                try? FileManager.default.removeItem(at: batch)
                self.phase = .failed(errors.first ?? S("None of the files could be read."))
                return
            }
            do { try ShareInbox.commit(batch) } catch {
                try? FileManager.default.removeItem(at: batch)
                self.phase = .failed(error.localizedDescription)
                return
            }
            ShareInbox.notifyApp()
            self.onFinish?(true)
        }
    }

    /// One item: its file URL when the provider has one (Files: the original file or package),
    /// else a file representation of its data. `true` = copied, `false` = skipped.
    private static func copy(_ p: NSItemProvider, index: Int, into batch: URL, done: @escaping (Result<Bool, Error>) -> Void) {
        let fileURL = UTType.fileURL.identifier
        if p.hasItemConformingToTypeIdentifier(fileURL) {
            p.loadItem(forTypeIdentifier: fileURL, options: nil) { item, error in
                let url = (item as? URL) ?? (item as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
                guard let url, url.isFileURL else {
                    loadRepresentation(p, index: index, into: batch, fallbackError: error, done: done)
                    return
                }
                done(Result { try copyFile(url, name: nil, index: index, into: batch) })
            }
            return
        }
        loadRepresentation(p, index: index, into: batch, fallbackError: nil, done: done)
    }

    private static func loadRepresentation(_ p: NSItemProvider, index: Int, into batch: URL, fallbackError: Error?,
                                           done: @escaping (Result<Bool, Error>) -> Void) {
        let types = p.registeredTypeIdentifiers
        let type = types.first { UTType($0)?.conforms(to: .data) == true || UTType($0)?.conforms(to: .package) == true } ?? types.first
        guard let type else { done(.failure(fallbackError ?? CocoaError(.fileReadUnknown))); return }
        p.loadFileRepresentation(forTypeIdentifier: type) { url, error in
            guard let url else { done(.failure(error ?? fallbackError ?? CocoaError(.fileReadUnknown))); return }
            // The temporary file's name may be generic: the provider's name with the type's extension.
            var name = url.lastPathComponent
            if let s = p.suggestedName, !s.isEmpty {
                let ext = (s as NSString).pathExtension.isEmpty ? (UTType(type)?.preferredFilenameExtension ?? url.pathExtension) : ""
                name = ext.isEmpty ? s : s + "." + ext
            }
            // The file is deleted when this handler returns: copy it now.
            done(Result { try copyFile(url, name: name, index: index, into: batch) })
        }
    }

    private static func copyFile(_ url: URL, name: String?, index: Int, into batch: URL) throws -> Bool {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let v = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
        if v?.isDirectory != true, let size = v?.fileSize, size > ShareInbox.maxFileSize { return false }
        var failure: Error?
        var coordError: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [.withoutChanges], error: &coordError) { u in
            do { try ShareInbox.add(u, name: name ?? url.lastPathComponent, index: index, to: batch) } catch { failure = error }
        }
        if let e = coordError ?? failure { throw e }
        return true
    }
}

struct ShareView: View {
    @ObservedObject var model: ShareModel

    var body: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: "gamecontroller.fill").font(.system(size: 30)).foregroundStyle(.tint)
                Text(S("Add %lld file(s) to ReplayNES", Int64(model.count)))
                    .font(.headline).multilineTextAlignment(.center)
                    .accessibilityIdentifier("shareTitle")
                if !model.names.isEmpty {
                    Text(summary).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center).lineLimit(4)
                }
                switch model.phase {
                case .ready:
                    Text(S("They are imported into the library when ReplayNES opens."))
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                case .copying:
                    ProgressView(S("Adding…"))
                case .failed(let msg):
                    Text(msg).font(.caption).foregroundStyle(.red).multilineTextAlignment(.center)
                }
                HStack(spacing: 12) {
                    Button(role: .cancel) { model.cancel() } label: {
                        Text(S("Cancel")).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("shareCancel")
                    Button { model.add() } label: {
                        Text(S("Add")).bold().frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.count == 0 || model.phase == .copying)
                    .accessibilityIdentifier("shareAdd")
                }
                .controlSize(.large)
            }
            .padding(20)
            .frame(maxWidth: 340)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color(uiColor: .secondarySystemBackground)))
            .padding(24)
        }
    }

    private var summary: String {
        let shown = model.names.prefix(3).joined(separator: "\n")
        return model.names.count > 3 ? shown + "\n" + S("and %lld more", Int64(model.names.count - 3)) : shown
    }
}
