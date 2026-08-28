import SwiftUI

extension AppColors {
    static let primaryAccent = brand
    static let primaryOrange = brand
    static let primaryBlue = info
    static let primaryPurple = dynamic(light: 0x6D4AC4, dark: 0xA98CF0)
    static let statusGreen = success
    static let statusBlue = info
    static let statusOrange = brand
    static let statusGray = textTertiary
    static let backgroundSecondary = surfaceMuted
}

enum AppSpacing {
    static let xxSmall = Space.hair
    static let small = Space.sm
    static let cornerRadiusSmall = Radius.xs
}

enum AppTypography {
    static let caption2 = AppType.font(.caption)
}
