import SwiftUI

struct RecordingBar: View {
    let levels: [Float]
    let isPaused: Bool
    let elapsed: TimeInterval
    let transcript: String
    var diagnostics: String = ""
    let onPauseResume: () -> Void
    let onDiscard: () -> Void
    let onFinish: () -> Void

    var body: some View {
        HStack(spacing: Space.md) {
            Button(action: onDiscard) {
                Image(systemName: "trash")
                    .glyph(ComposerMetrics.glyph)
                    .foregroundStyle(AppColors.danger)
                    .frame(width: ComposerMetrics.control, height: ComposerMetrics.control)
                    .background(Circle().fill(AppColors.dangerMuted))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Discard recording")

            VStack(alignment: .leading, spacing: Space.xs) {
                Visualizer(levels: levels, isPaused: isPaused)
                    .frame(height: 22)

                HStack(spacing: Space.sm) {
                    Text(timeLabel)
                        .appType(.caption)
                        .monospacedDigit()
                        .foregroundStyle(AppColors.textSecondary)

                    if !transcript.isEmpty {
                        Text(transcript)
                            .appType(.caption)
                            .foregroundStyle(AppColors.textSecondary)
                            .lineLimit(1)
                    } else if !diagnostics.isEmpty {
                        Text(diagnostics)
                            .appType(.caption)
                            .monospacedDigit()
                            .foregroundStyle(AppColors.textTertiary)
                    }

                    Spacer(minLength: 0)
                }
            }

            Button(action: onPauseResume) {
                Image(systemName: isPaused ? "play.fill" : "pause.fill")
                    .glyph(ComposerMetrics.glyph)
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(width: ComposerMetrics.control, height: ComposerMetrics.control)
                    .background(Circle().fill(AppColors.surfaceMuted))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(isPaused ? "Resume" : "Pause")

            Button(action: onFinish) {
                Image(systemName: "checkmark")
                    .glyph(ComposerMetrics.glyph, weight: .semibold)
                    .foregroundStyle(AppColors.onBrand)
                    .frame(width: ComposerMetrics.control, height: ComposerMetrics.control)
                    .background(Circle().fill(AppColors.brand))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Use this recording")
        }
        .padding(.horizontal, ComposerMetrics.inset)
        .padding(.vertical, ComposerMetrics.gap)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var timeLabel: String {
        let total = Int(elapsed)
        return String(format: "%01d:%02d", total / 60, total % 60)
    }
}

private struct Visualizer: View {
    let levels: [Float]
    let isPaused: Bool

    var body: some View {
        GeometryReader { geo in
            let count = max(levels.count, 1)
            let spacing: CGFloat = 2
            let width = max(2, (geo.size.width - spacing * CGFloat(count - 1)) / CGFloat(count))

            HStack(alignment: .center, spacing: spacing) {
                ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                    Capsule()
                        .fill(isPaused ? AppColors.textTertiary : AppColors.brand)
                        .frame(width: width, height: height(for: level, in: geo.size.height))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .animation(.easeOut(duration: 0.12), value: levels)
        }
    }

    private func height(for level: Float, in available: CGFloat) -> CGFloat {
        let normalised = CGFloat(min(max(level, 0), 1))
        return max(3, normalised * available)
    }
}

struct SpeakButton: View {
    let isSpeaking: Bool
    let progress: Double
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if isSpeaking {
                    Circle()
                        .stroke(AppColors.brand.opacity(0.25), lineWidth: 2)
                    Circle()
                        .trim(from: 0, to: max(0.03, progress))
                        .stroke(AppColors.brand, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.2), value: progress)
                }
                Image(systemName: isSpeaking ? "stop.fill" : "speaker.wave.2")
                    .glyph(Glyph.xs)
                    .foregroundStyle(isSpeaking ? AppColors.brand : AppColors.textSecondary)
            }
            .frame(width: 26, height: 26)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(isSpeaking ? "Stop speaking" : "Speak")
        .accessibilityLabel(isSpeaking ? "Stop speaking" : "Speak")
    }
}
