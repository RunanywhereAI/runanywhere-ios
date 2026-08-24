import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

enum AppColors {
    static let brand = dynamic(light: 0xFF6900, dark: 0xFF7A1A)
    static let onBrand = dynamic(light: 0x2A1200, dark: 0x1C0C00)
    static let brandMuted = dynamic(light: 0xFFEDE0, dark: 0x3A2018)
    static let brandSelected = dynamic(light: 0xFFCEA3, dark: 0xB0500F)

    static let background = dynamic(light: 0xFFFAF6, dark: 0x141112)
    static let surface = dynamic(light: 0xFFFFFF, dark: 0x1C1819)
    static let surfaceMuted = dynamic(light: 0xFBF1E9, dark: 0x231E1F)

    static let border = dynamic(light: 0xEEDFD3, dark: 0x332C2D)
    static let borderStrong = dynamic(light: 0xE0CBBA, dark: 0x453C3D)

    static let textPrimary = dynamic(light: 0x1F1813, dark: 0xF6F2F2)
    static let textSecondary = dynamic(light: 0x6E5D51, dark: 0xB0A6A6)
    static let textTertiary = dynamic(light: 0x9C8879, dark: 0x7C7273)

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
