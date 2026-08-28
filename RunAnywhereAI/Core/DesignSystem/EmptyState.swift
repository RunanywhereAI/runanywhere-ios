import SwiftUI

struct EmptyState: View {
    let symbol: String
    let title: String
    let detail: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: Space.md) {
            Image(systemName: symbol)
                .glyph(Glyph.hero, weight: .light)
                .foregroundStyle(AppColors.textTertiary)
                .frame(width: 56, height: 56)
                .background(Circle().fill(AppColors.surfaceMuted))

            VStack(spacing: Space.xs) {
                Text(title)
                    .appType(.cardTitle)
                    .foregroundStyle(AppColors.textPrimary)
                    .multilineTextAlignment(.center)

                Text(detail)
                    .appType(.meta)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 240)

            if let actionTitle, let action {
                Button(action: action) {
                    HStack(spacing: Space.xs) {
                        Image(systemName: "plus")
                            .glyph(Glyph.xs, weight: .semibold)
                        Text(actionTitle)
                            .appType(.secondary)
                    }
                    .foregroundStyle(AppColors.brand)
                    .padding(.horizontal, Space.lg)
                    .frame(height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .fill(AppColors.brandMuted)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .strokeBorder(
                                AppColors.brand.opacity(0.55),
                                style: StrokeStyle(lineWidth: Stroke.regular, dash: [4, 3])
                            )
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.xxl)
    }
}
