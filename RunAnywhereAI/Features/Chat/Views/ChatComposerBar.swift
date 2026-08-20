//
//  ChatComposerBar.swift
//  RunAnywhereAI
//
//  The chat's bottom bar, ported from the Android example's `ChatInputBar` +
//  `PromptSuggestions` so both apps compose a turn the same way.
//
//  The shape is Android's, the idiom is not: circular 44pt targets instead of
//  Material icon buttons, `symbolEffect` swaps instead of Compose crossfades,
//  and every animation routes through `motionAware` so Reduce Motion is honored.
//
//  Order is load-bearing and matches Android top to bottom — divider, blocked
//  reason, attachment rejection, attachment, tool status, the switch row, the
//  editor, the stopping pill. Two of those strips (rejection, attachment) stay
//  visible in `compact` because they are the only two that change what Send
//  does; hiding them left a staged file with no way to see or remove it.
//

import SwiftUI

// MARK: - Palette

/// The two surfaces the composer paints, mapped from Android's Material roles.
///
/// Android sets `background` and `surface` to the same tone (Neutral98 light /
/// Neutral6 dark), so the transcript and the bar are one field and every control
/// stands on `surfaceContainerHigh`, a clear step up from it. That relationship
/// is the whole reason the Android bar reads as a bar.
///
/// The first port used `systemGray6` for controls, which on iOS is the *same
/// value* as `systemGroupedBackground` — so every button, the editor, and every
/// chip painted themselves in the exact color they sat on and disappeared.
/// `systemGray5` is the step that actually exists.
enum ComposerPalette {
    /// The field the bar and the transcript share. Android `surface`.
    static let barFill = AppColors.backgroundGrouped
    /// Buttons, the editor well, chips, strips. Android `surfaceContainerHigh`.
    static let controlFill = AppColors.backgroundGray5
    /// A control whose glyph is live. Android's `primary @ 0.15` container.
    static let activeFill = AppColors.primaryAccent.opacity(0.15)

    /// Glyph inside a composer control. Android `iconMd` is 22dp; an SF Symbol
    /// set at 18pt medium matches that cap height.
    static let glyph = Font.system(size: 18, weight: .medium)
}

// MARK: - Prompt Suggestions

/// The horizontally scrolling starter chips that sit directly above the editor.
///
/// Shown only on an empty transcript, and only while the keyboard is down —
/// a row of prompts above a raised keyboard is a second thing competing for a
/// viewport that has just halved.
struct ChatPromptSuggestionsRow: View {
    let prompts: [StarterPrompt]
    let onSelect: (StarterPrompt) -> Void

    @State private var scrollOffset: CGFloat = 0
    @State private var contentWidth: CGFloat = 0
    @State private var viewportWidth: CGFloat = 0

    private var canScrollBack: Bool { scrollOffset > 1 }
    private var canScrollForward: Bool { contentWidth - scrollOffset - viewportWidth > 1 }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.sm) {
                ForEach(prompts) { prompt in
                    SuggestionPill(prompt: prompt) { onSelect(prompt) }
                }
            }
            .padding(.horizontal, Space.md)
            .background(
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: SuggestionMetricsKey.self,
                        value: SuggestionMetrics(
                            offset: -geometry.frame(in: .named(Self.scrollSpace)).minX,
                            contentWidth: geometry.size.width
                        )
                    )
                }
            )
        }
        .coordinateSpace(name: Self.scrollSpace)
        .onPreferenceChange(SuggestionMetricsKey.self) { metrics in
            scrollOffset = metrics.offset
            contentWidth = metrics.contentWidth
        }
        .background(
            GeometryReader { geometry in
                ComposerPalette.barFill
                    .preference(key: SuggestionViewportKey.self, value: geometry.size.width)
            }
        )
        .onPreferenceChange(SuggestionViewportKey.self) { viewportWidth = $0 }
        .mask(edgeFade)
        .motionAware(Motion.microFade, value: canScrollBack)
        .motionAware(Motion.microFade, value: canScrollForward)
    }

    private static let scrollSpace = "chat.suggestions"

    /// A scrim over whichever edge still has content past it, so an overflowing
    /// row looks scrollable instead of cropped. Only that edge: a chip sliced
    /// flush at the bezel reads as a rendering bug rather than "scroll for
    /// more", and a row that happens to fit should stay crisp.
    ///
    /// A mask rather than an overlaid gradient — the row sits on the same field
    /// as the bar, and a scrim tinted to one appearance is wrong in the other.
    private var edgeFade: some View {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(canScrollBack ? 0 : 1), location: 0),
                .init(color: .black, location: canScrollBack ? Self.fadeFraction : 0),
                .init(color: .black, location: canScrollForward ? 1 - Self.fadeFraction : 1),
                .init(color: .black.opacity(canScrollForward ? 0 : 1), location: 1)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    /// Wide enough to read as a fade at phone width, narrow enough that it never
    /// eats a whole chip.
    private static let fadeFraction: CGFloat = 0.12
}

