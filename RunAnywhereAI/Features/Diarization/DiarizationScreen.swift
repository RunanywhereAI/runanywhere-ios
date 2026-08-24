#if os(iOS)
import SwiftUI

struct DiarizationScreen: View {
    @Environment(ModelStore.self) private var store
    @State private var model = DiarizationViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                DiarizationModelCard(store: store, model: model)

                if model.hasModel {
                    section("Recording") { recorder }
                    section("Speakers") { transcript }
                }

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
        .task { await model.refreshLoadedModel(store: store) }
        .onDisappear { model.stop() }
    }

    // MARK: - Recording

    private var recorder: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Text("Record a clip with two or more people talking. Nothing leaves the device.")
                .appType(.meta)
                .foregroundStyle(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            meter

            HStack(spacing: Space.sm) {
                recordButton

                if model.isRecording {
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) { model.discard() }
                    } label: {
                        Text("Discard")
                            .appType(.meta)
                            .foregroundStyle(AppColors.textSecondary)
                            .padding(.horizontal, Space.md)
                            .frame(height: Measure.hitTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Text(Self.clock(model.elapsed))
                        .appType(.monoMetric)
                        .foregroundStyle(AppColors.textSecondary)
                }

                Spacer(minLength: 0)

                if model.isDiarizing {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let status = model.status {
                Text(status)
                    .appType(.meta)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .padding(Space.md)
        .card()
    }

    private var recordButton: some View {
        Button {
            Task { await model.toggleRecording() }
        } label: {
            HStack(spacing: Space.sm) {
                Image(systemName: model.isRecording ? "stop.fill" : "mic.fill")
                    .glyph(Glyph.sm, weight: .semibold)
                Text(model.isRecording ? "Stop and diarize" : "Record")
                    .appType(.cardTitle)
            }
            .foregroundStyle(model.isRecording ? AppColors.danger : AppColors.brand)
            .padding(.horizontal, Space.lg)
            .frame(height: Measure.hitTarget)
            .background(
                Capsule().fill(model.isRecording ? AppColors.dangerMuted : AppColors.brandMuted)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(model.isBusy)
    }

    private var meter: some View {
        HStack(alignment: .center, spacing: Space.hair) {
            ForEach(Array(model.levels.enumerated()), id: \.offset) { _, level in
                Capsule()
                    .fill(model.isRecording ? AppColors.brand : AppColors.borderStrong)
                    .frame(width: Space.hair, height: max(CGFloat(level) * Glyph.hero, Stroke.heavy))
            }
        }
        .frame(height: Glyph.hero, alignment: .center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.sm)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(AppColors.surfaceMuted)
        )
        .accessibilityHidden(true)
    }

    // MARK: - Segments

    @ViewBuilder
    private var transcript: some View {
        if model.turns.isEmpty {
            EmptyState(
                symbol: "waveform.badge.person",
                title: model.isDiarizing ? "Listening back…" : "Nothing diarized yet",
                detail: model.isDiarizing
                    ? "Splitting the clip into speaker turns."
                    : "Record a clip and the speaker turns land here, one colour per voice."
            )
            .card()
        } else {
            VStack(spacing: Space.sm) {
                speakerLegend

                ForEach(model.turns) { turn in
                    row(turn)
                }
            }
        }
    }

    private var speakerLegend: some View {
        HStack(spacing: Space.sm) {
            ForEach(0..<max(model.speakerCount, 1), id: \.self) { index in
                HStack(spacing: Space.xs) {
                    Circle()
                        .fill(SpeakerPalette.tint(index))
                        .frame(width: Space.sm, height: Space.sm)
                    Text("Speaker \(index + 1)")
                        .appType(.caption)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func row(_ turn: SpeakerTurn) -> some View {
        let tint = SpeakerPalette.tint(turn.speakerIndex)
        return HStack(spacing: Space.md) {
            RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                .fill(tint)
                .frame(width: Stroke.heavy * 2)

            VStack(alignment: .leading, spacing: Space.hair) {
                Text("Speaker \(turn.speakerIndex + 1)")
                    .appType(.cardTitle)
                    .foregroundStyle(tint)
                Text(turn.speakerID)
                    .appType(.caption)
                    .foregroundStyle(AppColors.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: Space.sm)

            VStack(alignment: .trailing, spacing: Space.hair) {
                Text(turn.range)
                    .appType(.mono)
                    .foregroundStyle(AppColors.textPrimary)
                Text(turn.durationLabel)
                    .appType(.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .padding(Space.md)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(tint.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(AppColors.border, lineWidth: Stroke.hairline)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Speaker \(turn.speakerIndex + 1), \(turn.range)")
    }

    // MARK: - Chrome

    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(title)
                .appType(.overline)
                .textCase(.uppercase)
                .foregroundStyle(AppColors.textSecondary)
            content()
        }
    }

    private static func clock(_ elapsed: TimeInterval) -> String {
        String(format: "%d:%02d", Int(elapsed) / 60, Int(elapsed) % 60)
    }
}

/// Speaker identity is the one thing this screen colours, and it needs more
/// hues than the palette reserves for status. These are the same tokens, read
/// as identity rather than as a warning.
enum SpeakerPalette {
    private static let tints: [Color] = [
        AppColors.brand,
        AppColors.info,
        AppColors.success,
        AppColors.accent,
        AppColors.danger
    ]

    static func tint(_ index: Int) -> Color {
        tints[abs(index) % tints.count]
    }
}
#endif
