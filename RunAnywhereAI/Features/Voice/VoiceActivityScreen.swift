import SwiftUI

struct VoiceActivityScreen: View {
    @Environment(ModelStore.self) private var store

    @State private var model = VoiceActivityViewModel()
    @State private var picking: VoiceSlot?

    var body: some View {
        ScrollView {
            VStack(spacing: Space.xl) {
                indicator
                metrics

                if let error = model.lastError {
                    VoiceNotice(message: error)
                }

                activityLog

                VoiceSection(title: "Model") {
                    VoiceModelRow(slot: model.vad, isEnabled: !model.isListening) {
                        picking = .activity
                    }
                }
            }
            .padding(Space.lg)
            .measured()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background)
        .task { await model.prepare(store: store) }
        .onDisappear { model.teardown() }
        .voiceModelPicker(
            slot: $picking,
            store: store,
            activeID: { _ in model.vad.id },
            onSelect: { _, choice in model.choose(choice) }
        )
    }

    // MARK: - Indicator

    private var indicator: some View {
        VStack(spacing: Space.lg) {
            VoiceStatusPill(text: statusTitle, tint: statusTint)

            ZStack {
                Circle()
                    .fill(statusTint.opacity(0.14))
                    .frame(width: VoiceMetrics.halo, height: VoiceMetrics.halo)
                    .scaleEffect(model.isSpeechDetected ? 1.1 : 1)
                    .animation(.easeOut(duration: 0.18), value: model.isSpeechDetected)

                Circle()
                    .fill(statusTint)
                    .frame(width: VoiceMetrics.core, height: VoiceMetrics.core)

                Image(systemName: model.isSpeechDetected ? "waveform" : "mic.slash")
                    .glyph(Glyph.hero, weight: .semibold)
                    .foregroundStyle(AppColors.onBrand)
            }

            VoiceLevelMeter(
                levels: model.levels.levels,
                tint: statusTint,
                isActive: model.isListening
            )
            .frame(height: VoiceMetrics.meter)
            .padding(.horizontal, Space.lg)

            probabilityBar

            Button {
                Task { await model.toggleListening() }
            } label: {
                HStack(spacing: Space.sm) {
                    if model.isPreparing {
                        ProgressView()
                            .controlSize(.small)
                            .tint(AppColors.onBrand)
                    } else {
                        Image(systemName: model.isListening ? "stop.fill" : "mic.fill")
                            .glyph(Glyph.sm, weight: .semibold)
                    }
                    Text(buttonTitle)
                        .appType(.cardTitle)
                }
                .foregroundStyle(AppColors.onBrand)
                .padding(.horizontal, Space.xl)
                .frame(height: Measure.hitTarget)
                .background(Capsule().fill(model.isListening ? AppColors.danger : AppColors.brand))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(model.isPreparing)
        }
        .padding(.vertical, Space.xl)
        .frame(maxWidth: .infinity)
        .card()
    }

    private var probabilityBar: some View {
        VStack(spacing: Space.xs) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(AppColors.surfaceMuted)
                    Capsule()
                        .fill(statusTint)
                        .frame(width: geo.size.width * CGFloat(min(max(model.probability, 0), 1)))
                        .animation(.easeOut(duration: 0.12), value: model.probability)
                }
            }
            .frame(height: Space.sm)

            HStack {
                Text("Speech probability")
                    .appType(.caption)
                    .foregroundStyle(AppColors.textTertiary)
                Spacer(minLength: 0)
                Text(String(format: "%.0f%%", model.probability * 100))
                    .appType(.caption)
                    .monospacedDigit()
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .padding(.horizontal, Space.lg)
    }

    private var buttonTitle: String {
        if model.isPreparing { return "Loading model" }
        return model.isListening ? "Stop listening" : "Start listening"
    }

    private var statusTitle: String {
        if model.isPreparing { return "Loading model" }
        if !model.isListening { return model.vad.model == nil ? "Needs a model" : "Idle" }
        return model.isSpeechDetected ? "Speech" : "Silence"
    }

    private var statusTint: Color {
        if model.isPreparing { return AppColors.info }
        if !model.isListening { return AppColors.textTertiary }
        return model.isSpeechDetected ? AppColors.success : AppColors.brand
    }

    // MARK: - Metrics

    private var metrics: some View {
        HStack(spacing: Space.xl) {
            metric("Utterances", value: "\(model.utterances)")
            metric("Speech", value: durationLabel(model.speechSeconds))
            metric("Events", value: "\(model.log.count)")
            Spacer(minLength: 0)
        }
        .padding(Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
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

    private func durationLabel(_ seconds: TimeInterval) -> String {
        String(format: "%.1fs", seconds)
    }

    // MARK: - Log

    private var activityLog: some View {
        VoiceSection(title: "Activity") {
            VStack(spacing: 0) {
                if model.log.isEmpty {
                    Text("Nothing detected yet. Start listening and speak.")
                        .appType(.meta)
                        .foregroundStyle(AppColors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Space.md)
                } else {
                    ForEach(Array(model.log.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 {
                            Divider().overlay(AppColors.border)
                        }
                        row(entry)
                    }
                }
            }
            .card()

            if !model.log.isEmpty {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { model.clearLog() }
                } label: {
                    Text("Clear log")
                        .appType(.meta)
                        .foregroundStyle(AppColors.textSecondary)
                        .padding(.horizontal, Space.md)
                        .frame(height: 30)
                        .background(Capsule().fill(AppColors.surfaceMuted))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func row(_ entry: SpeechActivityEntry) -> some View {
        HStack(spacing: Space.md) {
            Image(systemName: entry.kind.symbol)
                .glyph(Glyph.sm)
                .foregroundStyle(entry.kind == .started ? AppColors.success : AppColors.textSecondary)
                .frame(width: Glyph.lg)

            Text(entry.kind.label)
                .appType(.secondary)
                .foregroundStyle(AppColors.textPrimary)

            Spacer(minLength: Space.sm)

            Text(String(format: "+%.1fs", entry.offset))
                .appType(.caption)
                .monospacedDigit()
                .foregroundStyle(AppColors.textSecondary)

            Text(entry.at.formatted(date: .omitted, time: .standard))
                .appType(.caption)
                .monospacedDigit()
                .foregroundStyle(AppColors.textTertiary)
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.sm)
    }
}
