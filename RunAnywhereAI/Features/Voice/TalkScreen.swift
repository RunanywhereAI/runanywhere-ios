import SwiftUI

struct TalkScreen: View {
    /// Where a finished exchange goes. Nil in the More hub, which has no
    /// conversation to put one in.
    var onTurn: ((String, String) -> Void)?

    @Environment(ModelStore.self) private var store

    @State private var model = TalkViewModel()
    @State private var picking: VoiceSlot?

    var body: some View {
        content.onAppear { model.onTurn = onTurn }
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: Space.xl) {
                stage

                if hasConversation {
                    conversation
                }

                if let error = model.lastError, !model.phase.isLive {
                    VoiceNotice(message: error)
                }

                pipeline
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
            activeID: { model.activeID(for: $0) },
            onSelect: { slot, choice in model.choose(slot, model: choice) }
        )
    }

    // MARK: - Stage

    private var stage: some View {
        VStack(spacing: Space.lg) {
            VoiceStatusPill(text: statusTitle, tint: statusTint)

            micButton

            Text(statusDetail)
                .appType(.secondary)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 320)

            if model.phase.isLive {
                PillButton(title: "End conversation", tint: AppColors.textSecondary) {
                    Task { await model.stop() }
                }
            }
        }
        .padding(.vertical, Space.xl)
        .frame(maxWidth: .infinity)
        .card()
    }

    private var micButton: some View {
        Button(action: primaryAction) {
            ZStack {
                Circle()
                    .fill(statusTint.opacity(0.14))
                    .frame(width: VoiceMetrics.halo, height: VoiceMetrics.halo)
                    .scaleEffect(model.isSpeechDetected ? 1.08 : 1)
                    .animation(Motion.quick, value: model.isSpeechDetected)

                Circle()
                    .strokeBorder(statusTint.opacity(0.4), lineWidth: Stroke.heavy)
                    .frame(width: VoiceMetrics.ring, height: VoiceMetrics.ring)

                Circle()
                    .fill(statusTint)
                    .frame(width: VoiceMetrics.core, height: VoiceMetrics.core)

                if model.phase == .connecting {
                    ProgressView()
                        .controlSize(.large)
                        .tint(AppColors.onBrand)
                } else {
                    Image(systemName: primarySymbol)
                        .glyph(Glyph.hero, weight: .semibold)
                        .foregroundStyle(AppColors.onBrand)
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(model.phase == .connecting || (!model.isReady && !model.phase.isLive))
        .opacity(model.isReady || model.phase.isLive ? 1 : 0.45)
        .accessibilityLabel(primaryLabel)
    }

    private func primaryAction() {
        switch model.phase {
        case .speaking:
            Task { await model.interrupt() }
        case .listening, .thinking:
            Task { await model.stop() }
        case .idle, .failed:
            Task { await model.start() }
        case .connecting:
            break
        }
    }

    private var primarySymbol: String {
        switch model.phase {
        case .speaking: "hand.raised.fill"
        case .listening, .thinking: "stop.fill"
        case .idle, .failed, .connecting: "mic.fill"
        }
    }

    private var primaryLabel: String {
        switch model.phase {
        case .speaking: model.isInterrupting ? "Stopping the reply" : "Take the turn back"
        case .listening, .thinking: "End conversation"
        case .connecting: "Getting ready"
        case .idle, .failed: "Start conversation"
        }
    }

    private var statusTitle: String {
        switch model.phase {
        case .idle: model.isReady ? "Ready" : "Needs models"
        case .connecting: "Connecting"
        case .listening: "Listening"
        case .thinking: "Thinking"
        case .speaking: "Speaking"
        case .failed: "Stopped"
        }
    }

    private var statusTint: Color {
        switch model.phase {
        case .idle: model.isReady ? AppColors.brand : AppColors.textTertiary
        case .connecting: AppColors.info
        case .listening: model.inputSilentDetail == nil ? AppColors.brand : AppColors.textTertiary
        case .thinking: AppColors.info
        case .speaking: AppColors.success
        case .failed: AppColors.danger
        }
    }

    private var statusDetail: String {
        if let silent = model.inputSilentDetail, model.phase.isLive {
            return "Nothing is reaching the microphone — \(silent)"
        }
        switch model.phase {
        case .idle:
            return model.isReady
                ? "Press to talk. It listens until you stop, answers out loud, and you can cut in any time."
                : "Pick a speech, language and voice model below to begin."
        case .connecting:
            return "Loading the models and opening the microphone."
        case .listening:
            return model.isSpeechDetected ? "Go on, I'm following." : "Go ahead — say something."
        case .thinking:
            return "Working out a reply."
        case .speaking:
            return model.isInterrupting ? "Stopping." : "Speaking. Press to cut in."
        case .failed(let message):
            return message
        }
    }

    // MARK: - Conversation

    private var hasConversation: Bool {
        !model.transcript.isEmpty || !model.reply.isEmpty
    }

    private var conversation: some View {
        ScreenSection(title: "This turn") {
            VStack(alignment: .leading, spacing: Space.md) {
                if !model.transcript.isEmpty {
                    turn(
                        speaker: "You",
                        text: model.transcript,
                        symbol: "person.wave.2",
                        tint: AppColors.brand,
                        isProvisional: !model.isTranscriptFinal
                    )
                }

                if !model.reply.isEmpty {
                    turn(
                        speaker: "Assistant",
                        text: model.reply,
                        symbol: "waveform",
                        tint: AppColors.accent,
                        isProvisional: model.phase == .thinking
                    )
                }
            }
            .padding(Space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
    }

    private func turn(
        speaker: String,
        text: String,
        symbol: String,
        tint: Color,
        isProvisional: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.xs) {
                Image(systemName: symbol)
                    .glyph(Glyph.xs, weight: .semibold)
                Text(speaker)
                    .appType(.overline)
                    .textCase(.uppercase)
                if isProvisional {
                    Text("live")
                        .appType(.caption)
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
            .foregroundStyle(tint)

            Text(text)
                .appType(.body)
                .foregroundStyle(isProvisional ? AppColors.textSecondary : AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }

    // MARK: - Pipeline

    private var pipeline: some View {
        ScreenSection(title: "Pipeline") {
            VStack(spacing: Space.sm) {
                ForEach([model.stt, model.llm, model.tts], id: \.slot) { slot in
                    VoiceModelRow(slot: slot, isEnabled: !model.phase.isLive) {
                        picking = slot.slot
                    }
                }
            }
        }
    }
}
