import SwiftUI
import RunAnywhere

struct SettingsScreen: View {
    let settings: AppSettings
    let defaults: DefaultModels
    let store: ModelStore
    let onManageModels: () -> Void

    @State private var picking: ModelPurpose?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                section("Appearance") {
                    HStack(spacing: Space.xs) {
                        ForEach(AppTheme.allCases) { theme in
                            themeChip(theme)
                        }
                        Spacer(minLength: 0)
                    }
                }

                section("Default models") {
                    VStack(spacing: Space.sm) {
                        defaultRow(
                            purpose: .textToSpeech,
                            title: "Speech",
                            detail: "Used when you tap Speak on a reply",
                            current: defaults.ttsID
                        )
                        defaultRow(
                            purpose: .speechToText,
                            title: "Dictation",
                            detail: "Used by the microphone in the composer",
                            current: defaults.sttID
                        )
                        defaultRow(
                            purpose: .embedding,
                            title: "Documents",
                            detail: "Indexes an attached file so you can ask about it",
                            current: defaults.embeddingID
                        )
                        defaultRow(
                            purpose: .vision,
                            title: "Images",
                            detail: "Answers questions about a photo you attach",
                            current: defaults.visionID
                        )
                    }
                }

                section("Storage") {
                    VStack(alignment: .leading, spacing: Space.md) {
                        HStack(spacing: Space.xl) {
                            metric("Models", value: AppSettings.format(settings.usedBytes))
                            metric("Free", value: AppSettings.format(settings.freeBytes))
                            metric("Installed", value: "\(store.installed.count)")
                            Spacer(minLength: 0)
                        }

                        Button {
                            Task { await settings.clearCache() }
                        } label: {
                            HStack(spacing: Space.xs) {
                                Image(systemName: "trash")
                                    .glyph(Glyph.xs, weight: .semibold)
                                Text(settings.isBusy ? "Clearing…" : "Clear cache and temporary files")
                                    .appType(.meta)
                            }
                            .foregroundStyle(AppColors.danger)
                            .padding(.horizontal, Space.md)
                            .frame(height: 32)
                            .background(Capsule().fill(AppColors.dangerMuted))
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(settings.isBusy)
                    }
                    .padding(Space.md)
                    .card()
                }
            }
            .padding(Space.lg)
            .measured()
        }
        .task { await settings.refreshStorage() }
        .modelPicker(
            isPresented: Binding(get: { picking != nil }, set: { if !$0 { picking = nil } }),
            models: candidates,
            activeID: activeID,
            onSelect: assign,
            onManage: onManageModels
        )
    }

    private var candidates: [InstalledModel] {
        guard let picking else { return [] }
        return store.installed.filter { $0.purpose == picking }
    }

    private var activeID: String? {
        switch picking {
        case .textToSpeech: defaults.ttsID
        case .speechToText: defaults.sttID
        case .embedding: defaults.embeddingID
        case .vision: defaults.visionID
        default: nil
        }
    }

    private func assign(_ model: InstalledModel) {
        switch picking {
        case .textToSpeech:
            defaults.ttsID = model.id
            Task { await defaults.ensureLoaded(model.id, category: .speechSynthesis) }
        case .speechToText:
            defaults.sttID = model.id
            Task { await defaults.ensureLoaded(model.id, category: .speechRecognition) }
        case .embedding:
            // Not loaded here: `rag.open` loads the embedding model itself, and
            // loading it eagerly holds memory for a document that may never be
            // attached.
            defaults.embeddingID = model.id
        case .vision:
            defaults.visionID = model.id
        default:
            break
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(title)
                .appType(.overline)
                .textCase(.uppercase)
                .foregroundStyle(AppColors.textSecondary)
            content()
        }
    }

    private func themeChip(_ theme: AppTheme) -> some View {
        let isActive = settings.theme == theme
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { settings.theme = theme }
        } label: {
            HStack(spacing: Space.xs) {
                Image(systemName: theme.symbol)
                    .glyph(Glyph.xs)
                Text(theme.title)
                    .appType(.meta)
            }
            .foregroundStyle(isActive ? AppColors.onBrand : AppColors.textSecondary)
            .padding(.horizontal, Space.md)
            .frame(height: 32)
            .background(Capsule().fill(isActive ? AppColors.brandSelected : AppColors.surfaceMuted))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func defaultRow(purpose: ModelPurpose, title: String, detail: String, current: String?) -> some View {
        let model = store.models.first { $0.id == current }
        return Button {
            picking = purpose
        } label: {
            HStack(spacing: Space.md) {
                Image(systemName: purpose.symbol)
                    .glyph(Glyph.md)
                    .foregroundStyle(AppColors.brand)
                    .frame(width: 36, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(AppColors.brandMuted)
                    )

                VStack(alignment: .leading, spacing: Space.hair) {
                    Text(title)
                        .appType(.cardTitle)
                        .foregroundStyle(AppColors.textPrimary)
                    Text(model?.name ?? detail)
                        .appType(.meta)
                        .foregroundStyle(model == nil ? AppColors.textSecondary : AppColors.textPrimary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Text(model == nil ? "Choose" : "Change")
                    .appType(.meta)
                    .foregroundStyle(AppColors.brand)

                Image(systemName: "chevron.right")
                    .glyph(Glyph.sm)
                    .foregroundStyle(AppColors.textTertiary)
            }
            .padding(Space.md)
            .card()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func metric(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: Space.hair) {
            Text(value)
                .appType(.sectionTitle)
                .monospacedDigit()
                .foregroundStyle(AppColors.textPrimary)
            Text(label)
                .appType(.caption)
                .foregroundStyle(AppColors.textSecondary)
        }
    }
}
