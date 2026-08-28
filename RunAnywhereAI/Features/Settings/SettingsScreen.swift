import SwiftUI
import RunAnywhere

/// Settings is the only screen a user in either mode always has, so it carries
/// everything a consumer is allowed to reach: appearance, the mode switch,
/// which model each job uses, what the models are costing on disk, and — on
/// Mac — sharing them with a phone. Developer mode appends one section for the
/// things a builder needs and a reader would only find confusing.
struct SettingsScreen: View {
    @Bindable var settings: AppSettings
    let defaults: DefaultModels
    let store: ModelStore
    let onManageModels: () -> Void
    let onOpenConnect: () -> Void
    let onOpenDeveloperTools: () -> Void

    @State private var picking: ModelPurpose?
    @State private var storage = StorageViewModel()
    @State private var pendingDelete: StoredModel?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                ScreenSection(title: "Appearance") { appearance }

                ScreenSection(title: "Mode") { modeToggle }

                // Which model answers which modality is plumbing: in user mode
                // the recommendation engine picks per device, and a reader who
                // never chose a speech or embedding model has nothing to say
                // about one. Developer mode still overrides it.
                if settings.mode == .developer {
                    ScreenSection(title: "Default models") { defaultModels }
                }

                #if os(macOS)
                ScreenSection(title: "Connect") { connect }
                #endif

                ScreenSection(title: "Storage") { storageCard }

