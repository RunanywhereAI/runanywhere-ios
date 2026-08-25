//
//  ChatFirstRun.swift
//  RunAnywhereAI
//
//  What chat shows before there is anything to chat with.
//

import SwiftUI
import RunAnywhere

/// The first-run download gate.
///
/// Chat used to open on a live transcript and a dead composer reading "Choose a
/// chat model to start", which asks the reader to work out what is missing and
/// where to get it. Nothing about the conversation is real until a model is on
/// the device, so none of it is drawn: this offers the model picked for this
/// device, keeps the rest as alternatives, and hands over to chat the moment
/// one is ready. The sidebar stays live throughout, so Settings is always a tap
/// away.
struct ChatFirstRunView: View {
    let store: ModelStore
    let shortlist: CuratedModels
    let onReady: (String) -> Void
    let onBrowseModels: () -> Void

    private var recommended: ModelInfo? {
        guard let id = shortlist.recommendedID else { return shortlist.models.first }
        return shortlist.models.first { $0.id == id } ?? shortlist.models.first
    }

    private var alternatives: [ModelInfo] {
        shortlist.models.filter { $0.id != recommended?.id }
    }

    var body: some View {
        Group {
            if shortlist.isEmpty {
                unavailable
            } else {
                offer
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var unavailable: some View {
        if !store.hasLoaded || store.isRefreshing {
            VStack(spacing: Space.md) {
                ProgressView()
                Text("Reading the model catalog…")
                    .appType(.meta)
                    .foregroundStyle(AppColors.textSecondary)
            }
        } else {
            EmptyState(
                symbol: "square.stack.3d.up.slash",
                title: "No chat models available",
                detail: "The catalog registers on launch and none of its chat models can run here.",
                actionTitle: "Open Manage Models",
                action: onBrowseModels
            )
        }
    }

    private var offer: some View {
        ScrollView {
            VStack(spacing: Space.xl) {
                header

                if let recommended {
                    hero(recommended)
                }

                if !alternatives.isEmpty {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        Text("Or pick another")
                            .appType(.overline)
                            .textCase(.uppercase)
                            .foregroundStyle(AppColors.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        ForEach(alternatives, id: \.id) { model in
                            alternative(model)
                        }
                    }
                }

                Text("Models run entirely on this device. Nothing you type leaves it.")
                    .appType(.caption)
                    .foregroundStyle(AppColors.textTertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(Space.lg)
            .measured(520)
        }
    }

    private var header: some View {
        VStack(spacing: Space.sm) {
            Image(systemName: "arrow.down.circle")
                .glyph(Glyph.hero, weight: .light)
                .foregroundStyle(AppColors.brand)
                .frame(width: 64, height: 64)
                .background(Circle().fill(AppColors.brandMuted))

            Text("Download a model to start chatting")
                .appType(.title)
                .foregroundStyle(AppColors.textPrimary)
                .multilineTextAlignment(.center)

            Text("This one is the best fit for this device. It takes a few minutes, once.")
                .appType(.secondary)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, Space.lg)
    }

    private func hero(_ model: ModelInfo) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack(spacing: Space.sm) {
                Image(systemName: "sparkles")
                    .glyph(Glyph.sm, weight: .semibold)
                Text("Recommended for this device")
                    .appType(.overline)
                    .textCase(.uppercase)
                Spacer(minLength: 0)
            }
            .foregroundStyle(AppColors.brand)

            Text(store.label(for: model))
                .appType(.sectionTitle)
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            action(for: model, prominent: true)
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

    private func alternative(_ model: ModelInfo) -> some View {
        HStack(spacing: Space.md) {
            VStack(alignment: .leading, spacing: Space.hair) {
                Text(store.label(for: model))
                    .appType(.cardTitle)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                Text(shortlist.standing(of: model).label)
                    .appType(.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }

            Spacer(minLength: Space.sm)

            action(for: model, prominent: false)
        }
        .padding(Space.md)
        .card()
    }

    @ViewBuilder
    private func action(for model: ModelInfo, prominent: Bool) -> some View {
        if let progress = store.downloading[model.id] {
            VStack(alignment: .leading, spacing: Space.xs) {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(AppColors.brand)
                Text("Downloading · \(Int(progress * 100))%")
                    .appType(.caption)
                    .monospacedDigit()
                    .foregroundStyle(AppColors.textSecondary)
            }
            .frame(maxWidth: prominent ? .infinity : 140)
        } else {
            Button {
                start(model)
            } label: {
                HStack(spacing: Space.xs) {
                    Image(systemName: "arrow.down")
                        .glyph(Glyph.xs, weight: .semibold)
                    Text(prominent ? "Download · \(model.consumerSizeLabel)" : model.consumerSizeLabel)
                        .appType(prominent ? .cardTitle : .meta)
                }
                .foregroundStyle(prominent ? AppColors.onBrand : AppColors.brand)
                .frame(maxWidth: prominent ? .infinity : nil)
                .padding(.horizontal, Space.lg)
                .frame(height: prominent ? 44 : 30)
                .background(Capsule().fill(prominent ? AppColors.brand : AppColors.brandMuted))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(store.isDownloading)
            .opacity(store.isDownloading ? 0.4 : 1)
        }
    }

    private func start(_ model: ModelInfo) {
        Task {
            await store.download(model.id)
            guard store.models.first(where: { $0.id == model.id })?.isDownloaded == true else {
                return
            }
            onReady(model.id)
        }
    }
}
