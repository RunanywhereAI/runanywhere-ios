import SwiftUI

struct StorageScreen: View {
    @Environment(ModelStore.self) private var store
    @State private var model = StorageViewModel()
    @State private var pendingDelete: StoredModel?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                ScreenSection(title: "On this device") { summary }

                ScreenSection(title: "Downloaded models") { downloaded }

                ScreenSection(title: "Reclaim space") { maintenance }

                if let error = model.lastError {
                    Text(error)
                        .appType(.meta)
                        .foregroundStyle(AppColors.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(Space.lg)
            .measured()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background)
        .task { await model.refresh(store: store) }
        .confirmationDialog(
            pendingDelete.map { "Delete \($0.name)?" } ?? "",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            if let pendingDelete {
                Button("Delete and free \(pendingDelete.sizeLabel)", role: .destructive) {
                    Task { await model.delete(pendingDelete, store: store) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The files come off the disk. You can download the model again later.")
        }
    }

    // MARK: - Summary

    private var summary: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack(spacing: Space.xl) {
                metric("Models", value: AppSettings.format(model.usedBytes))
                metric("Free", value: AppSettings.format(model.freeBytes))
                metric("Downloaded", value: "\(model.models.count)")
                Spacer(minLength: 0)
            }

            ProgressView(value: model.usedFraction)
                .progressViewStyle(.linear)
                .tint(AppColors.brand)

            Text(capacityCaption)
                .appType(.caption)
                .foregroundStyle(AppColors.textSecondary)
        }
        .padding(Space.md)
        .card()
    }

    private var capacityCaption: String {
        guard model.capacityBytes > 0 else { return "Reading the disk…" }
        return "\(AppSettings.format(model.usedBytes)) of \(AppSettings.format(model.capacityBytes)) available space"
    }

    // MARK: - Model list

    @ViewBuilder
    private var downloaded: some View {
        if model.models.isEmpty {
            EmptyState(
                symbol: "internaldrive",
                title: model.isLoading ? "Reading storage…" : "Nothing downloaded",
                detail: model.isLoading
                    ? "Adding up what the models are holding."
                    : "Models you download from Manage Models show up here with what they cost."
            )
            .card()
        } else {
            VStack(spacing: Space.sm) {
                ForEach(model.models) { stored in
                    row(stored)
                }
            }
        }
    }

    private func row(_ stored: StoredModel) -> some View {
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
            .disabled(model.isBusy)
            .opacity(model.activity == .deleting(stored.id) ? 0.4 : 1)
            .accessibilityLabel("Delete \(stored.name)")
        }
        .padding(Space.md)
        .card()
    }

    // MARK: - Maintenance

    private var maintenance: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Text("Caches and half-finished downloads are safe to remove — the models themselves stay put.")
                .appType(.meta)
                .foregroundStyle(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Space.sm) {
                actionPill(
                    title: "Clear cache",
                    busyTitle: "Clearing…",
                    symbol: "arrow.3.trianglepath",
                    isRunning: model.activity == .clearingCache
                ) {
                    Task { await model.clearCache(store: store) }
                }

                actionPill(
                    title: "Clean temporary files",
                    busyTitle: "Cleaning…",
                    symbol: "trash",
                    isRunning: model.activity == .cleaningTemp
                ) {
                    Task { await model.cleanTempFiles(store: store) }
                }

                Spacer(minLength: 0)
            }
        }
        .padding(Space.md)
        .card()
    }

    /// Neutral, not red: the copy above says these are safe to remove, and the
    /// only genuinely destructive control on this screen is the trash button on
    /// a model row.
    private func actionPill(
        title: String,
        busyTitle: String,
        symbol: String,
        isRunning: Bool,
        action: @escaping () -> Void
    ) -> some View {
        PillButton(
            title: isRunning ? busyTitle : title,
            symbol: symbol,
            tint: AppColors.textSecondary,
            isEnabled: !model.isBusy,
            action: action
        )
    }

    // MARK: - Chrome

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
