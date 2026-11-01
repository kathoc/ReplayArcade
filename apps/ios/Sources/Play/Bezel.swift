import UIKit

/// The product's bezel (docs/design/BEZEL.md on the desktop): the image set "Bezel" of the app's
/// assets, transparent in its window, and the window's place in the image's pixels in Info.plist
/// (`RNBezelWindow`: "x y width height"). A product without them (ReplayNES) has no bezel.
///
/// The iPhone keeps the picture where the touch layout puts it (between the control columns): the
/// bezel is scaled so its window just holds the picture, its outer frame may run off the screen.
enum Bezel {
    static let image: UIImage? = UIImage(named: "Bezel")
    /// The window in the image's pixels.
    static let window: CGRect? = {
        guard let s = Bundle.main.object(forInfoDictionaryKey: "RNBezelWindow") as? String else { return nil }
        let v = s.split(separator: " ").compactMap { Double($0) }
        guard v.count == 4, v[2] > 0, v[3] > 0 else { return nil }
        return CGRect(x: v[0], y: v[1], width: v[2], height: v[3])
    }()
    static var available: Bool { image != nil && window != nil }

    /// The bezel's frame (points) whose window holds `picture` (points), centred on it.
    static func frame(around picture: CGRect) -> CGRect? {
        guard let cg = image?.cgImage, let w = window, picture.width > 0, picture.height > 0 else { return nil }
        let s = max(picture.width / w.width, picture.height / w.height)
        return CGRect(x: picture.midX - w.midX * s, y: picture.midY - w.midY * s,
                      width: CGFloat(cg.width) * s, height: CGFloat(cg.height) * s)
    }
}
