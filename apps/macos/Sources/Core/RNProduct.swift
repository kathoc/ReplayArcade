// The product this build is (ReplayNES, or another product such as ReplayArcade built from the same
// sources): the engine's generated replaynes/product.h, through the bridging header. Builds that do not
// see the generated header (the macOS Xcode project) get ReplayNES's values from frontend.h.
// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation

enum RNProduct {
    static let name = RN_PRODUCT_NAME
    /// Folder name under Documents and Application Support.
    static let dataDirectory = RN_PRODUCT_DATA_DIR
    /// Project package extension without the dot ("nesrec").
    static let projectExtension = String(RN_PRODUCT_PROJECT_EXT.drop { $0 == "." })
    /// ROM file extensions, lower case, without the dot.
    static let romExtensions = Set(RN_PRODUCT_ROM_EXTS.lowercased().split(separator: ";").map(String.init))
    /// The NES product: iNES images, the test cartridge, the NES game database.
    static let isNES = RN_PRODUCT_NES != 0

    static func isROMFile(_ url: URL) -> Bool { romExtensions.contains(url.pathExtension.lowercased()) }
    static func isProject(_ url: URL) -> Bool { url.pathExtension.lowercased() == projectExtension }

    /// The product's start-up hook (registers its core, content identity and ROM filter), like the
    /// Linux app's RN_PRODUCT_HAS_STARTUP. Once, before the library or a session is used.
    static func startup() {
        #if RN_PRODUCT_HAS_STARTUP
        rnProductStartup()
        #endif
    }
}

#if RN_PRODUCT_HAS_STARTUP
@_silgen_name("rn_product_startup")
private func rnProductStartup()
#endif
