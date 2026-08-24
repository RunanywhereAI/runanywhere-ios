import SwiftUI

struct ChatTranscript: View {
    let turns: [ChatTurn]
    let streamingID: UUID?
    let speakingID: UUID?
    var speakingProgress: Double = 0
    let onAction: (TurnAction, ChatTurn) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Space.xl) {
                    ForEach(turns) { turn in
                        TurnView(
                            turn: turn,
                            isStreaming: turn.id == streamingID,
                            isSpeaking: turn.id == speakingID,
                            speakingProgress: speakingProgress,
                            onAction: onAction
                        )
                        .id(turn.id)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }

                    Color.clear
                        .frame(height: 1)
                        .id(bottomAnchor)
                }
                .padding(.horizontal, Space.lg)
                .padding(.vertical, Space.xl)
                .measured()
            }
            .onChange(of: turns.last?.id) { _, _ in
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo(bottomAnchor, anchor: .bottom)
                }
            }
            .onChange(of: turns.last?.text.count) { _, _ in
                proxy.scrollTo(bottomAnchor, anchor: .bottom)
            }
        }
    }

    private var bottomAnchor: String { "transcript.bottom" }
}

enum TurnAction {
    case copy
    case speak
    case fork
    case retry
    case delete
}

private struct TurnView: View, Equatable {
    let turn: ChatTurn
    let isStreaming: Bool
    let isSpeaking: Bool
    let speakingProgress: Double
    let onAction: (TurnAction, ChatTurn) -> Void

    @State private var showThinking = false
    @State private var isHovering = false

    static func == (lhs: TurnView, rhs: TurnView) -> Bool {
        lhs.turn == rhs.turn
            && lhs.isStreaming == rhs.isStreaming
            && lhs.isSpeaking == rhs.isSpeaking
            && lhs.speakingProgress == rhs.speakingProgress
    }

    var body: some View {
        VStack(alignment: turn.role == .user ? .trailing : .leading, spacing: Space.sm) {
            if turn.role == .user {
                userBubble
            } else {
                assistantBody
            }

            if turn.role == .assistant, !turn.isEmpty {
                actions
                    .opacity(isHovering || isStreaming ? 1 : 0.35)
                    .animation(.easeOut(duration: 0.18), value: isHovering)
            }
        }
        .frame(maxWidth: .infinity, alignment: turn.role == .user ? .trailing : .leading)
        .onHover { isHovering = $0 }
    }

    @ViewBuilder
    private var userBubble: some View {
        VStack(alignment: .trailing, spacing: Space.xs) {
            if let name = turn.attachmentName {
                AttachmentChip(name: name, isImage: turn.attachmentIsImage)
            }
            if !turn.text.isEmpty {
                userText
            }
        }
        .frame(maxWidth: 520, alignment: .trailing)
    }

    private var userText: some View {
        Text(turn.text)
            .appType(.body)
            .foregroundStyle(AppColors.onBrand)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            .padding(.horizontal, Space.lg)
            .padding(.vertical, Space.md)
            .background(
                RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .fill(AppColors.brand)
            )
    }

    @ViewBuilder
    private var assistantBody: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            if turn.hasThinking {
                ThinkingDisclosure(text: turn.thinking, isOpen: $showThinking, isStreaming: isStreaming)
                    .transition(.opacity.combined(with: .offset(y: -4)))
            }

            if !turn.tools.isEmpty {
                VStack(alignment: .leading, spacing: Space.xs) {
                    ForEach(turn.tools) { tool in
                        Group {
                            if tool.isMultiStage {
                                ResearchProgressCard(tool: tool, isBusy: !tool.isComplete)
                            } else {
                                ToolCallCard(tool: tool, isBusy: !tool.isComplete)
                            }
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .animation(.easeInOut(duration: 0.22), value: turn.tools)
            }

            if turn.text.isEmpty, isStreaming, turn.tools.isEmpty, !turn.hasThinking {
                WorkingIndicator()
            }

            if !turn.text.isEmpty || (isStreaming && !turn.tools.isEmpty) {
                StreamingText(text: turn.text, isStreaming: isStreaming)
            }

            if let failure = turn.failure {
                Label(failure, systemImage: "exclamationmark.triangle")
                    .appType(.meta)
                    .foregroundStyle(AppColors.danger)
                    .padding(.horizontal, Space.md)
                    .padding(.vertical, Space.sm)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .fill(AppColors.dangerMuted)
                    )
            }

            if turn.wasCancelled {
                Text("Stopped")
                    .appType(.caption)
                    .foregroundStyle(AppColors.textTertiary)
            }
        }
    }

