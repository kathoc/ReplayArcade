// A face button in a controller hint: four small circles in a diamond (north, east, south, west),
// the one to press filled (shared core rnf_ui_face_glyph / rnf_ui_face_glyph_circle) - right on every
// controller family. The iPhone copy of the Mac's FaceGlyph / KeyCap (apps/macos/Sources/App/
// QuickMenu/QuickMenuView.swift, not part of the iOS target). Hint strings carry it as a
// one-character token (U+E000 north ... U+E003 west) that KeyCapIOS draws.
// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

struct FaceGlyph: View {
    let position: Int
    var size: CGFloat = 16
    var color: Color = .white

    static var southConfirm: Bool { UserDefaults.standard.bool(forKey: "southConfirm") }

    /// The hint token of a face element ("face.*", "ui.confirm", "ui.cancel"), or nil.
    static func token(forElement element: String) -> String? {
        InputCatalog.faceGlyph(element, southConfirm: southConfirm).map { String(UnicodeScalar(0xE000 + UInt32($0))!) }
    }
    /// The hint token of a face element (the element itself when it is not a face button).
    static func token(_ element: String) -> String { token(forElement: element) ?? element }
    /// The position of a hint token, nil for ordinary text.
    static func position(_ text: String) -> Int? {
        guard text.unicodeScalars.count == 1, let v = text.unicodeScalars.first?.value, (0xE000...0xE003).contains(v) else { return nil }
        return Int(v - 0xE000)
    }
    /// Running text cannot draw the glyph: the position's name ("Right button").
    static func plain(_ text: String) -> String {
        guard let p = position(text) else { return text }
        return String(cString: rnf_l10n_lookup(rnf_ui_face_glyph_name(rnf_face_position_glyph(rawValue: Int32(p)))))
    }

    var body: some View {
        Canvas { ctx, sz in
            let s = Double(min(sz.width, sz.height))
            for i in 0..<4 {
                var c = rnf_face_glyph_circle()
                guard rnf_ui_face_glyph_circle(Int32(i), s, &c) != 0 else { continue }
                let r = i == position ? c.radius : c.radius - c.stroke / 2
                let rect = CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
                if i == position {
                    ctx.fill(Path(ellipseIn: rect), with: .color(color))
                } else {
                    ctx.stroke(Path(ellipseIn: rect), with: .color(color.opacity(0.55)), lineWidth: c.stroke)
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(Text(FaceGlyph.plain(String(UnicodeScalar(0xE000 + UInt32(max(0, min(3, position))))!))))
    }
}

/// A key in a hint: a face button token as the position glyph, anything else as a small key cap.
struct KeyCapIOS: View {
    let text: String
    init(_ t: String) { text = t }
    var body: some View {
        if let p = FaceGlyph.position(text) {
            FaceGlyph(position: p, size: 18, color: .white.opacity(0.92)).frame(minWidth: 20, minHeight: 20).fixedSize()
        } else {
            Text(verbatim: text).font(.system(size: 11, weight: .bold, design: .rounded))
                .padding(.horizontal, 5).frame(minWidth: 20, minHeight: 20)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.16)))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.22), lineWidth: 1))
                .fixedSize()
        }
    }
}
