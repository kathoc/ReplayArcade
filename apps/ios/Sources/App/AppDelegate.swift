// UIKit delegates for what SwiftUI's App has no API for: the supported orientations
// (OrientationLock) and every URL of a multi-item "Open in" (SceneDelegate).
// SPDX-License-Identifier: GPL-2.0-or-later
import UIKit

/// UIApplicationDelegate for what SwiftUI's App has no API for: the supported orientations and
/// the scene delegate below.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        UIDevice.current.userInterfaceIdiom == .phone ? OrientationLock.current.mask : .all
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let c = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        c.delegateClass = SceneDelegate.self
        return c
    }
}

/// Files opened from other apps. SwiftUI's onOpenURL hands over only the first URL of a
/// multi-item open (Files › select several › Share › ReplayNES delivers one UIOpenURLAction with
/// every file), so the scene delegate takes all of them, at launch and while running. SwiftUI keeps
/// creating the window; this class only sees the URL contexts.
final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        deliver(connectionOptions.urlContexts)
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        deliver(URLContexts)
    }

    private func deliver(_ contexts: Set<UIOpenURLContext>) {
        guard !contexts.isEmpty else { return }
        NSLog("ReplayNES: open \(contexts.count) URL(s)")
        AppModel.shared.open(urls: contexts.map(\.url))
    }
}
