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
                .padding(.top, Space.md)
                .padding(.bottom, Space.xs)
                .id(model.toolsEnabled)
                .transition(.opacity)
            }

            if recording == nil {
            VStack(spacing: ComposerMetrics.rowSpacing) {
                strips
                switchRow
                editorRow
                if model.isStopping {
                    stoppingPill.transition(.composerStrip)
                }
            }
            .padding(.horizontal, ComposerMetrics.inset)
            .padding(.vertical, ComposerMetrics.gap)
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
            model.stagedDetail,
            model.toolStatus ?? "",
            model.isStopping ? "stopping" : "",
            model.showsPrompts ? "prompts" : "",
            model.toolsEnabled ? "tools" : ""
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
                    model.staged = nil
                }
            }
            .transition(.composerStrip)
        }

        if let status = model.toolStatus {
            ComposerStrip(
                symbol: model.toolsUnavailableMessage == nil ? "globe" : "globe.badge.chevron.backward",
                tint: model.toolsUnavailableMessage == nil ? AppColors.brand : AppColors.textTertiary,
                wash: model.toolsUnavailableMessage == nil ? AppColors.brandMuted : AppColors.surfaceMuted,
                title: model.toolsUnavailableMessage == nil ? "Web and tools on" : "Tools unavailable",
                detail: status
            ) {
                EmptyView()
            }
            .transition(.composerStrip)
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

    private var switchRow: some View {
        HStack(spacing: ComposerMetrics.gap) {
            attachmentMenu

            Spacer(minLength: 0)

            ComposerToggle(
                icon: "globe",
                isOn: model.toolsEnabled,
                isEnabled: model.toolsSupported,
                label: model.toolsLabel
            ) {
                withAnimation(.easeInOut(duration: 0.28)) {
                    model.toolsEnabled.toggle()
                }
            }

            ComposerToggle(
                icon: "mic",
                isOn: false,
                isEnabled: true,
                label: "Talk mode"
            ) {
                onAction(.talk)
            }

            ComposerToggle(
                icon: "brain",
                isOn: model.thinkingEnabled,
                isEnabled: model.thinkingSupported,
                label: thinkingLabel
            ) {
                model.toggleThinking()
            }
        }
    }

    private var thinkingLabel: String {
        guard model.thinkingSupported else { return "Thinking not supported by current model" }
        return model.thinkingEnabled ? "Disable thinking" : "Enable thinking"
    }

    private var attachmentMenu: some View {
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
        } label: {
            Image(systemName: "plus")
                .glyph(ComposerMetrics.glyph)
                .foregroundStyle(AppColors.textSecondary)
                .frame(width: ComposerMetrics.control, height: ComposerMetrics.control)
                .background(Circle().fill(AppColors.surfaceMuted))
                .overlay(Circle().strokeBorder(AppColors.border, lineWidth: Stroke.hairline))
                .contentShape(Circle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Attach")
    }

    private var editorRow: some View {
        HStack(alignment: .bottom, spacing: ComposerMetrics.gap) {
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

struct ComposerToggle: View {
    let icon: String
    let isOn: Bool
    let isEnabled: Bool
    let label: String
    let action: () -> Void

    private var tint: Color {
        guard isEnabled else { return AppColors.textTertiary }
        return isOn ? AppColors.brand : AppColors.textSecondary
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .glyph(ComposerMetrics.glyph)
                .foregroundStyle(tint)
                .frame(width: ComposerMetrics.control, height: ComposerMetrics.control)
                .background(Circle().fill(isOn ? AppColors.brandMuted : AppColors.surfaceMuted))
                .overlay(
                    Circle().strokeBorder(
                        isOn ? AppColors.brand.opacity(0.45) : AppColors.border,
                        lineWidth: Stroke.hairline
                    )
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .help(label)
        .accessibilityLabel(label)
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
