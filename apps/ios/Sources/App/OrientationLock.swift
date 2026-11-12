// iPhone screen orientation setting (Settings › Display › Picture Shape › Orientation): Auto
// follows the device, Portrait / Landscape lock the interface. The app delegate answers
// supportedInterfaceOrientations from it (AppDelegate.swift) (so a locked app also launches in its orientation), and
// a change rotates at once with UIWindowScene.requestGeometryUpdate.
// SPDX-License-Identifier: GPL-2.0-or-later
import UIKit

enum OrientationLock: Int, CaseIterable {
    case auto, portrait, landscape

    /// UserDefaults key (AppModel.orientationLock, @AppStorage).
    static let key = "orientationLock"

    var mask: UIInterfaceOrientationMask {
        switch self {
        case .auto: return .allButUpsideDown
        case .portrait: return .portrait
        case .landscape: return .landscape
        }
    }

    /// The stored setting (read by the app delegate before AppModel exists).
    static var current: OrientationLock {
        OrientationLock(rawValue: UserDefaults.standard.integer(forKey: key)) ?? .auto
    }

    /// Tell UIKit the supported orientations changed and, when locked, rotate to the lock.
    static func apply(_ lock: OrientationLock) {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for w in scene.windows { w.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations() }
            if lock != .auto {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: lock.mask)) { NSLog("ReplayNES: orientation: \($0)") }
            }
        }
    }
}
