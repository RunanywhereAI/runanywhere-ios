import SwiftUI

enum Space {
    static let hair: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

enum Radius {
    static let xs: CGFloat = 6
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 22
    static let pill: CGFloat = 999
}

enum Stroke {
    static var hairline: CGFloat {
        #if canImport(UIKit)
        1 / max(UIScreen.main.scale, 1)
        #else
        0.5
        #endif
    }

    static let regular: CGFloat = 1
    static let heavy: CGFloat = 2
}

enum Measure {
    static let hitTarget: CGFloat = 44
    static let content: CGFloat = 720
    static let barHeight: CGFloat = 52
}

enum Glyph {
    static let xs: CGFloat = 13
    static let sm: CGFloat = 15
    static let md: CGFloat = 18
    static let lg: CGFloat = 22
    static let hero: CGFloat = 34
}

extension View {
    func measured(_ width: CGFloat = Measure.content) -> some View {
        frame(maxWidth: width)
            .frame(maxWidth: .infinity)
    }

    func card(radius: CGFloat = Radius.lg) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return background(AppColors.surface, in: shape)
            .overlay(shape.strokeBorder(AppColors.border, lineWidth: Stroke.hairline))
    }

    func glyph(_ size: CGFloat = Glyph.md, weight: Font.Weight = .medium) -> some View {
        font(.system(size: size, weight: weight))
            .symbolRenderingMode(.hierarchical)
    }
}