private struct SuggestionMetrics: Equatable {
    var offset: CGFloat = 0
    var contentWidth: CGFloat = 0
}

private struct SuggestionMetricsKey: PreferenceKey {
    static let defaultValue = SuggestionMetrics()
    static func reduce(value: inout SuggestionMetrics, nextValue: () -> SuggestionMetrics) {
        value = nextValue()
    }
}

private struct SuggestionViewportKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct SuggestionPill: View {
    let prompt: StarterPrompt
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.light()
            action()
        } label: {
            HStack(spacing: Space.xs) {
                if let icon = prompt.icon {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppColors.primaryAccent)
                }
                Text(prompt.title)
                    .appType(.secondary)
                    .foregroundStyle(AppColors.textPrimary)
            }
            .padding(.horizontal, Space.md)
            .padding(.vertical, Space.sm)
            .background(Capsule().fill(ComposerPalette.controlFill))
            .contentShape(Capsule())
        }
        .buttonStyle(ComposerPressStyle())
    }
}

// MARK: - Composer Bar

struct ChatComposerBar: View {
    @Bindable var viewModel: LLMViewModel
    @FocusState.Binding var isTextFieldFocused: Bool

    let imageAttachment: ChatImageAttachment?
    let documentAttachment: ChatDocumentAttachment?
    let attachmentRejection: String?
    let isVisionModelReady: Bool
    let areDocumentModelsReady: Bool
    let canSendCurrentTurn: Bool
    let compact: Bool

    let onRemoveImageAttachment: () -> Void
    let onRemoveDocumentAttachment: () -> Void
    let onDismissAttachmentRejection: () -> Void
    let onChooseVisionModel: () -> Void
    let onChooseDocumentModels: () -> Void
    let onResolveBlocked: () -> Void
    let onComposerAction: (ComposerAction) -> Void
    let onSend: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(AppColors.border)
                .frame(height: Hairline.width)

