import SwiftUI

struct ComposerStrip<Trailing: View>: View {
    let symbol: String
    let tint: Color
    let wash: Color
    let title: String
    var detail: String?
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: Space.sm) {
            Image(systemName: symbol)
                .glyph(Glyph.xs)
                .foregroundStyle(tint)
                .frame(width: Glyph.lg)

            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .appType(.meta)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                if let detail {
                    Text(detail)
                        .appType(.caption)
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: Space.sm)

            trailing
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(wash)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(tint.opacity(0.35), lineWidth: Stroke.hairline)
        )
    }
}

struct StripButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .glyph(Glyph.xs)
                .foregroundStyle(AppColors.textSecondary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

extension AnyTransition {
    static var composerStrip: AnyTransition {
        .move(edge: .bottom).combined(with: .opacity)
    }
}
