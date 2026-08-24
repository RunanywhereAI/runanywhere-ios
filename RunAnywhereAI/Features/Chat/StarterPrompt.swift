import SwiftUI

struct StarterPrompt: Identifiable, Hashable {
    let id: String
    let icon: String
    let title: String
    let subtitle: String
    let text: String
    let tint: PromptTint

    static func set(toolsEnabled: Bool) -> [StarterPrompt] {
        toolsEnabled ? tools : general
    }

    static let general: [StarterPrompt] = [
        StarterPrompt(
            id: "plan",
            icon: "checklist",
            title: "Plan my day",
            subtitle: "Turn a messy list into priorities",
            text: "Turn this messy list into a realistic plan with the top three priorities:",
            tint: .brand
        ),
        StarterPrompt(
            id: "rewrite",
            icon: "text.quote",
            title: "Rewrite clearly",
            subtitle: "Clear, warm and concise",
            text: "Rewrite this so it is clear, warm, and concise:",
            tint: .info
        ),
        StarterPrompt(
            id: "compare",
            icon: "arrow.left.arrow.right",
            title: "Compare options",
            subtitle: "Trade-offs side by side",
            text: "Compare these options and tell me the trade-offs of each:",
            tint: .success
        ),
        StarterPrompt(
            id: "summarize",
            icon: "doc.text.magnifyingglass",
            title: "Summarize notes",
            subtitle: "Decisions and action items",
            text: "Summarize these notes into decisions, action items, and open questions:",
            tint: .info
        ),
        StarterPrompt(
            id: "explain",
            icon: "lightbulb",
            title: "Explain simply",
            subtitle: "Plain language, no jargon",
            text: "Explain this in plain language, without jargon:",
            tint: .brand
        ),
        StarterPrompt(
            id: "debug",
            icon: "ladybug",
            title: "Find the bug",
            subtitle: "Read code and spot the fault",
            text: "Read this code, find the bug, and explain why it fails:",
            tint: .danger
        ),
        StarterPrompt(
            id: "draft",
            icon: "envelope",
            title: "Draft a reply",
            subtitle: "Short and appropriate",
            text: "Draft a short, appropriate reply to this message:",
            tint: .success
        ),
        StarterPrompt(
            id: "brainstorm",
            icon: "sparkles",
            title: "Brainstorm",
            subtitle: "Ten angles, fast",
            text: "Give me ten different angles on this idea, ranked by how promising they are:",
            tint: .brand
        )
    ]

    static let tools: [StarterPrompt] = [
        StarterPrompt(
            id: "weather",
            icon: "cloud.sun",
            title: "Weather",
            subtitle: "Right where I am",
            text: "What is the weather where I am right now?",
            tint: .info
        ),
        StarterPrompt(
            id: "search",
            icon: "globe",
            title: "Search the web",
            subtitle: "Look it up and cite it",
            text: "Search the web and summarize what you find about:",
            tint: .info
        ),
        StarterPrompt(
            id: "calculate",
            icon: "function",
            title: "Calculate",
            subtitle: "Work it out step by step",
            text: "Work this out step by step:",
            tint: .success
        ),
        StarterPrompt(
            id: "device",
            icon: "iphone",
            title: "This device",
            subtitle: "What can it run",
            text: "What are this device's specs, and what size model can it run comfortably?",
            tint: .brand
        ),
        StarterPrompt(
            id: "time",
            icon: "clock",
            title: "Time and date",
            subtitle: "Local, right now",
            text: "What is the current local time and date?",
            tint: .success
        )
    ]
}

enum PromptTint: Hashable {
    case brand
    case info
    case success
    case danger

    var color: Color {
        switch self {
        case .brand: AppColors.brand
        case .info: AppColors.info
        case .success: AppColors.success
        case .danger: AppColors.danger
        }
    }

    var wash: Color {
        switch self {
        case .brand: AppColors.brandMuted
        case .info: AppColors.infoMuted
        case .success: AppColors.successMuted
        case .danger: AppColors.dangerMuted
        }
    }
}

struct PromptSuggestions: View {
    let prompts: [StarterPrompt]
    let onSelect: (StarterPrompt) -> Void

    private let fade: CGFloat = 28

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.sm) {
                ForEach(prompts) { prompt in
                    PromptCard(prompt: prompt) { onSelect(prompt) }
                }
            }
            .padding(.horizontal, fade)
            .frame(maxWidth: .infinity)
        }
        .defaultScrollAnchor(.center)
        .mask(edgeFade)
        .frame(maxWidth: .infinity)
    }

    private var edgeFade: some View {
        GeometryReader { geo in
            let stop = min(fade / max(geo.size.width, 1), 0.5)
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0), location: 0),
                    .init(color: .black, location: stop),
                    .init(color: .black, location: 1 - stop),
                    .init(color: .black.opacity(0), location: 1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }
}

private struct PromptCard: View {
    let prompt: StarterPrompt
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.sm) {
                Image(systemName: prompt.icon)
                    .glyph(Glyph.sm)
                    .foregroundStyle(prompt.tint.color)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(prompt.tint.wash))

                VStack(alignment: .leading, spacing: 0) {
                    Text(prompt.title)
                        .appType(.meta)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)
                    Text(prompt.subtitle)
                        .appType(.caption)
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, Space.sm)
            .padding(.vertical, Space.sm)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(AppColors.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(AppColors.border, lineWidth: Stroke.hairline)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(prompt.title). \(prompt.subtitle)")
    }
}
