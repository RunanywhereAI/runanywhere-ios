import SwiftUI
import RunAnywhere

/// The consumer face of the catalog: five models per modality, the middle one
/// picked for this device. Developer mode gets the unfiltered browse instead.
///
/// How it is drawn is the reader's call, not ours — a column or a grid of
/// cards, sectioned by what a model does or by who made it — and the choice
/// outlives the launch.
struct CuratedModelsView: View {
    let shortlists: [CuratedModels]
    let store: ModelStore

    @Bindable private var preferences = ModelBrowsePreferences.shared

    private var groups: [CuratedGroup] {
        ModelCuration.groups(from: shortlists, by: preferences.grouping)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Space.xl) {
                ModelViewOptions(preferences: preferences)

                ForEach(groups) { group in
                    CuratedModelSection(group: group, layout: preferences.layout, store: store)
                }
            }
            .padding(.horizontal, Space.lg)
            .padding(.vertical, Space.lg)
            .measured()
        }
    }
}

struct CuratedModelSection: View {
    let group: CuratedGroup
    let layout: ModelLayout
    let store: ModelStore

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack(spacing: Space.sm) {
                Image(systemName: group.symbol)
                    .glyph(Glyph.sm, weight: .semibold)
                    .foregroundStyle(AppColors.brand)
                Text(group.title)
                    .appType(.sectionTitle)
                    .foregroundStyle(AppColors.textPrimary)
                Spacer(minLength: 0)
            }

            switch layout {
            case .list:
                VStack(spacing: Space.sm) {
                    ForEach(group.entries) { entry in
                        CuratedModelRow(
                            model: entry.model,
                            standing: entry.standing,
                            store: store
                        )
                    }
                }
            case .grid:
                ModelCardGrid(items: group.entries, id: \.id) { entry in
                    ModelTile(model: entry.model, store: store, standing: entry.standing)
                }
            }
        }
    }
}

struct CuratedModelRow: View {
    let model: ModelInfo
    let standing: ModelStanding
    let store: ModelStore

    private var isRecommended: Bool { standing == .recommended }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(spacing: Space.sm) {
                Image(systemName: standing.symbol)
                    .glyph(Glyph.xs, weight: .semibold)
                Text(standing.label)
                    .appType(.overline)
                    .textCase(.uppercase)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isRecommended ? AppColors.brand : AppColors.textSecondary)

            Text(store.label(for: model))
                .appType(.cardTitle)
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: Space.xs) {
                MetaBadge(text: model.consumerSizeLabel)
                if model.category == .multimodal || model.category == .vision {
                    CapabilityTag(symbol: "eye", title: "Vision", tint: AppColors.success)
                }
                if model.supportsThinking {
                    CapabilityTag(symbol: "brain", title: "Thinking", tint: AppColors.info)
                }
                Spacer(minLength: Space.sm)
                ModelActionButton(model: model, store: store)
            }
        }
        .padding(Space.md)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(isRecommended ? AppColors.brandMuted : AppColors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(
                    isRecommended ? AppColors.brand.opacity(0.35) : AppColors.border,
                    lineWidth: Stroke.hairline
                )
        )
    }
}
