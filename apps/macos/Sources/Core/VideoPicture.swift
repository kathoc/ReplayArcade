// A session's picture with its geometry (rn_session_video_frame + rn_session_media_info): any core's
// size (NES 256x240, an arcade board's 320x224 ...), clockwise display rotation (vertical games) and
// pixel aspect. docs/plans/2026-10-24-media-frontend.md.
// SPDX-License-Identifier: GPL-2.0-or-later
import CoreGraphics
import Foundation

/// The geometry of the pictures of a session.
struct PictureGeometry: Equatable {
    var width = Int(RN_VIDEO_WIDTH), height = Int(RN_VIDEO_HEIGHT)
    /// Clockwise quarter turns for display (0...3).
    var rotation = 0
    /// Display width / height of one pixel (NES 8/7; the 8:7 option decides for the NES).
    var pixelAspect = 8.0 / 7.0

    static let nes = PictureGeometry()

    /// The NES picture (PPU codes, CRT model, overscan crop, flash filter apply).
    var isNESPicture: Bool { width == Int(RN_VIDEO_WIDTH) && height == Int(RN_VIDEO_HEIGHT) && rotation == 0 }
    /// Width and height on screen in source pixels (swapped for 90 / 270 degrees).
    var displayed: (width: Int, height: Int) { rotation % 2 == 1 ? (height, width) : (width, height) }
}

struct VideoPicture {
    var pixels: [UInt32]
    var geometry: PictureGeometry
}

extension VideoPicture {
    /// The last frame of a session (nil before the first frame or on an error).
    init?(session s: OpaquePointer) {
        var f = rn_video_frame_info()
        guard rn_session_video_frame(s, &f) == RN_OK, let src = f.pixels, f.width > 0, f.height > 0 else { return nil }
        var g = PictureGeometry(width: Int(f.width), height: Int(f.height))
        var m = rn_media_info()
        if rn_session_media_info(s, &m) == RN_OK {
            g.rotation = Int(m.rotation % 4)
            if m.pixel_aspect_num > 0, m.pixel_aspect_den > 0 { g.pixelAspect = Double(m.pixel_aspect_num) / Double(m.pixel_aspect_den) }
        }
        var px = [UInt32](repeating: 0, count: g.width * g.height)
        px.withUnsafeMutableBufferPointer { out in
            for y in 0..<g.height { (out.baseAddress! + y * g.width).update(from: src + y * Int(f.stride), count: g.width) }
        }
        self.init(pixels: px, geometry: g)
    }

    /// The picture upright as shown (rotation applied; pixel aspect not), cropping `crop` source pixels
    /// from the top and bottom (the NES overscan).
    func cgImage(crop: Int = 0) -> CGImage? {
        let w = geometry.width, h = geometry.height
        let data = pixels.withUnsafeBufferPointer { Data(buffer: $0) }
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        guard let provider = CGDataProvider(data: data as CFData),
              let full = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: space,
                                 bitmapInfo: info, provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
              let img = crop > 0 ? full.cropping(to: CGRect(x: 0, y: crop, width: w, height: h - 2 * crop)) : full
        else { return nil }
        let turns = geometry.rotation % 4
        guard turns != 0 else { return img }
        let (ow, oh) = turns % 2 == 1 ? (img.height, img.width) : (img.width, img.height)
        guard let ctx = CGContext(data: nil, width: ow, height: oh, bitsPerComponent: 8, bytesPerRow: ow * 4, space: space,
                                  bitmapInfo: info.rawValue) else { return nil }
        ctx.interpolationQuality = .none
        // Core Graphics' origin is bottom-left: a clockwise turn on screen is a negative angle here.
        ctx.translateBy(x: CGFloat(ow) / 2, y: CGFloat(oh) / 2)
        ctx.rotate(by: -CGFloat(turns) * .pi / 2)
        ctx.draw(img, in: CGRect(x: -CGFloat(img.width) / 2, y: -CGFloat(img.height) / 2, width: CGFloat(img.width), height: CGFloat(img.height)))
        return ctx.makeImage()
    }
}
