// UI language on iOS: the system (and Settings › ReplayNES › Language, iOS's per-app language)
// decides with "Auto"; Settings › System › Language = Japanese / English pins it (applied at the
// next launch, as on macOS). The macOS rule reads the global preferences domain, which an iOS app
// cannot see, so iOS only pins for an explicit choice.
// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation

extension UILanguage {
    static func applyAtLaunch() {
        let pref = preference
        let d = UserDefaults.standard
        if pref == "ja" || pref == "en" {
            if d.stringArray(forKey: "AppleLanguages")?.first != pref { d.set([pref], forKey: "AppleLanguages") }
        } else if d.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")?["AppleLanguagesPinnedByApp"] as? Bool == true {
            d.removeObject(forKey: "AppleLanguages")
        }
        d.set(pref == "ja" || pref == "en", forKey: "AppleLanguagesPinnedByApp")
        syncCore()
    }
}
