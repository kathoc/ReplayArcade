// iOS-only UI strings: Resources/IOS.xcstrings (table "IOS", English source text as key, Japanese
// translation). Strings shared with macOS keep using String(localized:) and the shared catalog
// apps/macos/Resources/Localizable.xcstrings, which this branch never rewrites (SWIFT_EMIT_LOC_STRINGS
// is off for the iOS targets).
// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation

/// The localized iOS string for `key` (the English text).
func L(_ key: String) -> String {
    Bundle.main.localizedString(forKey: key, value: key, table: "IOS")
}

/// Localized format (`%@`, `%lld`, `%d` as in String(format:)).
func L(_ key: String, _ args: CVarArg...) -> String {
    String(format: L(key), arguments: args)
}
