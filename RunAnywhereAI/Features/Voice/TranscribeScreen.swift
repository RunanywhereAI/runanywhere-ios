import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

struct TranscribeScreen: View {
    @Environment(ModelStore.self) private var store

    @State private var model = TranscribeViewModel()
    @State private var picking: VoiceSlot?

    var body: some View {
        ScrollView {
            VStack(spacing: Space.xl) {
                modes
                recorder

                if let error = model.lastError {
                    VoiceNotice(message: error)
                }

                transcript

                VoiceSection(title: "Model") {
                    VoiceModelRow(slot: model.stt, isEnabled: !model.isRecording) {
                        picking = .speech
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
            activeID: { _ in model.stt.id },
            onSelect: { _, choice in model.choose(choice) }
        )
    }

    // MARK: - Mode

    private var modes: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(spacing: Space.xs) {
                ForEach(TranscribeMode.allCases) { mode in
                    modeChip(mode)
                }
                Spacer(minLength: 0)
            }

            Text(model.mode.detail)
                .appType(.meta)
                .foregroundStyle(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func modeChip(_ mode: TranscribeMode) -> some View {
        let isActive = model.mode == mode
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { model.mode = mode }
        } label: {
            Text(mode.title)
                .appType(.meta)
                .foregroundStyle(isActive ? AppColors.onBrand : AppColors.textSecondary)
                .padding(.horizontal, Space.lg)
                .frame(height: 32)
                .background(Capsule().fill(isActive ? AppColors.brandSelected : AppColors.surfaceMuted))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(model.isRecording || model.isBusy)
    }

    // MARK: - Recorder

    private var recorder: some View {
        VStack(spacing: Space.lg) {
            VoiceStatusPill(text: statusTitle, tint: statusTint)

            Button {
                Task { await model.toggleRecording() }
            } label: {
                ZStack {
                    Circle()
                        .fill(statusTint.opacity(0.14))
                        .frame(width: VoiceMetrics.halo, height: VoiceMetrics.halo)
                    Circle()
                        .fill(statusTint)
                        .frame(width: VoiceMetrics.core, height: VoiceMetrics.core)
                    Image(systemName: model.isRecording ? "stop.fill" : "mic.fill")
                        .glyph(Glyph.lg, weight: .semibold)
                        .foregroundStyle(AppColors.onBrand)
                }
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(model.isBusy)
            .opacity(model.isBusy ? 0.5 : 1)
            .accessibilityLabel(model.isRecording ? "Stop recording" : "Start recording")

            VoiceLevelMeter(levels: model.levels.levels, isActive: model.isRecording)
                .frame(height: VoiceMetrics.meter)
                .padding(.horizontal, Space.lg)

            Text(elapsedLabel)
                .appType(.monoMetric)
                .foregroundStyle(AppColors.textSecondary)
        }
        .padding(.vertical, Space.xl)
        .frame(maxWidth: .infinity)
        .card()
    }

    private var statusTitle: String {
        if model.isTranscribing { return "Transcribing" }
        if model.isPreparing { return "Loading model" }
        if model.isRecording { return model.mode == .live ? "Listening" : "Recording" }
        return model.stt.model == nil ? "Needs a model" : "Ready"
    }

    private var statusTint: Color {
        if model.isBusy { return AppColors.info }
        if model.isRecording { return AppColors.danger }
        return model.stt.model == nil ? AppColors.textTertiary : AppColors.brand
    }

    private var elapsedLabel: String {
        let total = Int(model.recordedSeconds)
        return String(format: "%01d:%02d", total / 60, total % 60)
    }

    // MARK: - Transcript

    private var transcript: some View {
        VoiceSection(title: "Transcript") {
            VStack(alignment: .leading, spacing: Space.md) {
                if model.hasResult {
                    Text(model.displayText)
                        .appType(.body)
                        .foregroundStyle(AppColors.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)

                    HStack(spacing: Space.sm) {
                        actionChip("Copy", symbol: "doc.on.doc") { copy(model.displayText) }
                        actionChip("Clear", symbol: "xmark") { model.clear() }
                        Spacer(minLength: 0)
                    }
                } else {
                    Text(model.outcome.message)
                        .appType(.meta)
                        .foregroundStyle(AppColors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(Space.md)
            .frame(minHeight: 120, alignment: .top)
            .card()
        }
    }

    private func actionChip(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Space.xs) {
                Image(systemName: symbol)
                    .glyph(Glyph.xs, weight: .semibold)
                Text(title)
                    .appType(.meta)
            }
            .foregroundStyle(AppColors.textSecondary)
            .padding(.horizontal, Space.md)
            .frame(height: 30)
            .background(Capsule().fill(AppColors.surfaceMuted))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func copy(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }
}