            VStack(spacing: Space.sm) {
                strips
                switchRow
                editorRow
                if viewModel.isStopping && !compact {
                    StoppingPill().transition(.composerStrip)
                }
            }
            .padding(.horizontal, Space.md)
            .padding(.top, Space.sm)
            .padding(.bottom, compact ? Space.sm : Space.md)
            .measured(Measure.text)
        }
        .background(ComposerPalette.barFill)
        .motionAware(Motion.snappy, value: layoutSignature)
    }

    /// Everything that changes the bar's height in one value, so growth animates
    /// once instead of six modifiers each animating a different subview at its
    /// own speed.
    private var layoutSignature: String {
        [
            viewModel.sendBlockedReason ?? "",
            attachmentRejection ?? "",
            imageAttachment == nil ? "" : "img",
            documentAttachment == nil ? "" : "doc",
            toolStatusMessage ?? "",
            viewModel.isStopping ? "stopping" : "",
            compact ? "compact" : ""
        ].joined(separator: "|")
    }

    // MARK: - Strips

    @ViewBuilder private var strips: some View {
        if let reason = viewModel.sendBlockedReason, !compact {
            BlockedReasonStrip(reason: reason, onResolve: onResolveBlocked)
                .transition(.composerStrip)
        }

        // Deliberately outside the `compact` gate, unlike the strips around it.
        // These two are the only ones that change what Send does.
        if let rejection = attachmentRejection {
            AttachmentRejectionStrip(reason: rejection, onDismiss: onDismissAttachmentRejection)
                .transition(.composerStrip)
        }

        if let imageAttachment {
            ImageAttachmentPill(
                attachment: imageAttachment,
                isVisionModelReady: isVisionModelReady,
                onRemove: onRemoveImageAttachment,
                onChooseVisionModel: onChooseVisionModel
            )
            .transition(.composerStrip)
        }

        if let documentAttachment {
            DocumentAttachmentPill(
                attachment: documentAttachment,
                areModelsReady: areDocumentModelsReady,
                indexState: viewModel.documentIndexState,
                onRemove: onRemoveDocumentAttachment,
                onChooseModels: onChooseDocumentModels
            )
            .transition(.composerStrip)
        }

        if let message = toolStatusMessage, !compact {
            ToolStatusPill(unavailableMessage: viewModel.toolsUnavailableMessage, detail: message)
                .transition(.composerStrip)
        }
    }

    /// The tool strip's second line, or nil when there is nothing to report.
    private var toolStatusMessage: String? {
        if let unavailable = viewModel.toolsUnavailableMessage { return unavailable }
        guard viewModel.toolsEnabled else { return nil }
        return "Trace appears in replies"
    }

    // MARK: - Switch Row

    private var switchRow: some View {
        HStack(spacing: Space.sm) {
            attachmentMenu

            Spacer(minLength: 0)

            ComposerToggle(
                icon: "globe",
                isOn: viewModel.toolsEnabled,
                isEnabled: true,
                label: toolsToggleLabel
            ) {
                viewModel.useToolCalling.toggle()
            }

            ComposerToggle(
                icon: "mic",
                isOn: false,
                isEnabled: true,
                label: "Talk mode"
            ) {
                onComposerAction(.talk)
            }

            // `thinkingSupported` gates the control, not just its value: a model
            // that emits no reasoning has nothing to switch on, and a live toggle
            // over it would promise a trace that can never arrive.
            ComposerToggle(
                icon: "brain",
                isOn: viewModel.thinkingEnabled,
                isEnabled: viewModel.thinkingSupported,
                label: thinkingToggleLabel
            ) {
                viewModel.toggleThinking()
            }
        }
    }

    private var toolsToggleLabel: String {
        if viewModel.toolsEnabled { return "Disable web and tools" }
        if viewModel.toolsUnavailableMessage != nil {
            return "Web and tools unavailable for current model"
        }
        return "Enable web and tools"
    }

    private var thinkingToggleLabel: String {
        if !viewModel.thinkingSupported { return "Thinking not supported by current model" }
        return viewModel.thinkingEnabled ? "Disable thinking" : "Enable thinking"
    }

    /// Attachments and modes, as one native menu. Two-line rows so each says
    /// what it is *for*, matching the Android dropdown — "Image" and "Live
    /// camera" are otherwise near-identical rows.
    private var attachmentMenu: some View {
        Menu {
            Button { onComposerAction(.attachFile) } label: {
                Text("Document")
                Text("Ask with sources")
                Image(systemName: "doc.text")
            }
            Button { onComposerAction(.attachPhoto) } label: {
                Text("Image")
                Text("Ask about a photo")
                Image(systemName: "photo")
            }
            Button { onComposerAction(.takePhoto) } label: {
                Text("Live camera")
                Text("Look with vision")
                Image(systemName: "eye")
            }
            Button { onComposerAction(.pasteAttachment) } label: {
                Text("Paste")
                Text("Attach the clipboard")
                Image(systemName: "doc.on.clipboard")
            }
            .disabled(!ChatAttachmentLoader.pasteboardHasAttachment)
            #if os(iOS)
            // Android's fourth row. iOS only, because the Mac reaches Advanced
            // from its sidebar and a second route to one screen is how a menu
            // stops meaning anything.
            Button { onComposerAction(.openAdvanced) } label: {
                Text("Advanced tools")
                Text("SDK demos and diagnostics")
                Image(systemName: "slider.horizontal.3")
            }
            #endif
        } label: {
            Image(systemName: "line.3.horizontal")
                .font(ComposerPalette.glyph)
                .foregroundStyle(AppColors.textSecondary)
                .frame(width: Measure.hitTarget, height: Measure.hitTarget)
                .background(Circle().fill(ComposerPalette.controlFill))
                .contentShape(Circle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Attach or open a mode")
    }

    // MARK: - Editor

    private var editorRow: some View {
        HStack(alignment: .bottom, spacing: Space.sm) {
            TextField(placeholder, text: $viewModel.currentInput, axis: .vertical)
                .textFieldStyle(.plain)
                .appType(.body)
                .lineLimit(compact ? 1...2 : 1...5)
                .padding(.horizontal, Space.lg)
                .padding(.vertical, Space.md)
                .frame(minHeight: Measure.hitTarget, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(ComposerPalette.controlFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(
                            isTextFieldFocused ? AppColors.primaryAccent.opacity(0.5) : .clear,
                            lineWidth: Stroke.regular
                        )
                )
                .focused($isTextFieldFocused)
                .onSubmit(onSend)
                .submitLabel(.send)
                .accessibilityLabel("Message input")
                .motionAware(Motion.microFade, value: isTextFieldFocused)

            sendButton
        }
    }

    /// One slot, two roles. A single Button whose symbol is computed rather than
    /// two siblings, so `.symbolEffect(.replace)` fires and the row never
    /// reflows when Send becomes Stop mid-sentence.
    private var sendButton: some View {
        Button {
            Haptics.light()
            if viewModel.isGenerating { viewModel.stopGeneration() } else { onSend() }
        } label: {
            Image(systemName: viewModel.isGenerating ? "stop.fill" : "arrow.up")
                .font(ComposerPalette.glyph.weight(.semibold))
                .foregroundStyle(sendIsEnabled ? AppColors.onBrandLarge : AppColors.textTertiary)
                .frame(width: Measure.hitTarget, height: Measure.hitTarget)
                .background(
                    Circle().fill(sendIsEnabled ? AppColors.primaryAccent : ComposerPalette.controlFill)
                )
                .contentShape(Circle())
        }
        .buttonStyle(ComposerPressStyle())
        .disabled(!sendIsEnabled)
        .accessibilityLabel(viewModel.isGenerating ? "Stop" : "Send message")
        .contentTransition(.symbolEffect(.replace))
        .motionAware(Motion.snappy, value: sendIsEnabled)
        .motionAware(Motion.snappy, value: viewModel.isGenerating)
    }

    private var sendIsEnabled: Bool {
        viewModel.isGenerating || canSendCurrentTurn
    }

    private var placeholder: String {
        // The attachment wins: it is the more specific fact about what pressing
        // Send will do right now.
        if imageAttachment != nil { return "Add a question, or send to describe this image" }
        if documentAttachment != nil { return "Add a question, or send to describe this file" }
        return viewModel.toolsEnabled ? "Ask with web and tools…" : "Ask anything…"
    }
}

// MARK: - Toggle

/// A circular switch in the composer's action row.
///
/// The fill is what carries state, not the glyph — a tinted glyph on an untinted
/// ground is easy to miss on a row of three. `symbolEffect(.bounce)` fires on
/// the value change so a toggle reads as a thing that just happened rather than
/// a color that quietly differs from a second ago.
private struct ComposerToggle: View {
    let icon: String
    let isOn: Bool
    let isEnabled: Bool
    let label: String
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            Image(systemName: icon)
                .font(ComposerPalette.glyph)
                .foregroundStyle(foreground)
                .symbolEffect(.bounce, value: isOn)
                .frame(width: Measure.hitTarget, height: Measure.hitTarget)
                .background(Circle().fill(background))
                .contentShape(Circle())
        }
        .buttonStyle(ComposerPressStyle())
        .disabled(!isEnabled)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
        .motionAware(Motion.snappy, value: isOn)
        .motionAware(Motion.microFade, value: isEnabled)
    }

    private var foreground: Color {
        if !isEnabled { return AppColors.textTertiary.opacity(0.5) }
        return isOn ? AppColors.primaryAccent : AppColors.textSecondary
    }

    private var background: Color {
        isOn ? ComposerPalette.activeFill : ComposerPalette.controlFill
    }
}

