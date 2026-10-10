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
        UILanguage.applyAtLaunch()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .onAppear {
                    model.start()
                    TestHooks.run(model)
                }
                .onOpenURL { model.open(url: $0) }
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
            }
        }
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
