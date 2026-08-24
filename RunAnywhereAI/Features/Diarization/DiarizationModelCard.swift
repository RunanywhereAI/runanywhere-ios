#if os(iOS)
import SwiftUI
import RunAnywhere

/// Which diarization model is loaded, and a way to get one when none is.
struct DiarizationModelCard: View {
    let store: ModelStore
    let model: DiarizationViewModel

    private var candidates: [ModelInfo] {
        DiarizationViewModel.models(in: store)
    }

    var body: some View {
        if let name = model.loadedModelName {
            loaded(name)
        } else if candidates.isEmpty {
            EmptyState(
                symbol: "person.2.wave.2",
                title: "No diarization model in the catalog",
                detail: "Telling speakers apart needs a diarization model. None is registered on this device."
            )
            .card()
        } else {
            choices
        }
    }

    private func loaded(_ name: String) -> some View {
        HStack(spacing: Space.md) {
            GlyphTile(symbol: "person.2.wave.2")

            Text(name)
                .appType(.cardTitle)
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1)

            Spacer(minLength: Space.sm)

            CapabilityTag(symbol: "checkmark", title: "Ready", tint: AppColors.success)
        }
        .padding(Space.md)
        .card()
    }

    private var choices: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text("Diarization runs on its own model, separate from speech to text.")
                .appType(.meta)
                .foregroundStyle(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(candidates, id: \.id) { candidate in
                row(candidate)
            }
        }
        .padding(Space.md)
        .card()
    }

    private func row(_ candidate: ModelInfo) -> some View {
        HStack(spacing: Space.md) {
            Text(candidate.name.isEmpty ? candidate.id : candidate.name)
                .appType(.cardTitle)
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1)

            Spacer(minLength: Space.sm)

            action(candidate)
        }
        .padding(.vertical, Space.xs)
    }

    @ViewBuilder
    private func action(_ candidate: ModelInfo) -> some View {
        if let progress = store.downloading[candidate.id] {
            HStack(spacing: Space.xs) {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(AppColors.brand)
                Text("\(Int(progress * 100))%")
                    .appType(.caption)
                    .monospacedDigit()
                    .foregroundStyle(AppColors.textSecondary)
            }
            .frame(width: 130)
        } else if candidate.localPath.isEmpty {
            PillButton(
                title: "Get",
                symbol: "arrow.down",
                tint: AppColors.brand,
                fill: AppColors.brandMuted,
                isEnabled: !model.isLoadingModel
            ) {
                Task { await store.download(candidate.id) }
            }
        } else {
            PillButton(
                title: model.isLoadingModel ? "Loading…" : "Use",
                symbol: "play.fill",
                tint: AppColors.brand,
                fill: AppColors.brandMuted,
                isEnabled: !model.isLoadingModel
            ) {
                Task { await model.load(candidate, store: store) }
            }
        }
    }
}
#endif
