import SwiftUI

/// The hub for everything outside chat, models and settings.
///
/// A grid rather than a list: these are destinations you pick between, not a
/// sequence you read down, and a caption under each one is what stops the
/// diagnostic screens looking interchangeable.
struct MoreScreen: View {
    @Environment(AppSettings.self) private var settings

    @Binding var destination: MoreDestination?

    private var groups: [MoreDestination.Group] {
        let available = MoreDestination.available(for: settings.mode)
        return MoreDestination.Group.allCases.filter { group in
            available.contains { $0.group == group }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                ForEach(groups) { group in
                    section(group)
                }

                if settings.mode == .user {
                    developerHint
                }
            }
            .padding(.horizontal, Space.lg)
            .padding(.vertical, Space.xl)
            .measured()
        }
        .background(AppColors.background)
    }

    private func section(_ group: MoreDestination.Group) -> some View {
        let items = MoreDestination.available(for: settings.mode).filter { $0.group == group }
        return VStack(alignment: .leading, spacing: Space.md) {
            Text(group.title)
                .appType(.overline)
                .textCase(.uppercase)
                .foregroundStyle(AppColors.textSecondary)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 240), spacing: Space.md)],
                spacing: Space.md
            ) {
                ForEach(items) { item in
                    tile(item)
                }
            }
        }
    }

    private func tile(_ item: MoreDestination) -> some View {
        Button {
            withAnimation(Motion.quick) { destination = item }
        } label: {
            HStack(alignment: .top, spacing: Space.md) {
                GlyphTile(symbol: item.symbol, tint: AppColors.accent, wash: AppColors.accentMuted)

                VStack(alignment: .leading, spacing: Space.hair) {
                    Text(item.title)
                        .appType(.cardTitle)
                        .foregroundStyle(AppColors.textPrimary)
                    Text(item.caption)
                        .appType(.meta)
                        .foregroundStyle(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)
            }
            .padding(Space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var developerHint: some View {
        HStack(spacing: Space.sm) {
            Image(systemName: "hammer")
                .glyph(Glyph.xs)
                .foregroundStyle(AppColors.textTertiary)
            Text("More tools are available in developer mode, in Settings.")
                .appType(.meta)
                .foregroundStyle(AppColors.textTertiary)
            Spacer(minLength: 0)
        }
        .padding(.top, Space.sm)
    }
}
