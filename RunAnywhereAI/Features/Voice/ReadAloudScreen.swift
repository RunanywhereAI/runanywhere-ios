import SwiftUI

struct ReadAloudScreen: View {
    @Environment(ModelStore.self) private var store

    @State private var model = ReadAloudViewModel()
    @State private var picking: VoiceSlot?

    var body: some View {
        ScrollView {
            VStack(spacing: Space.xl) {
                editor
                samples
                speed

                if let error = model.lastError {
                    VoiceNotice(message: error)
                }

                playback

                VoiceSection(title: "Model") {
                    VoiceModelRow(slot: model.tts, isEnabled: !model.isSpeaking) {
                        picking = .voice
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
            activeID: { _ in model.tts.id },
            onSelect: { _, choice in model.choose(choice) }
        )
    }

    // MARK: - Text

    private var editor: some View {
        VoiceSection(title: "Text") {
            VStack(alignment: .leading, spacing: Space.sm) {
                TextEditor(text: $model.text)
                    .appType(.body)
                    .foregroundStyle(AppColors.textPrimary)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 140)
                    .disabled(model.isSpeaking)

                Text("\(model.trimmed.count) characters")
                    .appType(.caption)
                    .foregroundStyle(AppColors.textTertiary)
            }
            .padding(Space.md)
            .card()
        }
    }

    private var samples: some View {
        VoiceSection(title: "Or read one of these") {
            HStack(spacing: Space.xs) {
                ForEach(ReadAloudSample.all) { sample in
                    Button {
                        model.use(sample)
                    } label: {
                        Text(sample.title)
                            .appType(.meta)
                            .foregroundStyle(AppColors.textSecondary)
                            .padding(.horizontal, Space.md)
                            .frame(height: 30)
                            .background(Capsule().fill(AppColors.surfaceMuted))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isSpeaking)
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Speed

    private var speed: some View {
        VoiceSection(title: "Speed") {
            VStack(alignment: .leading, spacing: Space.sm) {
                HStack(spacing: Space.md) {
                    Slider(value: $model.rate, in: 0.5...2.0, step: 0.05)
                        .tint(AppColors.brand)
                        .disabled(model.isSpeaking)

                    Text(String(format: "%.2f×", model.rate))
                        .appType(.monoMetric)
                        .foregroundStyle(AppColors.textPrimary)
                        .frame(width: 64, alignment: .trailing)
                }

                Text("Applied when playback starts, so a change takes effect on the next phrase.")
                    .appType(.caption)
                    .foregroundStyle(AppColors.textTertiary)
            }
            .padding(Space.md)
            .card()
        }
    }

    // MARK: - Playback

    private var playback: some View {
        HStack(spacing: Space.md) {
            Button {
                Task {
                    if model.isSpeaking {
                        await model.stop()
                    } else {
                        await model.speak()
                    }
                }
            } label: {
                HStack(spacing: Space.sm) {
                    if model.isPreparing {
                        ProgressView()
                            .controlSize(.small)
                            .tint(AppColors.onBrand)
                    } else {
                        Image(systemName: model.isSpeaking ? "stop.fill" : "play.fill")
                            .glyph(Glyph.sm, weight: .semibold)
                    }
                    Text(buttonTitle)
                        .appType(.cardTitle)
                }
                .foregroundStyle(AppColors.onBrand)
                .padding(.horizontal, Space.xl)
                .frame(height: Measure.hitTarget)
                .background(Capsule().fill(model.canSpeak ? AppColors.brand : AppColors.textTertiary))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!model.canSpeak && !model.isSpeaking)

            VoiceStatusPill(text: statusTitle, tint: statusTint)

            Spacer(minLength: 0)
        }
    }

    private var buttonTitle: String {
        if model.isPreparing { return "Loading voice" }
        return model.isSpeaking ? "Stop" : "Speak"
    }

    private var statusTitle: String {
        if model.isPreparing { return "Loading model" }
        if model.isSpeaking { return "Speaking" }
        return model.tts.model == nil ? "Needs a voice" : "Ready"
    }

    private var statusTint: Color {
        if model.isPreparing { return AppColors.info }
        if model.isSpeaking { return AppColors.success }
        return model.tts.model == nil ? AppColors.textTertiary : AppColors.brand
    }
}