/// Presses shrink a hair. iOS has no ripple, and a circular target that does not
/// move under the thumb reads as unresponsive on a row of four.
private struct ComposerPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .motionAware(Motion.snappy, value: configuration.isPressed)
    }
}

// MARK: - Strips

/// The one blocker between a written message and an answer, plus the tap that
/// clears it.
///
/// Deliberately not an error color: nothing has gone wrong on a first launch,
/// the user simply has not chosen a model yet, and red here would read as a
/// fault they caused.
private struct BlockedReasonStrip: View {
    let reason: String
    let onResolve: () -> Void

    var body: some View {
        Button(action: onResolve) {
            HStack(spacing: Space.sm) {
                Image(systemName: "cube")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.primaryAccent)

                VStack(alignment: .leading, spacing: Space.hair) {
                    Text(reason)
                        .appType(.chip)
                        .foregroundStyle(AppColors.textPrimary)
                    Text("Tap to choose one — it downloads and runs on this device.")
                        .appType(.meta)
                        .foregroundStyle(AppColors.textSecondary)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)
            }
            .padding(.horizontal, Space.md)
            .padding(.vertical, Space.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(ComposerPalette.controlFill)
            )
            .contentShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
        .buttonStyle(ComposerPressStyle())
    }
}

/// The file the composer would not take, and why.
///
/// Error-colored, unlike `BlockedReasonStrip`: something the user did was
/// refused, and softening that into a neutral hint would leave them wondering
/// whether the attachment went through.
private struct AttachmentRejectionStrip: View {
    let reason: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: Space.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold))
            Text(reason)
                .appType(.chip)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: Measure.hitTarget, height: Measure.hitTarget)
                    .contentShape(Circle())
            }
            .buttonStyle(ComposerPressStyle())
            .accessibilityLabel("Dismiss")
        }
        .foregroundStyle(AppColors.dangerText)
        .padding(.leading, Space.md)
        .padding(.vertical, Space.xs)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(AppColors.danger.opacity(0.12))
        )
    }
}

