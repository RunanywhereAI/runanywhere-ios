import SwiftUI
import RunAnywhere

struct ModelActionButton: View {
    let model: ModelInfo
    let store: ModelStore
    var expands = false

    private var progress: Double? { store.downloading[model.id] }
    @State private var confirmingRemoval = false
    private var isInstalled: Bool { !model.localPath.isEmpty || model.isBuiltIn }

    var body: some View {
        if let progress {
            HStack(spacing: Space.xs) {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(AppColors.brand)
                Text("\(Int(progress * 100))%")
                    .appType(.caption)
                    .monospacedDigit()
                    .foregroundStyle(AppColors.textSecondary)
            }
            .frame(maxWidth: expands ? .infinity : 130)
        } else if model.isBuiltIn {
            // "Built in" with a green tick claimed Apple's model was ready to
            // use on machines where the framework refuses it, so choosing it
            // failed with nothing on screen explaining why. The runtime's own
            // reason is the only thing that can answer that.
            if let reason = builtInUnavailableReason {
                pillLabel("Unavailable", symbol: "exclamationmark.triangle.fill",
                          tint: AppColors.warning, wash: AppColors.warningMuted)
                    .help(reason)
            } else {
                pill("Built in", symbol: "checkmark", tint: AppColors.success, wash: AppColors.successMuted, run: nil)
            }
        } else if isInstalled {
            // A status, not a button. This used to delete the model on tap:
            // a green checkmark reading "Installed" is the last thing anyone
            // expects to destroy a multi-gigabyte download, and it did it with
            // no confirmation. Removal now lives behind a menu, with the same
            // confirmation Settings already uses.
            Menu {
                Button("Remove from this device", systemImage: "trash", role: .destructive) {
                    confirmingRemoval = true
                }
            } label: {
                pillLabel("Installed", symbol: "checkmark", tint: AppColors.success,
                          wash: AppColors.successMuted)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .confirmationDialog(
                "Remove \(store.label(for: model))?",
                isPresented: $confirmingRemoval,
                titleVisibility: .visible
            ) {
                Button("Remove", role: .destructive) {
                    Task { await store.delete(model.id) }
                }
                Button("Keep", role: .cancel) {}
            } message: {
                Text("It stays in the catalog, so you can download it again.")
            }
        } else {
            pill("Get", symbol: "arrow.down", tint: AppColors.brand, wash: AppColors.brandMuted) {
                Task { await store.download(model.id) }
            }
        }
    }

    private var builtInUnavailableReason: String? {
        Self.builtInUnavailableReason(for: model)
    }

    static func builtInUnavailableReason(for model: ModelInfo) -> String? {
        model.runtimeUnavailableReason
    }

    private func pill(_ title: String, symbol: String, tint: Color, wash: Color, run: (() -> Void)?) -> some View {
        Button { run?() } label: {
            pillLabel(title, symbol: symbol, tint: tint, wash: wash)
        }
        .buttonStyle(.plain)
        .disabled(run == nil)
    }

    private func pillLabel(_ title: String, symbol: String, tint: Color, wash: Color) -> some View {
        HStack(spacing: Space.xs) {
            Image(systemName: symbol)
                .glyph(Glyph.xs, weight: .semibold)
            Text(title)
                .appType(.meta)
        }
        .foregroundStyle(tint)
        .frame(maxWidth: expands ? .infinity : nil)
        .padding(.horizontal, Space.md)
        .frame(height: 30)
        .background(Capsule().fill(wash))
        .contentShape(Capsule())
    }
}

struct RecommendedHero: View {
    let model: ModelInfo
    let store: ModelStore

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack(spacing: Space.sm) {
                Image(systemName: "sparkles")
                    .glyph(Glyph.sm, weight: .semibold)
                    .foregroundStyle(AppColors.brand)
                Text("Best for this device")
                    .appType(.overline)
                    .textCase(.uppercase)
                    .foregroundStyle(AppColors.brand)
                Spacer(minLength: 0)
            }

            Text(store.label(for: model))
                .appType(.title)
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Space.xs) {
                MetaBadge(text: ModelOrgCatalog.org(for: model).displayName)
                MetaBadge(text: model.consumerSizeLabel)
                MetaBadge(text: model.framework.consumerBackendBadgeLabel)
            }

