import SwiftUI

/// A suggestion the reader finishes rather than a card they read.
///
/// `verb` is what the sentence starts with and `continuation` is where it was
/// going; `text` is the full prompt the field is seeded with.
struct StarterPrompt: Identifiable, Hashable {
    let id: String
    let verb: String
    let continuation: String
    let text: String

    static func set(toolsEnabled: Bool) -> [StarterPrompt] {
        toolsEnabled ? tools : general
    }

    static let general: [StarterPrompt] = [
        StarterPrompt(
            id: "plan",
            verb: "Plan",
            continuation: "a realistic day",
            text: "Turn this messy list into a realistic plan with the top three priorities:"
        ),
        StarterPrompt(
            id: "explain",
            verb: "Explain",
            continuation: "something confusing",
            text: "Explain this in plain language, without jargon:"
        ),
        StarterPrompt(
            id: "rewrite",
            verb: "Rewrite",
            continuation: "this more clearly",
            text: "Rewrite this so it is clear, warm, and concise:"
        ),
        StarterPrompt(
            id: "summarize",
            verb: "Summarize",
            continuation: "a page of notes",
            text: "Summarize these notes into decisions, action items, and open questions:"
        ),
        StarterPrompt(
            id: "draft",
            verb: "Draft",
            continuation: "a reply I keep putting off",
            text: "Draft a short, appropriate reply to this message:"
        )
    ]

    static let tools: [StarterPrompt] = [
        StarterPrompt(
            id: "search",
            verb: "Look up",
            continuation: "what happened today",
            text: "Search the web and summarize what you find about:"
        ),
        StarterPrompt(
            id: "weather",
            verb: "Check",
            continuation: "the weather here",
            text: "What is the weather where I am right now?"
        ),
        StarterPrompt(
            id: "calculate",
            verb: "Work out",
            continuation: "a number, step by step",
            text: "Work this out step by step:"
        ),
        StarterPrompt(
            id: "compare",
            verb: "Compare",
            continuation: "two things properly",
            text: "Search the web, then compare these and tell me the trade-offs of each:"
        )
    ]
}

struct PromptSuggestions: View {
    let prompts: [StarterPrompt]
    let onSelect: (StarterPrompt) -> Void

    private let fade: CGFloat = Space.xl

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: Space.lg) {
                ForEach(prompts) { prompt in
                    PromptPhrase(prompt: prompt) { onSelect(prompt) }
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

private struct PromptPhrase: View {
    let prompt: StarterPrompt
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Space.hair) {
                Text(prompt.verb)
                    .appType(.cardTitle)
                    .foregroundStyle(AppColors.textPrimary)

                Text(prompt.continuation)
                    .appType(.meta)
                    .foregroundStyle(AppColors.textTertiary)
            }
            .lineLimit(1)
            .padding(.horizontal, Space.md)
            .padding(.vertical, Space.sm)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(isHovered ? AppColors.surfaceMuted : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            withAnimation(Motion.fade) { isHovered = inside }
        }
        .accessibilityLabel("\(prompt.verb) \(prompt.continuation)")
    }
}