private struct ToolStatusPill: View {
    let unavailableMessage: String?
    let detail: String

    private var isUnavailable: Bool { unavailableMessage != nil }

    var body: some View {
        HStack(spacing: Space.xs) {
            Image(systemName: isUnavailable ? "exclamationmark.triangle.fill" : "globe")
                .font(.system(size: 12, weight: .semibold))

            VStack(alignment: .leading, spacing: Space.hair) {
                Text(isUnavailable ? "Web & tools unavailable" : "Web & tools on")
                    .appType(.chip)
                Text(detail)
                    .appType(.meta)
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(isUnavailable ? 2 : 1)
            }

            Spacer(minLength: 0)
        }
        .foregroundStyle(isUnavailable ? AppColors.dangerText : AppColors.primaryAccent)
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill((isUnavailable ? AppColors.danger : AppColors.primaryAccent).opacity(0.12))
        )
    }
}

private struct StoppingPill: View {
    var body: some View {
        Text("Stopping the previous response… You can keep typing.")
            .appType(.chip)
            .foregroundStyle(AppColors.textSecondary)
            .padding(.horizontal, Space.md)
            .padding(.vertical, Space.xs)
            .background(Capsule().fill(ComposerPalette.controlFill))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Transition

extension AnyTransition {
    /// Fade plus the stack's own reflow, which is what makes a strip appear to
    /// push the editor down rather than land on top of it. Asymmetric so a strip
    /// the user dismissed leaves without re-animating its arrival.
    static var composerStrip: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .move(edge: .bottom)),
            removal: .opacity
        )
    }
}