            ModelActionButton(model: model, store: store, expands: true)
        }
        .padding(Space.lg)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(AppColors.brandMuted)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(AppColors.brand.opacity(0.35), lineWidth: Stroke.hairline)
        )
    }
}

struct MetaBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .appType(.caption)
            .foregroundStyle(AppColors.textSecondary)
            .padding(.horizontal, Space.sm)
            .frame(height: 20)
            .background(Capsule().fill(AppColors.surface.opacity(0.7)))
    }
}

/// How many of a publisher's models are already on the device.
struct ReadyCountBadge: View {
    let count: Int

    var body: some View {
        Text("\(count) ready")
            .appType(.caption)
            .foregroundStyle(AppColors.success)
            .padding(.horizontal, Space.sm)
            .frame(height: 20)
            .background(Capsule().fill(AppColors.successMuted))
    }
}

/// A model as a card, for the grid layout. Width comes from the column it lands
/// in, so nothing inside it is fixed: the name wraps, the tags wrap after it,
/// and the action sits on the floor of whatever height the row settles at.
struct ModelTile: View {
    let model: ModelInfo
    let store: ModelStore
    /// Where the model stands in its shortlist, when it came from one. Nil in
    /// the developer catalog, where the publisher leads the card instead.
    var standing: ModelStanding?

    private var isRecommended: Bool { standing == .recommended }

    private var supportsTools: Bool {
        ToolCapability.supports(id: model.id, name: model.name, downloadBytes: model.downloadSizeBytes)
            && model.category == .language
    }

