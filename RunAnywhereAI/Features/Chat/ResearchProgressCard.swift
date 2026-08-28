import SwiftUI

/// A multi-step tool's work, shown while it happens and kept afterwards.
///
/// Collapsed it is one line saying where the tool has got to; expanded it is
/// the full trail with whatever each step reported. Nothing here knows what
/// the steps are — the tool names them — so a tool with three stages or nine
/// renders without a change.
struct ResearchProgressCard: View {
    let tool: ToolInvocation
    var isBusy: Bool = false

    @State private var isExpanded = false

    private var current: ResearchStage? {
        tool.stages.last(where: { $0.status == .running }) ?? tool.stages.last
    }

    private var failedCount: Int {
        tool.stages.filter { $0.status == .failed }.count
    }

    private var accent: Color {
        if isBusy { return AppColors.info }
        return failedCount > 0 ? AppColors.danger : AppColors.success
    }

    private var wash: Color {
        if isBusy { return AppColors.infoMuted }
        return failedCount > 0 ? AppColors.dangerMuted : AppColors.successMuted
    }

    private var headline: String {
        if isBusy { return current?.label ?? "Researching" }
        let done = tool.stages.filter { $0.status != .failed }.count
        return "Researched in \(done) step\(done == 1 ? "" : "s")"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if isExpanded {
                Divider().overlay(AppColors.border)
                VStack(alignment: .leading, spacing: Space.md) {
                    ForEach(tool.stages) { stage in
                        row(for: stage)
                    }
                }
                .padding(Space.md)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(AppColors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(accent.opacity(0.35), lineWidth: Stroke.hairline)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: isExpanded)
        .animation(.easeOut(duration: 0.2), value: tool.stages.count)
    }

    private var header: some View {
        Button {
            isExpanded.toggle()
        } label: {
            HStack(spacing: Space.sm) {
                ZStack {
                    Circle().fill(wash).frame(width: 24, height: 24)
                    if isBusy {
                        ProgressView().controlSize(.small).scaleEffect(0.7)
                    } else {
                        Image(systemName: "globe")
                            .glyph(Glyph.xs - 1, weight: .semibold)
                            .foregroundStyle(accent)
                    }
                }

                Text(headline)
                    .appType(.meta)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                    // The headline changes as stages land, so cross-fade it
                    // rather than letting it snap between words.
                    .id(headline)
                    .transition(.opacity)

                Spacer(minLength: Space.sm)

                Text("\(tool.stages.count) step\(tool.stages.count == 1 ? "" : "s")")
                    .appType(.caption)
                    .foregroundStyle(accent)
                    .padding(.horizontal, Space.sm)
                    .frame(height: 18)
                    .background(Capsule().fill(wash))

                Image(systemName: "chevron.right")
                    .glyph(Glyph.xs - 3)
                    .foregroundStyle(AppColors.textTertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .padding(.horizontal, Space.md)
            .frame(height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(tool.name), \(headline)")
    }

    private func row(for stage: ResearchStage) -> some View {
        HStack(alignment: .top, spacing: Space.sm) {
            Image(systemName: stage.status == .done ? stage.kindSymbol : stage.symbol)
                .glyph(Glyph.xs, weight: .semibold)
                .foregroundStyle(color(for: stage))
                .frame(width: Glyph.sm)

            VStack(alignment: .leading, spacing: Space.hair) {
                Text(stage.label)
                    .appType(.meta)
                    .foregroundStyle(AppColors.textPrimary)

                if let detail = stage.detail, !detail.isEmpty {
                    Text(detail)
                        .appType(.caption)
                        .foregroundStyle(AppColors.textSecondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
    }

    private func color(for stage: ResearchStage) -> Color {
        switch stage.status {
        case .running: AppColors.info
        case .done: AppColors.success
        case .failed: AppColors.danger
        }
    }
}
