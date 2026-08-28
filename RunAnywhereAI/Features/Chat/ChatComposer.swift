import SwiftUI

enum ComposerMetrics {
    static var control: CGFloat {
        #if os(macOS)
        30
        #else
        Measure.hitTarget
        #endif
    }

    static var glyph: CGFloat {
        #if os(macOS)
        Glyph.sm
        #else
        Glyph.md
        #endif
    }

    static let gap = Space.sm
    static let inset = Space.md
    static let rowSpacing = Space.sm
    static let radius = Radius.lg
}

enum ComposerAction {
    case attachDocument
    case attachImage
    case liveCamera
    case talk
    case resolveBlocked
    case chooseModel
    case acceptModelSwitch
    case declineModelSwitch
    case voiceMode
}

struct ChatComposer: View {
    @Bindable var model: ChatComposerModel
    var recording: RecordingState?
    var onAction: (ComposerAction) -> Void = { _ in }
    var onSend: () -> Void = {}

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if let recording {
                RecordingBar(
                    levels: recording.levels,
                    isPaused: recording.isPaused,
                    elapsed: recording.elapsed,
                    transcript: recording.transcript,
                    diagnostics: recording.diagnostics,
                    onPauseResume: recording.onPauseResume,
                    onDiscard: recording.onDiscard,
                    onFinish: recording.onFinish
                )
            } else if model.showsPrompts {
                PromptSuggestions(prompts: model.prompts) { prompt in
                    model.apply(prompt)
                    isFocused = true
                }
                .padding(.top, Space.lg)
                .padding(.bottom, Space.md)
                .id(model.toolsEnabled)
                .transition(.opacity)
            }