    private var isVision: Bool {
        model.category == .multimodal || model.category == .vision
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            overline

            Text(store.label(for: model))
                .appType(.cardTitle)
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            WrapLayout {
                MetaBadge(text: model.consumerSizeLabel)
                if standing == nil {
                    MetaBadge(text: model.framework.consumerBackendBadgeLabel)
                }
                if isVision {
                    CapabilityTag(symbol: "eye", title: "Vision", tint: AppColors.success)
                }
                if model.supportsThinking {
                    CapabilityTag(symbol: "brain", title: "Thinking", tint: AppColors.info)
                }
                if supportsTools {
                    CapabilityTag(symbol: "wrench.adjustable", title: "Tools", tint: AppColors.brand)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            ModelActionButton(model: model, store: store, expands: true)
        }
        .padding(Space.md)
        .frame(maxWidth: .infinity, alignment: .topLeading)
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

    @ViewBuilder
    private var overline: some View {
        if store.isDefault(model) {
            // Ahead of the shortlist standing, which answers a different
            // question: how this row compares with its neighbours, not whether
            // it is the one the app will actually reach for.
            HStack(spacing: Space.xs) {
                Image(systemName: "checkmark.seal.fill")
                    .glyph(Glyph.xs, weight: .semibold)
                Text("Default")
                    .appType(.overline)
                    .textCase(.uppercase)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(AppColors.brand)
            .accessibilityLabel("The model this app uses for \(ModelPurpose.of(model).title)")
        } else if let standing {
            HStack(spacing: Space.xs) {
                Image(systemName: standing.symbol)
                    .glyph(Glyph.xs, weight: .semibold)
                Text(standing.shortLabel)
                    .appType(.overline)
                    .textCase(.uppercase)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isRecommended ? AppColors.brand : AppColors.textSecondary)
            .accessibilityLabel(standing.label)
        } else {
            HStack(spacing: Space.xs) {
                Image(systemName: ModelOrgCatalog.org(for: model).systemImage)
                    .glyph(Glyph.xs)
                Text(ModelOrgCatalog.org(for: model).displayName)
                    .appType(.overline)
                    .textCase(.uppercase)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(AppColors.textSecondary)
        }
    }
}

/// A model as a row: the name, one line of context, the badges and the action
/// on the right. The developer catalog's counterpart to `CuratedModelRow`.
struct CatalogModelRow: View {
    let model: ModelInfo
    let store: ModelStore
    /// The line under the name — where the model sits among a publisher's other
    /// sizes, or who published it when the section is a category.
    let caption: String
    var captionTint: Color = AppColors.textSecondary

    var body: some View {
        HStack(spacing: Space.md) {
            VStack(alignment: .leading, spacing: Space.hair) {
                Text(store.label(for: model))
                    .appType(.cardTitle)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                Text(caption)
                    .appType(.caption)
                    .foregroundStyle(captionTint)
                HStack(spacing: Space.xs) {
                    MetaBadge(text: model.consumerSizeLabel)
                    MetaBadge(text: model.framework.consumerBackendBadgeLabel)
                    if model.category == .multimodal || model.category == .vision {
                        CapabilityTag(symbol: "eye", title: "Vision", tint: AppColors.success)
                    }
                    if model.category == .language,
                       ToolCapability.supports(
                           id: model.id,
                           name: model.name,
                           downloadBytes: model.downloadSizeBytes
                       ) {
                        CapabilityTag(symbol: "wrench.adjustable", title: "Tools", tint: AppColors.brand)
                    }
                }
            }

            Spacer(minLength: Space.sm)

            ModelActionButton(model: model, store: store)
        }
        .padding(Space.md)
        .card()
    }
}

struct OrgRow: View {
    let group: ModelOrgGroup
    let store: ModelStore

    var body: some View {
        HStack(spacing: Space.md) {
            GlyphTile(symbol: group.org.systemImage)

            VStack(alignment: .leading, spacing: Space.hair) {
                Text(group.displayName)
                    .appType(.cardTitle)
                    .foregroundStyle(AppColors.textPrimary)
                Text(group.modelCountLabel)
                    .appType(.meta)
                    .foregroundStyle(AppColors.textSecondary)
            }

            Spacer(minLength: 0)

            if group.installedCount > 0 {
                ReadyCountBadge(count: group.installedCount)
            }

            Image(systemName: "chevron.right")
                .glyph(Glyph.sm)
                .foregroundStyle(AppColors.textTertiary)
        }
        .padding(Space.md)
        .card()
        .contentShape(Rectangle())
    }
}

/// A publisher as a card, so the index reflows with everything else when the
/// reader asks for a grid.
struct OrgTile: View {
    let group: ModelOrgGroup

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(spacing: Space.sm) {
                GlyphTile(
                    symbol: group.org.systemImage,
                    size: Control.tileSmall,
                    glyphSize: Glyph.sm,
                    radius: Radius.sm
                )
                Spacer(minLength: 0)
                if group.installedCount > 0 {
                    ReadyCountBadge(count: group.installedCount)
                }
            }

            Text(group.displayName)
                .appType(.cardTitle)
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(group.modelCountLabel)
                .appType(.meta)
                .foregroundStyle(AppColors.textSecondary)

            Spacer(minLength: 0)
        }
        .padding(Space.md)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .card()
        .contentShape(Rectangle())
    }
}

extension ModelOrgGroup {
    var installedCount: Int {
        models.filter { !$0.localPath.isEmpty || $0.isBuiltIn }.count
    }

    var modelCountLabel: String {
        optionCount == 1 ? "1 model" : "\(optionCount) models"
    }
}

struct OrgDetail: View {
    let group: ModelOrgGroup
    let store: ModelStore
    let onBack: () -> Void

    @Bindable private var preferences = ModelBrowsePreferences.shared

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Space.md) {
                Button(action: onBack) {
                    HStack(spacing: Space.xs) {
                        Image(systemName: "chevron.left")
                            .glyph(Glyph.sm, weight: .semibold)
                        Text("All publishers")
                            .appType(.secondary)
                    }
                    .foregroundStyle(AppColors.brand)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                HStack(spacing: Space.md) {
                    GlyphTile(symbol: group.org.systemImage, glyphSize: Glyph.lg)
                    VStack(alignment: .leading, spacing: Space.hair) {
                        Text(group.displayName)
                            .appType(.title)
                            .foregroundStyle(AppColors.textPrimary)
                        Text("Smaller and faster at the top, larger and smarter below.")
                            .appType(.meta)
                            .foregroundStyle(AppColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: Space.sm)
                    ViewOptionControl(selection: $preferences.layout, showsTitles: false)
                }

                switch preferences.layout {
                case .list:
                    ForEach(Array(group.models.enumerated()), id: \.element.id) { index, model in
                        CatalogModelRow(
                            model: model,
                            store: store,
                            caption: model.variantFeelLabel(position: index, count: group.models.count),
                            captionTint: AppColors.brand
                        )
                    }
                case .grid:
                    ModelCardGrid(items: group.models, id: \.id) { model in
                        ModelTile(model: model, store: store)
                    }
                }
            }
            .padding(Space.lg)
            .measured()
        }
    }
}
