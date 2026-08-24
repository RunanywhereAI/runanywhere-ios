import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

enum AppColors {
    /// The palette in force. Set once from `AppSettings`; the root view is
    /// keyed on the mode so the tree rebuilds when it changes.
    ///
    /// A stored property rather than an environment value because these
    /// tokens are read from `AppColors` directly all over the app, and
    /// threading an environment through every one of them would be a larger
    /// change than the feature is worth.
    nonisolated(unsafe) static var mode: AppMode = .user

    static let brand = dynamic(light: 0xFF6900, dark: 0xFF7A1A)
    static let onBrand = dynamic(light: 0x2A1200, dark: 0x1C0C00)
    static let brandMuted = dynamic(light: 0xFFEDE0, dark: 0x3A2018)
    static let brandSelected = dynamic(light: 0xFFCEA3, dark: 0xB0500F)

    static var background: Color {
        mode.isCool ? dynamic(light: 0xF7F9FC, dark: 0x101318)
                    : dynamic(light: 0xFFFAF6, dark: 0x141112)
    }

    static var surface: Color {
        mode.isCool ? dynamic(light: 0xFFFFFF, dark: 0x171B22)
                    : dynamic(light: 0xFFFFFF, dark: 0x1C1819)
    }

    static var surfaceMuted: Color {
        mode.isCool ? dynamic(light: 0xEEF2F9, dark: 0x1D222B)
                    : dynamic(light: 0xFBF1E9, dark: 0x231E1F)
    }

    static var border: Color {
        mode.isCool ? dynamic(light: 0xDDE4F0, dark: 0x2A313C)
                    : dynamic(light: 0xEEDFD3, dark: 0x332C2D)
    }

    static var borderStrong: Color {
        mode.isCool ? dynamic(light: 0xC7D2E4, dark: 0x3A4351)
                    : dynamic(light: 0xE0CBBA, dark: 0x453C3D)
    }

    /// The second colour after brand. Developer mode leans on blue so the two
    /// modes are distinguishable without reading a label; user mode keeps
    /// everything in the orange family.
    static var accent: Color {
        mode.isCool ? dynamic(light: 0x2F6FED, dark: 0x6BA0FF)
                    : dynamic(light: 0xFF6900, dark: 0xFF7A1A)
    }

    static var accentMuted: Color {
        mode.isCool ? dynamic(light: 0xE7EFFE, dark: 0x16233C)
                    : dynamic(light: 0xFFEDE0, dark: 0x3A2018)
    }

    static let textPrimary = dynamic(light: 0x1F1813, dark: 0xF6F2F2)
    static var textSecondary: Color {
        mode.isCool ? dynamic(light: 0x5A6473, dark: 0xA6AEBC)
                    : dynamic(light: 0x6E5D51, dark: 0xB0A6A6)
    }

    static var textTertiary: Color {
        mode.isCool ? dynamic(light: 0x8B94A3, dark: 0x737C8A)
                    : dynamic(light: 0x9C8879, dark: 0x7C7273)
    }

    static let info = dynamic(light: 0x2F6FED, dark: 0x6BA0FF)
    static let infoMuted = dynamic(light: 0xE7EFFE, dark: 0x16233C)

    static let success = dynamic(light: 0x158A4E, dark: 0x41CE85)
    static let successMuted = dynamic(light: 0xE3F5EB, dark: 0x0F2E1F)

    static let danger = dynamic(light: 0xC8321F, dark: 0xFF7561)
    static let dangerMuted = dynamic(light: 0xFCEAE6, dark: 0x39160F)

    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        #if canImport(UIKit)
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(rgb: dark) : UIColor(rgb: light) })
        #else
        Color(NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(rgb: isDark ? dark : light)
        })
        #endif
    }
}

#if canImport(UIKit)
private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
#else
private extension NSColor {
    convenience init(rgb: UInt32) {
        self.init(
            srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
#endif
