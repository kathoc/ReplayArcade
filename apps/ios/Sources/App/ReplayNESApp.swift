// iPhone app entry: the library until a game runs, then the play screen; alerts, prompts and
// sheets; scene phase -> persistence (iOS may end the app any time it is in the background).
// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

@main
struct ReplayNESApp: App {
    @StateObject private var model = AppModel.shared
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var phase

    init() {
        // The product's core, content identity and ROM filter, before AppModel touches the library.
        RNProduct.startup()
        UILanguage.applyAtLaunch()
        TestHooks.prepare()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .onAppear {
                    model.start()
                    TestHooks.run(model)
                }
                // Opened files come in through SceneDelegate (all URLs of a multi-item open).
        }
        .onChange(of: phase) { _, p in
            switch p {
            case .background: model.enterBackground()
            case .active: model.enterForeground()
            default: break
            }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if model.status.hasSession && !model.showLibrary {
                PlayView()
            } else {
                LibraryView()
                    .overlay(alignment: .bottom) { LibraryNotice() }
            }
            if model.showBusy {
                // A session change is saving / loading off the main thread (AppModel.beginBusy).
                ZStack {
                    Color.black.opacity(0.35).ignoresSafeArea()
                    ProgressView().controlSize(.large).tint(.white)
                }
                .contentShape(Rectangle())
                .accessibilityIdentifier("busy")
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: model.showBusy)
        .alert(model.alert?.title ?? "", isPresented: Binding(get: { model.alert != nil }, set: { if !$0 { model.alert = nil } }),
               presenting: model.alert) { a in
            ForEach(Array(a.actions.enumerated()), id: \.offset) { _, act in
                Button(act.title, role: act.role) { act.run() }
            }
        } message: { a in Text(a.message) }
        .alert(model.prompt?.title ?? "", isPresented: Binding(get: { model.prompt != nil }, set: { if !$0 { model.prompt = nil } }),
               presenting: model.prompt) { p in
            PromptField(prompt: p)
        }
        .sheet(isPresented: $model.showUnlocks) { UnlocksView().environmentObject(model) }
        .sheet(isPresented: $model.showExport) { ExportView().environmentObject(model) }
    }
}

/// Notices over the library (the play screen shows its own over the picture): import results.
private struct LibraryNotice: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack {
            if let n = model.notice {
                Text(n).font(.system(size: 14, weight: .medium)).multilineTextAlignment(.center)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.15)))
                    .foregroundStyle(.white)
                    .accessibilityIdentifier("notice")
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 32)
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.2), value: model.notice)
    }
}

private struct PromptField: View {
    let prompt: AppPrompt
    @State private var text: String
    init(prompt: AppPrompt) {
        self.prompt = prompt
        _text = State(initialValue: prompt.text)
    }
    var body: some View {
        TextField("", text: $text)
        Button(String(localized: "Rename")) { prompt.done(text) }
        Button(String(localized: "Cancel"), role: .cancel) {}
    }
}
