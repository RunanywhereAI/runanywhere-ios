import SwiftUI
import RunAnywhere

struct ModelActionButton: View {
    let model: ModelInfo
    let store: ModelStore
    var expands = false

    private var progress: Double? { store.downloading[model.id] }
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
            pill("Built in", symbol: "checkmark", tint: AppColors.success, wash: AppColors.successMuted, run: nil)
        } else if isInstalled {
            pill("Installed", symbol: "checkmark", tint: AppColors.success, wash: AppColors.successMuted) {
                Task { await store.delete(model.id) }
            }
        } else {
            pill("Get", symbol: "arrow.down", tint: AppColors.brand, wash: AppColors.brandMuted) {
                Task { await store.download(model.id) }
            }
        }
    }

    private func pill(_ title: String, symbol: String, tint: Color, wash: Color, run: (() -> Void)?) -> some View {
        Button { run?() } label: {
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
        .buttonStyle(.plain)
        .disabled(run == nil)
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

            Text(model.name)
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

struct ModelTile: View {
    let model: ModelInfo
    let store: ModelStore

    private var supportsTools: Bool {
        ToolCapability.supports(id: model.id, name: model.name, downloadBytes: model.downloadSizeBytes)
            && model.category == .language
    }

    private var isVision: Bool {
        model.category == .multimodal || model.category == .vision
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(spacing: Space.xs) {
                Image(systemName: ModelOrgCatalog.org(for: model).systemImage)
                    .glyph(Glyph.xs)
                    .foregroundStyle(AppColors.textSecondary)
                Text(ModelOrgCatalog.org(for: model).displayName)
                    .appType(.overline)
                    .textCase(.uppercase)
                    .foregroundStyle(AppColors.textSecondary)
                Spacer(minLength: 0)
            }

            Text(model.name)
                .appType(.cardTitle)
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: Space.xs) {
                MetaBadge(text: model.consumerSizeLabel)
                MetaBadge(text: model.framework.consumerBackendBadgeLabel)
                if isVision {
                    CapabilityTag(symbol: "eye", title: "Vision", tint: AppColors.success)
                }
                if supportsTools {
                    CapabilityTag(symbol: "wrench.adjustable", title: "Tools", tint: AppColors.brand)
                }
            }

            Spacer(minLength: 0)

            ModelActionButton(model: model, store: store, expands: true)
        }
        .padding(Space.md)
        .frame(width: 230, height: 178, alignment: .topLeading)
        .card()
    }
}

struct OrgRow: View {
    let group: ModelOrgGroup
    let store: ModelStore

    private var installedCount: Int {
        group.models.filter { !$0.localPath.isEmpty || $0.isBuiltIn }.count
    }

    var body: some View {
        HStack(spacing: Space.md) {
            Image(systemName: group.org.systemImage)
                .glyph(Glyph.md)
                .foregroundStyle(AppColors.brand)
                .frame(width: 38, height: 38)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(AppColors.brandMuted)
                )

            VStack(alignment: .leading, spacing: Space.hair) {
                Text(group.displayName)
                    .appType(.cardTitle)
                    .foregroundStyle(AppColors.textPrimary)
                Text(subtitle)
                    .appType(.meta)
                    .foregroundStyle(AppColors.textSecondary)
            }

            Spacer(minLength: 0)

            if installedCount > 0 {
                Text("\(installedCount) ready")
                    .appType(.caption)
                    .foregroundStyle(AppColors.success)
                    .padding(.horizontal, Space.sm)
                    .frame(height: 20)
                    .background(Capsule().fill(AppColors.successMuted))
            }

            Image(systemName: "chevron.right")
                .glyph(Glyph.sm)
                .foregroundStyle(AppColors.textTertiary)
        }
        .padding(Space.md)
        .card()
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        let count = group.optionCount
        return count == 1 ? "1 model" : "\(count) models"
    }
}

struct OrgDetail: View {
    let group: ModelOrgGroup
    let store: ModelStore
    let onBack: () -> Void

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
                    Image(systemName: group.org.systemImage)
                        .glyph(Glyph.lg)
                        .foregroundStyle(AppColors.brand)
                        .frame(width: 46, height: 46)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .fill(AppColors.brandMuted)
                        )
                    VStack(alignment: .leading, spacing: Space.hair) {
                        Text(group.displayName)
                            .appType(.title)
                            .foregroundStyle(AppColors.textPrimary)
                        Text("Smaller and faster at the top, larger and smarter below.")
                            .appType(.meta)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    Spacer(minLength: 0)
                }

                ForEach(Array(group.models.enumerated()), id: \.element.id) { index, model in
                    variantRow(model, position: index, count: group.models.count)
                }
            }
            .padding(Space.lg)
            .measured()
        }
    }

    private func variantRow(_ model: ModelInfo, position: Int, count: Int) -> some View {
        HStack(spacing: Space.md) {
            VStack(alignment: .leading, spacing: Space.hair) {
                Text(model.name)
                    .appType(.cardTitle)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                Text(model.variantFeelLabel(position: position, count: count))
                    .appType(.caption)
                    .foregroundStyle(AppColors.brand)
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
