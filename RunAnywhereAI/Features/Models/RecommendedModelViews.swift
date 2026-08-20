//
//  RecommendedModelViews.swift
//  RunAnywhereAI
//
//  Shared action plumbing for every model row on the Models screen — the
//  handler bundle every list item takes, and the one primary action button
//  (Get / Use / Active / Built-in) they all render. The rows themselves are
//  `ModelVariantRow` (ModelOrgViews.swift), reused everywhere: the family
//  detail list, the "Recommended for you" hero, and the companions row.
//

import SwiftUI
import RunAnywhere

/// Bundled callbacks for model rows/cards so views avoid long parameter lists.
struct ModelActionHandlers {
    /// Load / activate the model.
    let onSelect: (RAModelInfo) -> Void
    /// Reload catalog + storage after a download or delete completes.
    let onChanged: () -> Void
    /// Delete the downloaded model from the device. Nil hides the delete action.
    var onDelete: ((RAModelInfo) -> Void)?

    init(
        onSelect: @escaping (RAModelInfo) -> Void,
        onChanged: @escaping () -> Void,
        onDelete: ((RAModelInfo) -> Void)? = nil
    ) {
        self.onSelect = onSelect
        self.onChanged = onChanged
        self.onDelete = onDelete
    }
}

/// Reusable primary action (Get / Use / Active / Built-in) with inline download
/// progress. Single responsibility: drive a model's readiness action so every
/// `ModelVariantRow` instance never duplicates this logic.
struct ModelPrimaryActionButton: View {
    let model: RAModelInfo
    let availabilityReason: String?
    let isSelected: Bool
    let isLoadingModel: Bool
    let onSelectModel: () -> Void
    let onChanged: () -> Void

    // Download state lives in the shared tracker so it survives navigation, can be
    // cancelled, and can't start twice for the same model.
    private var downloads: ModelDownloadTracker { .shared }

    var body: some View {
        Group {
            if availabilityReason != nil {
                Button("Unavailable") {}
                    .buttonStyle(.bordered)
                    .disabled(true)
            } else if model.isBuiltIn {
                useButton
            } else if model.localPathURL == nil {
                downloadControl
            } else if isSelected {
                activeIndicator
            } else {
                useButton
            }
        }
        .font(AppTypography.caption)
        .fontWeight(.semibold)
        .controlSize(.small)
        .alert("Download Failed", isPresented: Binding(
            get: { downloads.errorMessage(model.id) != nil },
            set: { if !$0 { downloads.clearError(model.id) } }
        ), presenting: downloads.errorMessage(model.id)) { _ in
            // Retry from the alert, because that is where the user already is
            // when they learn it failed. Whether it resumes is the SDK's answer,
            // not a promise this button makes: a network drop keeps the partial
            // so a 3 GB download that died at 90% costs the last 10%, but a
            // checksum failure deliberately throws those bytes away and the next
            // attempt genuinely starts over. The verb says which one happened.
            Button(downloads.canResume(model.id) ? "Resume" : "Try Again") {
                downloads.clearError(model.id)
                downloads.start(model) { onChanged() }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text($0) }
    }

    private var useButton: some View {
        Button("Use") { onSelectModel() }
            .buttonStyle(.borderedProminent)
            .tint(AppColors.primaryAccent)
            .disabled((isSelected && model.isBuiltIn) || isLoadingModel)
    }

    @ViewBuilder private var downloadControl: some View {
        if let detail = downloads.detail(model.id) {
            // Real progress: bytes, rate, and remaining time, not a spinner.
            // Given a fixed width so a row does not resize as the numbers change.
            ModelDownloadProgressView(progress: detail) {
                downloads.cancel(model.id)
            }
            .frame(width: 190)
        } else {
            Button {
                downloads.start(model) { onChanged() }
            } label: {
                HStack(spacing: AppSpacing.xxSmall) {
                    // "Resume" is the honest verb once bytes are on disk: the SDK
                    // continues from the partial rather than starting over, so
                    // calling it "Get" would understate what the tap does.
                    Image(systemName: downloads.canResume(model.id) ? "arrow.clockwise" : "arrow.down.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                    Text(downloads.canResume(model.id) ? "Resume" : "Get")
                }
            }
            .buttonStyle(.bordered)
            .tint(AppColors.primaryAccent)
            .help(downloads.canResume(model.id)
                ? "Continue from where the download stopped"
                : "Download this model")
        }
    }

    private var activeIndicator: some View {
        HStack(spacing: AppSpacing.xxSmall) {
            Image(systemName: "checkmark.circle.fill")
            Text("Active")
        }
        .font(AppTypography.caption2)
        .foregroundColor(AppColors.statusGreen)
    }
}

// The hero "Recommended" card and the companions row used to be two more
// bespoke row types (`RecommendedModelCard`, `CompanionModelChip`) that
// duplicated `ModelVariantRow`'s layout and had no delete action wired in —
// a downloaded model surfaced up here was unreachable from the family-detail
// list (which excludes surfaced ids) and so had NO way to be deleted. Both
// are gone now; every model list in the app renders through the one
// `ModelVariantRow` (`leadingIcon:` covers the hero's capability glyph).
