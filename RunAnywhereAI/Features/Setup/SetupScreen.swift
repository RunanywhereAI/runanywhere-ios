//
//  SetupScreen.swift
//  RunAnywhereAI
//
//  The first launch, before the app proper.
//

import RunAnywhere
import SwiftUI

/// One screen that gets a working device in a single tap.
///
/// Until now a new install opened on chat with nothing behind it, and the
/// reader had to find the download gate, pick a chat model, and then discover
/// separately that voice needs two more. This offers all three at once, with
/// the chat model locked on and the voice pair as choices, and hands over to
/// the app when the bytes are down.
///
/// Skipping is a real answer: `ChatFirstRunView` still stands behind chat, so
/// nobody who declines here is stranded.
struct SetupScreen: View {
    let store: ModelStore
    let settings: AppSettings
    let onFinished: () -> Void

    @State private var defaults = DefaultModels()
    @State private var candidates: [SetupCandidate] = []
    @State private var chosen: Set<String> = []
    @State private var isInstalling = false
    @State private var failure: String?

    var body: some View {
        Scaffold {
            ScrollView {
                VStack(spacing: Space.xl) {
                    header

                    VStack(spacing: Space.sm) {
                        ForEach(candidates) { candidate in
                            row(candidate)
                        }
                    }

                    if let failure {
                        Text(failure)
                            .appType(.caption)
                            .foregroundStyle(AppColors.danger)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    actions

                    Text("Everything downloads once and runs on this device. Nothing you type leaves it.")
                        .appType(.caption)
                        .foregroundStyle(AppColors.textTertiary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Space.xl)
                .measured(520)
            }
        }
        .task { candidates = SetupPlan.candidates(from: store.raw) }
        .onChange(of: candidates.map(\.id)) { _, ids in
            chosen = Set(ids)
        }
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(spacing: Space.sm) {
            Image(systemName: "sparkles")
                .glyph(Glyph.hero, weight: .light)
                .foregroundStyle(AppColors.brand)
                .frame(width: 64, height: 64)
                .background(Circle().fill(AppColors.brandMuted))

            Text("Set up RunAnywhere")
                .appType(.title)
                .foregroundStyle(AppColors.textPrimary)
                .multilineTextAlignment(.center)

            Text(subtitle)
                .appType(.secondary)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, Space.lg)
    }

    private var subtitle: String {
        guard let total = SetupPlan.total(of: selected) else {
            return "These are the models picked for this device."
        }
        let size = (total.isApproximate ? "About " : "") + AppSettings.format(total.bytes)
        return "\(size) of models picked for this device. It takes a few minutes, once."
    }

    private func row(_ candidate: SetupCandidate) -> some View {
        HStack(spacing: Space.md) {
            GlyphTile(symbol: candidate.purpose.symbol)

            VStack(alignment: .leading, spacing: Space.hair) {
                Text(store.label(for: candidate.model))
                    .appType(.cardTitle)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                Text("\(candidate.rationale) · \(candidate.model.consumerSizeLabel)")
                    .appType(.caption)
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: Space.sm)

            trailing(candidate)
        }
        .padding(Space.md)
        .card()
    }

    @ViewBuilder
    private func trailing(_ candidate: SetupCandidate) -> some View {
        if let progress = store.downloading[candidate.id] {
            Text("\(Int(progress * 100))%")
                .appType(.meta)
                .monospacedDigit()
                .foregroundStyle(AppColors.brand)
        } else if isInstalling, chosen.contains(candidate.id) {
            // Queued, or done. Either way the row is settled and the reader
            // only needs to know it is still in the run.
            Image(systemName: store.installed.contains { $0.id == candidate.id }
                ? "checkmark.circle.fill" : "clock")
                .glyph(Glyph.sm)
                .foregroundStyle(AppColors.textTertiary)
        } else if candidate.isEssential {
            // Not a disabled switch: a switch that cannot move still reads as
            // one that is off, and this row is the one thing always installed.
            StatusTag(text: "Required", tint: AppColors.brand, showsDot: false)
        } else {
            Toggle("", isOn: binding(for: candidate))
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(AppColors.brand)
                .accessibilityLabel("Install \(store.label(for: candidate.model))")
        }
    }

    private var actions: some View {
        VStack(spacing: Space.sm) {
            Button(action: install) {
                HStack(spacing: Space.xs) {
                    if isInstalling {
                        ProgressView().controlSize(.small).tint(AppColors.onBrand)
                    }
                    Text(primaryTitle)
                        .appType(.cardTitle)
                }
                .foregroundStyle(AppColors.onBrand)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Capsule().fill(AppColors.brand))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isInstalling || selected.isEmpty)
            .opacity(isInstalling || selected.isEmpty ? 0.5 : 1)

            Button("Skip for now", action: skip)
                .buttonStyle(.plain)
                .appType(.meta)
                .foregroundStyle(AppColors.textSecondary)
                .disabled(isInstalling)
                .opacity(isInstalling ? 0.4 : 1)
        }
    }

    private var primaryTitle: String {
        if isInstalling { return "Downloading…" }
        if failure != nil { return "Try again" }
        return "Download and continue"
    }

    // MARK: - Behaviour

    private var selected: [SetupCandidate] {
        candidates.filter { chosen.contains($0.id) }
    }

    private func binding(for candidate: SetupCandidate) -> Binding<Bool> {
        Binding(
            get: { chosen.contains(candidate.id) },
            set: { isOn in
                if isOn {
                    chosen.insert(candidate.id)
                } else {
                    chosen.remove(candidate.id)
                }
            }
        )
    }

    private func install() {
        guard !isInstalling else { return }
        Task {
            isInstalling = true
            failure = nil
            defer { isInstalling = false }

            // One at a time. Three concurrent multi-gigabyte downloads on a
            // phone starve each other and give the reader three bars that all
            // crawl, and a failure part-way through leaves a clearer state.
            for candidate in selected where !store.installed.contains(where: { $0.id == candidate.id }) {
                guard await store.download(candidate.id) else {
                    failure = store.lastError ?? "\(store.label(for: candidate.model)) did not download."
                    return
                }
                adopt(candidate)
            }

            await loadChatModel()
            finish()
        }
    }

    /// Loads the chat model before handing over, because "Download and
    /// continue" that lands on a composer reading "Choose a model" has not
    /// continued anywhere. Downloading sets the default; only loading makes the
    /// model the one chat is actually talking to.
    ///
    /// A failure here is not worth blocking on: the model is on the device, and
    /// the picker is one tap away.
    private func loadChatModel() async {
        guard let chat = selected.first(where: { $0.purpose == .language }) else { return }
        await defaults.ensureLoaded(chat.model.id, category: .language)
    }

    /// A model nobody points at is just bytes on disk, so each one becomes the
    /// default for its modality as it lands.
    private func adopt(_ candidate: SetupCandidate) {
        switch candidate.purpose {
        case .language: defaults.llmID = candidate.model.id
        case .speechToText: defaults.sttID = candidate.model.id
        case .textToSpeech: defaults.ttsID = candidate.model.id
        default: break
        }
    }

    private func skip() {
        finish()
    }

    private func finish() {
        settings.hasCompletedSetup = true
        onFinished()
    }
}