            if recording == nil {
                VStack(spacing: ComposerMetrics.rowSpacing) {
                    strips
                    if model.hasActiveModes {
                        modeChips.transition(.composerStrip)
                    }
                    editorRow
                    if model.isStopping {
                        stoppingPill.transition(.composerStrip)
                    }
                }
                .padding(.horizontal, ComposerMetrics.inset)
                .padding(.vertical, Space.md)
            }
        }
        .measured()
        .animation(.easeInOut(duration: 0.28), value: layoutSignature)
    }

    private var layoutSignature: String {
        [
            model.blockedReason ?? "",
            model.attachmentRejection ?? "",
            model.notice ?? "",
            model.staged?.filename ?? "",
            model.modelSwitch?.modelID ?? "",
            model.stagedDetail,
            model.toolsUnavailableMessage ?? "",
            model.isStopping ? "stopping" : "",
            model.showsPrompts ? "prompts" : "",
            model.toolsEnabled ? "tools" : "",
            model.thinkingEnabled ? "thinking" : ""
        ].joined(separator: "|")
    }

    @ViewBuilder
    private var strips: some View {
        if let reason = model.blockedReason {
            ComposerStrip(
                symbol: "exclamationmark.triangle",
                tint: AppColors.danger,
                wash: AppColors.dangerMuted,
                title: "Cannot send",
                detail: reason
            ) {
                Button("Fix") { onAction(.resolveBlocked) }
                    .appType(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(AppColors.danger)
            }
            .transition(.composerStrip)
        }

        if let rejection = model.attachmentRejection {
            ComposerStrip(
                symbol: "paperclip.badge.ellipsis",
                tint: AppColors.danger,
                wash: AppColors.dangerMuted,
                title: "Attachment not added",
                detail: rejection
            ) {
                StripButton(symbol: "xmark", label: "Dismiss") {
                    model.dismissRejection()
                }
            }
            .transition(.composerStrip)
        }

        if let notice = model.notice {
            ComposerStrip(
                symbol: model.noticeSymbol,
                tint: AppColors.danger,
                wash: AppColors.dangerMuted,
                title: model.noticeTitle,
                detail: notice
            ) {
                StripButton(symbol: "xmark", label: "Dismiss") {
                    model.notice = nil
                }
            }
            .transition(.composerStrip)
        }

        if let staged = model.staged {
            ComposerStrip(
                symbol: staged.symbol,
                tint: model.stagedTint,
                wash: model.stagedWash,
                title: staged.filename,
                detail: model.stagedDetail
            ) {
                StripButton(symbol: "xmark", label: "Remove attachment") {
                    model.removeAttachment()
                }
            }
            .transition(.composerStrip)
        }

        if let offer = model.modelSwitch {
            ModelSwitchStrip(
                offer: offer,
                onAccept: { onAction(.acceptModelSwitch) },
                onDecline: { onAction(.declineModelSwitch) }
            )
            .transition(.composerStrip)
        }

        if let unavailable = model.toolsUnavailableMessage {
            ComposerStrip(
                symbol: "globe.badge.chevron.backward",
                tint: AppColors.textTertiary,
                wash: AppColors.surfaceMuted,
                title: "Tools unavailable",
                detail: unavailable
            ) {
                EmptyView()
            }
            .transition(.composerStrip)
        }
    }

    /// Web and thinking live in the plus menu, so this is the only thing that
    /// says they are on. Each chip is also how they are turned off again.
    private var modeChips: some View {
        HStack(spacing: Space.sm) {
            if model.toolsEnabled {
                ModeChip(symbol: "globe", title: "Web search") {
                    withAnimation(.easeInOut(duration: 0.28)) { model.toolsEnabled = false }
                }
            }
            if model.thinkingEnabled {
                ModeChip(symbol: "brain", title: "Thinking") {
                    withAnimation(.easeInOut(duration: 0.28)) { model.thinkingEnabled = false }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var stoppingPill: some View {
        HStack(spacing: Space.sm) {
            ProgressView()
                .controlSize(.small)
            Text("Stopping…")
                .appType(.caption)
                .foregroundStyle(AppColors.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.xs)
        .background(Capsule().fill(AppColors.surfaceMuted))
    }

    private var plusMenu: some View {
        Menu {
            Button { onAction(.attachDocument) } label: {
                Text("Document")
                Text("Ask with sources")
                Image(systemName: "doc.text")
            }
            Button { onAction(.attachImage) } label: {
                Text("Image")
                Text("Ask about a photo")
                Image(systemName: "photo")
            }
            Button { onAction(.liveCamera) } label: {
                Text("Live camera")
                Text("Look with vision")
                Image(systemName: "eye")
            }

            Divider()

            Toggle(isOn: $model.toolsEnabled) {
                Label("Search the web", systemImage: "globe")
            }
            .disabled(!model.toolsSupported)

            Toggle(isOn: $model.thinkingEnabled) {
                Label("Think it through", systemImage: "brain")
            }
            .disabled(!model.thinkingSupported)
        } label: {
            ComposerGlyph(symbol: "plus", isEmphasised: model.hasActiveModes)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Attach, and change how the next message runs")
    }

    private var editorRow: some View {
        HStack(alignment: .bottom, spacing: ComposerMetrics.gap) {
            plusMenu

            TextField(model.placeholder, text: $model.draft, axis: .vertical)
                .textFieldStyle(.plain)
                .appType(.body)
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1...5)
                .padding(.horizontal, ComposerMetrics.inset)
                .padding(.vertical, Space.sm)
                .frame(minHeight: ComposerMetrics.control, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: ComposerMetrics.radius, style: .continuous)
                        .fill(AppColors.surfaceMuted)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: ComposerMetrics.radius, style: .continuous)
                        .strokeBorder(
                            isFocused ? AppColors.brand.opacity(0.55) : AppColors.border,
                            lineWidth: Stroke.hairline
                        )
                )
                .focused($isFocused)
                // Return bypassed the disabled Send button entirely, which is
                // how a turn was sent with no model loaded.
                .onSubmit { if sendEnabled { onSend() } }
                .accessibilityLabel("Message input")

            Button { onAction(.talk) } label: {
                ComposerGlyph(symbol: "mic", isEmphasised: false)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dictate")

            // Two different things share this corner: the microphone types for
            // you, this holds a conversation. Voice mode used to be reachable
            // only from the More screen, which developer mode hides.
            Button { onAction(.voiceMode) } label: {
                ComposerGlyph(symbol: "waveform.circle", isEmphasised: false)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Voice mode")

            sendButton
        }
    }

    private var sendButton: some View {
        Button {
            onSend()
        } label: {
            Image(systemName: model.isGenerating ? "stop.fill" : "arrow.up")
                .glyph(ComposerMetrics.glyph, weight: .semibold)
                .foregroundStyle(sendEnabled ? AppColors.onBrand : AppColors.textTertiary)
                .frame(width: ComposerMetrics.control, height: ComposerMetrics.control)
                .background(Circle().fill(sendEnabled ? AppColors.brand : AppColors.surfaceMuted))
                .overlay(
                    Circle().strokeBorder(
                        sendEnabled ? Color.clear : AppColors.border,
                        lineWidth: Stroke.hairline
                    )
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!sendEnabled)
        .accessibilityLabel(model.isGenerating ? "Stop" : "Send message")
        .contentTransition(.symbolEffect(.replace))
    }

    private var sendEnabled: Bool {
        model.isGenerating || model.canSend
    }
}

/// The round glyph the composer's secondary controls wear.
struct ComposerGlyph: View {
    let symbol: String
    var isEmphasised = false

    var body: some View {
        Image(systemName: symbol)
            .glyph(ComposerMetrics.glyph)
            .foregroundStyle(isEmphasised ? AppColors.brand : AppColors.textSecondary)
            .frame(width: ComposerMetrics.control, height: ComposerMetrics.control)
            .background(Circle().fill(isEmphasised ? AppColors.brandMuted : AppColors.surfaceMuted))
            .overlay(
                Circle().strokeBorder(
                    isEmphasised ? AppColors.brand.opacity(0.45) : AppColors.border,
                    lineWidth: Stroke.hairline
                )
            )
            .contentShape(Circle())
    }
}

struct ModeChip: View {
    let symbol: String
    let title: String
    let onClear: () -> Void

    var body: some View {
        Button(action: onClear) {
            HStack(spacing: Space.xs) {
                Image(systemName: symbol)
                    .glyph(Glyph.xs - 2, weight: .semibold)
                Text(title)
                    .appType(.chip)
                Image(systemName: "xmark")
                    .glyph(Glyph.xs - 3, weight: .semibold)
                    .foregroundStyle(AppColors.brand.opacity(0.6))
            }
            .foregroundStyle(AppColors.brand)
            .padding(.horizontal, Space.sm)
            .frame(height: Control.tag)
            .background(Capsule().fill(AppColors.brandMuted))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) is on. Turn it off.")
    }
}

struct RecordingState {
    let levels: [Float]
    let isPaused: Bool
    let elapsed: TimeInterval
    let transcript: String
    let diagnostics: String
    let onPauseResume: () -> Void
    let onDiscard: () -> Void
    let onFinish: () -> Void
}