                if settings.mode == .developer {
                    ScreenSection(title: "Developer") { developer }
                }
            }
            .padding(Space.lg)
            .measured()
        }
        .task { await storage.refresh(store: store) }
        .confirmationDialog(
            pendingDelete.map { "Delete \($0.name)?" } ?? "",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            if let pendingDelete {
                Button("Delete and free \(pendingDelete.sizeLabel)", role: .destructive) {
                    Task { await storage.delete(pendingDelete, store: store) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The files come off the disk. You can download the model again later.")
        }
        .modelPicker(
            isPresented: Binding(get: { picking != nil }, set: { if !$0 { picking = nil } }),
            models: candidates,
            activeID: activeID,
            onSelect: assign,
            onManage: onManageModels
        )
    }

    // MARK: - Appearance

    private var appearance: some View {
        HStack(spacing: Space.xs) {
            ForEach(AppTheme.allCases) { theme in
                themeChip(theme)
            }
            Spacer(minLength: 0)
        }
    }

    private func themeChip(_ theme: AppTheme) -> some View {
        let isActive = settings.theme == theme
        return Button {
            withAnimation(Motion.fade) { settings.theme = theme }
        } label: {
            HStack(spacing: Space.xs) {
                Image(systemName: theme.symbol)
                    .glyph(Glyph.xs)
                Text(theme.title)
                    .appType(.meta)
            }
            .foregroundStyle(isActive ? AppColors.onBrand : AppColors.textSecondary)
            .padding(.horizontal, Space.md)
            .frame(height: Control.pill)
            .background(Capsule().fill(isActive ? AppColors.brandSelected : AppColors.surfaceMuted))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Mode

    /// A two-state switch rather than a picker: there are two modes and the
    /// difference is visible the moment it moves, so a label per option would
    /// be saying twice what the colour already says. It stays in both modes —
    /// hide it in user mode and a developer build has no way back out.
    private var modeToggle: some View {
        HStack(alignment: .top, spacing: Space.sm) {
            GlyphTile(
                symbol: settings.mode.symbol,
                tint: AppColors.accent,
                wash: AppColors.accentMuted,
                size: Control.tileSmall,
                glyphSize: Glyph.sm,
                radius: Radius.sm
            )

            VStack(alignment: .leading, spacing: Space.hair) {
                Text("Developer mode")
                    .appType(.cardTitle)
                    .foregroundStyle(AppColors.textPrimary)
                Text(settings.mode.caption)
                    .appType(.meta)
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: Space.sm)

            Toggle(
                "",
                isOn: Binding(
                    get: { settings.mode == .developer },
                    set: { isOn in
                        withAnimation(Motion.fade) {
                            settings.mode = isOn ? .developer : .user
                        }
                    }
                )
            )
            .labelsHidden()
            .tint(AppColors.accent)
        }
        .padding(Space.md)
        .card()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Developer mode, \(settings.mode.title)")
    }

    // MARK: - Default models

    private var defaultModels: some View {
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

    private func defaultRow(purpose: ModelPurpose, title: String, detail: String, current: String?) -> some View {
        let model = store.models.first { $0.id == current }
        return Button {
            picking = purpose
        } label: {
            HStack(spacing: Space.md) {
                GlyphTile(symbol: purpose.symbol)

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

    // MARK: - Connect

    #if os(macOS)
    private var connect: some View {
        linkRow(
            symbol: "antenna.radiowaves.left.and.right",
            title: "Share with your devices",
            detail: "Serve a model on this Mac to an iPhone, iPad or Android on the same network",
            action: onOpenConnect
        )
    }
    #endif

    // MARK: - Storage

    /// The consumer's only view of what the models cost, so it has to stand on
    /// its own: what is used, what is left, and a way to remove any one of
    /// them. The Storage screen in the developer hub adds temp-file cleanup on
    /// top of this and is not needed to keep a disk under control.
    private var storageCard: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack(spacing: Space.xl) {
                metric("Models", value: AppSettings.format(storage.usedBytes))
                metric("Free", value: AppSettings.format(storage.freeBytes))
                metric("Downloaded", value: "\(storage.models.count)")
                Spacer(minLength: 0)
            }

            ProgressView(value: storage.usedFraction)
                .progressViewStyle(.linear)
                .tint(AppColors.brand)

            if storage.models.isEmpty {
                Text(storage.isLoading
                    ? "Adding up what the models are holding."
                    : "Nothing downloaded yet. Models you get from Manage Models show up here.")
                    .appType(.meta)
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 0) {
                    ForEach(storage.models) { stored in
                        Divider().overlay(AppColors.border)
                        storedRow(stored)
                    }
                }
            }

            Divider().overlay(AppColors.border)

            PillButton(
                title: storage.isBusy ? "Clearing…" : "Clear cache and temporary files",
                symbol: "trash",
                tint: AppColors.danger,
                fill: AppColors.dangerMuted,
                isOutlined: false,
                isEnabled: !storage.isBusy
            ) {
                Task {
                    await storage.clearCache(store: store)
                    await storage.cleanTempFiles(store: store)
                }
            }

            if let error = storage.lastError {
                Text(error)
                    .appType(.meta)
                    .foregroundStyle(AppColors.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Space.md)
        .card()
    }

    private func storedRow(_ stored: StoredModel) -> some View {
        HStack(spacing: Space.md) {
            VStack(alignment: .leading, spacing: Space.hair) {
                Text(stored.name)
                    .appType(.cardTitle)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                Text(stored.kind)
                    .appType(.meta)
                    .foregroundStyle(AppColors.textSecondary)
            }

            Spacer(minLength: Space.sm)

            Text(stored.sizeLabel)
                .appType(.meta)
                .monospacedDigit()
                .foregroundStyle(AppColors.textSecondary)

            Button {
                pendingDelete = stored
            } label: {
                Image(systemName: "trash")
                    .glyph(Glyph.sm, weight: .semibold)
                    .foregroundStyle(AppColors.danger)
                    .frame(width: Control.pill, height: Control.pill)
                    .background(Circle().fill(AppColors.dangerMuted))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(storage.isBusy)
            .opacity(storage.activity == .deleting(stored.id) ? 0.4 : 1)
            .accessibilityLabel("Delete \(stored.name)")
        }
        .padding(.vertical, Space.sm)
    }

    // MARK: - Developer

    private var developer: some View {
        VStack(spacing: Space.sm) {
            linkRow(
                symbol: "square.grid.2x2",
                title: "SDK screens",
                detail: "Voice, vision, agents and benchmarks, one screen per modality",
                action: onOpenDeveloperTools
            )

            HStack(spacing: Space.xl) {
                metric("Version", value: Self.version)
                metric("Models in catalog", value: "\(store.models.count)")
                Spacer(minLength: 0)
            }
            .padding(Space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        guard let build = info?["CFBundleVersion"] as? String, build != short else { return short }
        return "\(short) (\(build))"
    }

    // MARK: - Chrome

    private func linkRow(
        symbol: String,
        title: String,
        detail: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Space.md) {
                GlyphTile(symbol: symbol, tint: AppColors.accent, wash: AppColors.accentMuted)

                VStack(alignment: .leading, spacing: Space.hair) {
                    Text(title)
                        .appType(.cardTitle)
                        .foregroundStyle(AppColors.textPrimary)
                    Text(detail)
                        .appType(.meta)
                        .foregroundStyle(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: Space.sm)

                Image(systemName: "chevron.right")
                    .glyph(Glyph.sm)
                    .foregroundStyle(AppColors.textTertiary)
            }
            .padding(Space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
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
