import SwiftUI

/// One tool call, drawn the same way for every model architecture.
///
/// Backends disagree about everything here: some send arguments as compact
/// JSON, some as `{}` for a no-argument tool, some stream them a fragment at a
/// time. The card normalises all of it so a Qwen turn and a Gemma turn look
/// identical, and never shows a reader a raw brace.
struct ToolCallCard: View {
    let tool: ToolInvocation
    var isBusy: Bool = false

    @State private var isExpanded = false

    private var prettyArguments: String? {
        let raw = tool.arguments.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, raw != "{}", raw != "null" else { return nil }
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(
                  withJSONObject: object,
                  options: [.prettyPrinted, .sortedKeys]
              ),
              let text = String(data: pretty, encoding: .utf8) else {
            return raw
        }
        return text
    }

    private var summary: String {
        guard let raw = prettyArguments else { return "No input" }
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "1 input"
        }
        let keys = object.keys.sorted().prefix(2).joined(separator: ", ")
        return object.count > 2 ? "\(keys) +\(object.count - 2)" : keys
    }

    private var accent: Color { isBusy ? AppColors.info : AppColors.success }
    private var wash: Color { isBusy ? AppColors.infoMuted : AppColors.successMuted }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if isExpanded, let prettyArguments {
                Divider().overlay(AppColors.border)
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(prettyArguments)
                        .appType(.mono)
                        .foregroundStyle(AppColors.textSecondary)
                        .textSelection(.enabled)
                        .padding(Space.md)
                }
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
    }

    private var header: some View {
        Button {
            guard prettyArguments != nil else { return }
            isExpanded.toggle()
        } label: {
            HStack(spacing: Space.sm) {
                ZStack {
                    Circle().fill(wash).frame(width: 24, height: 24)
                    if isBusy {
                        ProgressView().controlSize(.small).scaleEffect(0.7)
                    } else {
                        Image(systemName: "wrench.adjustable")
                            .glyph(Glyph.xs - 1, weight: .semibold)
                            .foregroundStyle(accent)
                    }
                }

                Text(tool.name)
                    .appType(.meta)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)

                Text(summary)
                    .appType(.caption)
                    .foregroundStyle(AppColors.textTertiary)
                    .lineLimit(1)

                Spacer(minLength: Space.sm)

                Text(isBusy ? "Running" : "Ran")
                    .appType(.caption)
                    .foregroundStyle(accent)
                    .padding(.horizontal, Space.sm)
                    .frame(height: 18)
                    .background(Capsule().fill(wash))

                if prettyArguments != nil {
                    Image(systemName: "chevron.right")
                        .glyph(Glyph.xs - 3)
                        .foregroundStyle(AppColors.textTertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
            }
            .padding(.horizontal, Space.md)
            .frame(height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(tool.name), \(isBusy ? "running" : "ran"), \(summary)")
    }
}
