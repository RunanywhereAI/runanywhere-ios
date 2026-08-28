import SwiftUI

/// Heights for the app's small controls.
///
/// `AppSpacing` names gaps, radii and strokes but nothing names how tall a
/// capsule button is, so each restored screen picked its own: the same "Run"
/// chip came out 30pt in one file, 32pt in the next and 36pt in a third, and a
/// status capsule ranged from 20 to 26. These are the three that were actually
/// meant.
enum Control {
    /// A capsule the finger can hit: chips, small actions inside a card.
    static let pill: CGFloat = 32
    /// A read-only status capsule. Smaller because it is not a target.
    static let tag: CGFloat = 22
    /// The rounded glyph tile that fronts a model or capability row.
    static let tile: CGFloat = 36
    /// The same tile one step down, for rows that are secondary to their card.
    static let tileSmall: CGFloat = 32
    /// The smallest of the three: an icon well in a list row or a node header.
    static let well: CGFloat = 26
}

/// The capsule every screen's small action wears.
///
/// Split from `PillButton` because two call sites need the label without the
/// button: `PhotosPicker` and `Menu` supply their own gesture.
struct PillLabel: View {
    let title: String
    var symbol: String?
    var tint: Color = AppColors.textPrimary
    var fill: Color = AppColors.surfaceMuted
    var isOutlined = true

    var body: some View {
        HStack(spacing: Space.xs) {
            if let symbol {
                Image(systemName: symbol)
                    .glyph(Glyph.xs, weight: .semibold)
            }
            Text(title)
                .appType(.meta)
                .fontWeight(.semibold)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, Space.md)
        .frame(height: Control.pill)
        .background(Capsule().fill(fill))
        .overlay {
            if isOutlined {
                Capsule().strokeBorder(AppColors.border, lineWidth: Stroke.hairline)
            }
        }
        .contentShape(Capsule())
    }
}

struct PillButton: View {
    let title: String
    var symbol: String?
    var tint: Color = AppColors.textPrimary
    var fill: Color = AppColors.surfaceMuted
    var isOutlined = true
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            PillLabel(title: title, symbol: symbol, tint: tint, fill: fill, isOutlined: isOutlined)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
    }
}

/// The rounded glyph tile that fronts a model row, a capability card or a
/// parsed action.
struct GlyphTile: View {
    let symbol: String
    var tint: Color = AppColors.brand
    var wash: Color = AppColors.brandMuted
    var size: CGFloat = Control.tile
    var glyphSize: CGFloat = Glyph.md
    var radius: CGFloat = Radius.md

    var body: some View {
        Image(systemName: symbol)
            .glyph(glyphSize)
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(wash)
            )
    }
}

/// One word for what a screen is doing right now, said the same way on all of
/// them: a dot when the state is live, the word in the state's own colour, on a
/// wash of it.
struct StatusTag: View {
    let text: String
    let tint: Color
    var showsDot = true
    var fill: Color?

    var body: some View {
        HStack(spacing: Space.xs) {
            if showsDot {
                Circle()
                    .fill(tint)
                    .frame(width: Space.sm, height: Space.sm)
            }
            Text(text)
                .appType(.chip)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, Space.md)
        .frame(height: Control.tag)
        .background(Capsule().fill(fill ?? tint.opacity(0.12)))
    }
}

/// A titled group inside a screen.
///
/// Five of the restored screens grew a private `section(_:content:)` with the
/// same body, and a sixth wrote the header inline. This is the one they meant.
struct ScreenSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionHeader(title)
            content
        }
    }
}

/// The overline that names a group, on its own for the few places that put a
/// control on the same line.
struct SectionHeader: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .appType(.overline)
            .textCase(.uppercase)
            .foregroundStyle(AppColors.textSecondary)
    }
}
