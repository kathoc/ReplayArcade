// Hit areas for touch: a control drawn smaller than Apple's 44 x 44 pt minimum still takes a
// finger's tap anywhere in a 44 x 44 pt box around it, without changing the layout (the extra is
// padding that is taken back after the content shape).
// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

extension View {
    /// `width` / `height`: the size the control is drawn at (nil = flexible, left as it is).
    func touchTarget(width: CGFloat? = nil, height: CGFloat? = nil, side: CGFloat = 44) -> some View {
        let h = width.map { max(0, (side - $0) / 2) } ?? 0
        let v = height.map { max(0, (side - $0) / 2) } ?? 0
        return padding(.horizontal, h).padding(.vertical, v)
            .contentShape(Rectangle())
            .padding(.horizontal, -h).padding(.vertical, -v)
    }
}