    private var actions: some View {
        HStack(spacing: Space.xs) {
            if !turn.metrics.isEmpty {
                Text(metricsLabel)
                    .appType(.caption)
                    .monospacedDigit()
                    .foregroundStyle(AppColors.textTertiary)
                    .padding(.trailing, Space.xs)
            }

            MicroAction(symbol: "doc.on.doc", label: "Copy") { onAction(.copy, turn) }
            SpeakButton(isSpeaking: isSpeaking, progress: speakingProgress) {
                onAction(.speak, turn)
            }

            ShareLink(item: turn.text) {
                Image(systemName: "square.and.arrow.up")
                    .glyph(Glyph.xs)
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Share")

            MicroAction(symbol: "arrow.triangle.branch", label: "Fork from here") { onAction(.fork, turn) }
            MicroAction(symbol: "arrow.clockwise", label: "Retry") { onAction(.retry, turn) }
            MicroAction(symbol: "trash", label: "Delete", tint: AppColors.danger) { onAction(.delete, turn) }

            Spacer(minLength: 0)
        }
    }

    private var metricsLabel: String {
        var parts: [String] = []
        if turn.metrics.timeToFirstTokenMs > 0 {
            parts.append("\(turn.metrics.timeToFirstTokenMs) ms to first token")
        }
        if turn.metrics.tokensPerSecond > 0 {
            parts.append(String(format: "%.1f tok/s", turn.metrics.tokensPerSecond))
        }
        return parts.joined(separator: " · ")
    }
}

private struct MicroAction: View {
    let symbol: String
    let label: String
    var tint: Color?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .glyph(Glyph.xs)
                .foregroundStyle(tint ?? AppColors.textSecondary)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

private struct StreamingText: View {
    let text: String
    let isStreaming: Bool

    /// Parsed once per text change rather than per render.
    ///
    /// `body` runs on every token while a reply streams, and re-parsing a
    /// multi-kilobyte answer that often is wasted work. The cache keys on the
    /// text itself, so a turn that stopped changing stops parsing.
    @State private var cache: (source: String, blocks: [MarkdownBlock])?

    private var blocks: [MarkdownBlock] {
        if let cache, cache.source == text { return cache.blocks }
        return MarkdownBlockParser.parse(text)
    }

    var body: some View {
        MarkdownView(
            blocks: blocks,
            trailing: isStreaming ? Text(" ▍").foregroundColor(AppColors.brand) : nil
        )
        .onChange(of: text, initial: true) { _, value in
            cache = (value, MarkdownBlockParser.parse(value))
        }
    }
}

private struct ThinkingDisclosure: View {
    let text: String
    @Binding var isOpen: Bool
    let isStreaming: Bool

    @State private var shimmer: CGFloat = -1
    @State private var breathe = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            header

            if isOpen {
                Text(text)
                    .appType(.secondary)
                    .foregroundStyle(AppColors.textSecondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(Space.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(AppColors.surfaceMuted)
                    )
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .offset(y: -6)).combined(with: .scale(scale: 0.98, anchor: .top)),
                            removal: .opacity.combined(with: .offset(y: -4))
                        )
                    )
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: isOpen)
        .animation(.easeInOut(duration: 0.3), value: isStreaming)
    }

    private var header: some View {
        Button {
            isOpen.toggle()
        } label: {
            HStack(spacing: Space.xs) {
                Image(systemName: "brain")
                    .glyph(Glyph.xs)
                    .symbolEffect(.pulse, isActive: isStreaming)

                Text(isStreaming ? "Thinking…" : "Thought process")
                    .appType(.meta)
                    .contentTransition(.opacity)

                Image(systemName: "chevron.right")
                    .glyph(Glyph.xs - 3)
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
            }
            .foregroundStyle(AppColors.info)
            .padding(.horizontal, Space.md)
            .frame(height: 26)
            .background(capsuleBackground)
            .overlay(shimmerOverlay)
            .clipShape(Capsule())
            .scaleEffect(breathe ? 1.015 : 1)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onChange(of: isStreaming, initial: true) { _, streaming in
            guard streaming else {
                breathe = false
                return
            }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                breathe = true
            }
            withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                shimmer = 2
            }
        }
    }

    private var capsuleBackground: some View {
        Capsule().fill(AppColors.infoMuted)
    }

    @ViewBuilder
    private var shimmerOverlay: some View {
        if isStreaming {
            GeometryReader { geo in
                LinearGradient(
                    colors: [
                        AppColors.info.opacity(0),
                        AppColors.info.opacity(0.22),
                        AppColors.info.opacity(0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: geo.size.width * 0.6)
                .offset(x: shimmer * geo.size.width)
            }
            .allowsHitTesting(false)
        }
    }
}

private struct WorkingIndicator: View {
    @State private var phase = 0.0

    var body: some View {
        HStack(spacing: Space.xs) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(AppColors.textTertiary)
                    .frame(width: 5, height: 5)
                    .opacity(0.35 + 0.65 * abs(sin(phase + Double(index) * 0.6)))
            }
        }
        .frame(height: 18)
        .onAppear {
            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                phase = .pi * 2
            }
        }
        .accessibilityLabel("Working")
    }
}


/// What the reader sees on their own turn when they attached something. The
/// bubble stays about the question; the file is named beside it rather than
/// dumped into the prose.
struct AttachmentChip: View {
    let name: String
    let isImage: Bool

    var body: some View {
        HStack(spacing: Space.xs) {
            Image(systemName: isImage ? "photo" : "doc.text")
                .glyph(Glyph.xs, weight: .semibold)
            Text(name)
                .appType(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .foregroundStyle(AppColors.textSecondary)
        .padding(.horizontal, Space.sm)
        .frame(height: 24)
        .background(Capsule().fill(AppColors.surfaceMuted))
        .overlay(Capsule().strokeBorder(AppColors.border, lineWidth: Stroke.hairline))
        .accessibilityLabel("Attached \(name)")
    }
}
