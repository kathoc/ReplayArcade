// iPhone copy of apps/macos/Sources/App/CountdownOverlay.swift (MetalView.swift, shared, draws it):
// the same disc, ring and numeral, with UIKit text drawing instead of AppKit's.
// The practice countdown's picture (3, 2, 1 after the run returned to A): a large numeral on a soft
// dark disc with a thin ring running down the second. The animation (fade / scale) is the shared
// core's (rnf_practice_countdown_visual), the same look as the desktop frontends (ui_play.cpp);
// MetalView draws it inside the game's own pass.
// SPDX-License-Identifier: GPL-2.0-or-later
import UIKit

enum CountdownOverlay {
    /// side x side premultiplied BGRA (top row first), or nil.
    static func render(_ v: rnf_countdown_visual, side: Int) -> [UInt8]? {
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        let ok = bytes.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
            else { return false }
            let a = CGFloat(v.alpha)
            let s = CGFloat(side), r = s / 2, c = CGPoint(x: r, y: r)
            ctx.setFillColor(CGColor(srgbRed: 20 / 255, green: 20 / 255, blue: 22 / 255, alpha: 0.62 * a))
            ctx.fillEllipse(in: CGRect(x: 0, y: 0, width: s, height: s))
            let ringW = max(2, r * 0.045), rr = r - ringW * 1.6
            ctx.setLineWidth(ringW)
            ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.14 * a))
            ctx.strokeEllipse(in: CGRect(x: c.x - rr, y: c.y - rr, width: rr * 2, height: rr * 2))
            if v.ring > 0.002 {
                // From 12 o'clock, clockwise (CoreGraphics is y-up here).
                ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.85 * a))
                ctx.setLineCap(.butt)
                ctx.addArc(center: c, radius: rr, startAngle: .pi / 2, endAngle: .pi / 2 - 2 * .pi * CGFloat(v.ring), clockwise: true)
                ctx.strokePath()
            }
            // UIKit draws y-down: flip the y-up context for the text (same baseline maths below).
            ctx.saveGState()
            ctx.translateBy(x: 0, y: s)
            ctx.scaleBy(x: 1, y: -1)
            UIGraphicsPushContext(ctx)
            let font = UIFont.monospacedDigitSystemFont(ofSize: r * 1.25 * CGFloat(v.scale), weight: .semibold)
            let text = NSAttributedString(string: "\(v.number)", attributes: [
                .font: font, .foregroundColor: UIColor(red: 1, green: 1, blue: 1, alpha: a),
            ])
            let ts = text.size()
            // Optical centre: the numeral's cap height on the centre, not the line box (draw(at:) is
            // the line's lower left; the baseline is |descender| above it).
            // y-down: the line box's top is ascender above the baseline.
            let baseline = c.y + font.capHeight / 2
            text.draw(at: CGPoint(x: c.x - ts.width / 2, y: baseline - font.ascender))
            UIGraphicsPopContext()
            ctx.restoreGState()
            return true
        }
        return ok ? bytes : nil
    }
}
