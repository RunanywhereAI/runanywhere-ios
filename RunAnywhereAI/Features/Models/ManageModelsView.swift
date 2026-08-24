import SwiftUI
import RunAnywhere

struct ManageModelsView: View {
    let store: ModelStore

    @State private var query = ""
    @State private var openOrg: ModelOrg?
    @State private var purpose: ModelPurpose?
    @State private var installedOnly = false

    private let engine = ModelRecommendationEngine()
    private let tierResolver = HardwareTierResolver()

    private var recommendation: RecommendedSelection {
        engine.recommend(
            tier: tierResolver.resolve(),
            appleFoundationAvailable: tierResolver.appleFoundationAvailable,
            from: store.raw
        )
    }

    private var filtered: [ModelInfo] {
        var models = store.raw
        if let purpose {
            models = models.filter { ModelPurpose.of($0) == purpose }
        }
        if installedOnly {
            models = models.filter { !$0.localPath.isEmpty || $0.isBuiltIn }
        }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return models }
        return models.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed)
                || $0.id.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private var availablePurposes: [ModelPurpose] {
        let present = Set(store.raw.map(ModelPurpose.of))
        return ModelPurpose.allCases.filter { present.contains($0) }
    }

    private var orgs: [ModelOrgGroup] {
        ModelOrgCatalog.groups(from: filtered)
    }

    var body: some View {
        Group {
            if store.raw.isEmpty {
                EmptyState(
                    symbol: "square.stack.3d.up.slash",
                    title: store.isRefreshing ? "Loading catalog…" : "No models in the catalog",
                    detail: store.isRefreshing
                        ? "Reading what is registered on this device."
                        : "The catalog registers on launch. Refresh to try again."
                )
            } else if let openOrg, let group = orgs.first(where: { $0.org == openOrg }) {
                OrgDetail(group: group, store: store) { self.openOrg = nil }
            } else {
                browse
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var browse: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Space.lg) {
                if let hero = recommendation.defaultChatModel ?? recommendation.recommendedLLMs.first,
                   purpose == nil, !installedOnly, query.isEmpty {
                    RecommendedHero(model: hero, store: store)
                        .padding(.horizontal, Space.lg)
                }

                controls

                if orgs.isEmpty {
                    EmptyState(
                        symbol: "magnifyingglass",
                        title: "Nothing matches",
                        detail: "Try a different filter or search term."
                    )
                } else {
                    VStack(spacing: Space.sm) {
                        ForEach(orgs) { group in
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) { openOrg = group.org }
                            } label: {
                                OrgRow(group: group, store: store)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, Space.lg)
                }
            }
            .padding(.vertical, Space.lg)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            searchField

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.xs) {
                    filterChip(
                        title: "All",
                        symbol: "square.grid.2x2",
                        isActive: purpose == nil
                    ) { purpose = nil }

                    ForEach(availablePurposes) { item in
                        filterChip(
                            title: item.title,
                            symbol: item.symbol,
                            isActive: purpose == item
                        ) { purpose = purpose == item ? nil : item }
                    }

                    Divider().frame(height: 18)

                    filterChip(
                        title: "Installed",
                        symbol: "checkmark.circle",
                        isActive: installedOnly
                    ) { installedOnly.toggle() }
                }
                .padding(.horizontal, Space.lg)
            }
        }
    }

    private func filterChip(title: String, symbol: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { action() }
        } label: {
            HStack(spacing: Space.xs) {
                Image(systemName: symbol)
                    .glyph(Glyph.xs)
                Text(title)
                    .appType(.meta)
            }
            .foregroundStyle(isActive ? AppColors.onBrand : AppColors.textSecondary)
            .padding(.horizontal, Space.md)
            .frame(height: 28)
            .background(Capsule().fill(isActive ? AppColors.brandSelected : AppColors.surfaceMuted))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var searchField: some View {
        HStack(spacing: Space.sm) {
            Image(systemName: "magnifyingglass")
                .glyph(Glyph.sm)
                .foregroundStyle(AppColors.textSecondary)
            TextField("Search models", text: $query)
                .textFieldStyle(.plain)
                .appType(.secondary)
                .foregroundStyle(AppColors.textPrimary)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .glyph(Glyph.sm)
                        .foregroundStyle(AppColors.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Space.md)
        .frame(height: 34)
        .background(Capsule().fill(AppColors.surfaceMuted))
        .padding(.horizontal, Space.lg)
    }
}
