//
//  ChatMessageListView.swift
//  RunAnywhereAI
//
//  The transcript and the composer.
//
//  Two things here are deliberate and easy to undo by accident:
//
//  1. **Zero scroll drivers.** There used to be six (`messages.count`,
//     `isGenerating`, focus + a 0.3s `asyncAfter`, `keyboardWillShow` + a 0.1s
//     `asyncAfter`, `last?.content`, `last?.thinkingContent`) all calling
//     `scrollTo` on one proxy, three of them animated. They fought each other: a
//     token arriving mid-animation restarted the 0.5s curve, so a fast reply
//     scrolled in visible lurches. Collapsing them to one coalesced `scrollTo`
//     fixed the lurching but not the underlying problem: `scrollTo(_, anchor:
//     .bottom)` on a transcript **shorter than the viewport** overscrolls past
//     the end, so the first reply of a chat landed entirely above the visible
//     region and the screen read as blank until you dragged it back. Verified on
//     an iPhone 17 Pro: send one message, get a full reply, see nothing.
//     `.defaultScrollAnchor(.bottom)` alone does the whole job — it pins content
//     to the bottom edge *and* holds that alignment as the content grows, with
//     no offset arithmetic to get wrong at either size.
//  2. **The reading measure.** `Measure.text` caps both the transcript and the
//     composer. Without it a 3456pt Mac window sets one line of prose across the
//     whole display, which is unreadable and the loudest "this is a phone app in
//     a window" tell in the build.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

enum ComposerAction {
    case attachFile
    case takePhoto
    case attachPhoto
    /// Attach whatever is on the clipboard. Also reachable with ⌘V on the Mac;
    /// the menu item is what makes it discoverable on a phone, which has no
    /// keyboard shortcut and no other way to hand a screenshot to the chat.
    case pasteAttachment
    case talk
    /// The SDK demo hub. iOS only: the Mac reaches it from the sidebar.
    case openAdvanced
}

// MARK: - Chat Messages View

struct ChatMessageListView: View {
    @Bindable var viewModel: LLMViewModel
    @FocusState.Binding var isTextFieldFocused: Bool
    @Binding var showingLoRAManagement: Bool
    @ObservedObject var settingsViewModel: SettingsViewModel
    @ObservedObject var toolSettingsViewModel: ToolSettingsViewModel

    private var isEmpty: Bool {
        viewModel.messages.isEmpty && !viewModel.isGenerating
    }

    var body: some View {
        // `GeometryReader` for one number: the viewport height, which the content
        // below claims as a *minimum*. Without it `.defaultScrollAnchor(.bottom)`
        // pins a two-message transcript to the composer and leaves ~860pt of void
        // above it in a 1034pt Mac window — measured on the real app. Claiming
        // the viewport height with `alignment: .top` makes bottom-anchoring a
        // no-op while the transcript is short (it starts at the top and grows
        // down, as every assistant does) and hands scrolling back the moment the
        // content genuinely overflows.
        GeometryReader { proxy in
            ScrollView {
                if isEmpty {
                    emptyStateView
                        .frame(minHeight: proxy.size.height, alignment: .center)
                } else {
                    messageListView
                        .frame(minHeight: proxy.size.height, alignment: .top)
                }
            }
            // Scrolling stays enabled even on the empty state. It was disabled to
            // stop an idle screen rubber-banding, but raising the keyboard halves
            // the viewport, and a centered empty state taller than that gets its
            // greeting clipped under the header with no way to reach it.
            .defaultScrollAnchor(isEmpty ? .center : .bottom)
            .background(AppColors.backgroundGrouped)
            .contentShape(Rectangle())
            .onTapGesture { isTextFieldFocused = false }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: Space.xl) {
            // The shared figure, so the empty transcript is recognisably the same
            // object as every other empty state in the app. 96pt rather than the
            // 132pt hero: the starter prompts sit directly under this in the
            // composer, and a full-size mark pushed them off the shortest phone.
            EmptyStateMark(systemImage: "bubble.left.and.bubble.right", diameter: 96)

            VStack(spacing: Space.sm) {
                Text(emptyStateGreeting)
                    .appType(.title)
                    .foregroundStyle(AppColors.textPrimary)

                Text("Ask anything — everything runs privately on your device.")
                    .appType(.secondary)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, Space.screenMargin)
        .padding(.vertical, Space.xxl)
        .measured(Measure.text)
    }

    private var emptyStateGreeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<5: return "Working late?"
        case 5..<12: return "Good morning"
        case 12..<18: return "Good afternoon"
        default: return "Good evening"
        }
    }

    // MARK: - Message List

    private var messageListView: some View {
        LazyVStack(spacing: Space.xl) {
            ForEach(viewModel.messages) { message in
                MessageBubbleView(
                    message: message,
                    isStreamingTail: viewModel.isGenerating
                        && message.role == .assistant
                        && message.id == viewModel.messages.last?.id,
                    isLatestTurn: message.id == viewModel.messages.last?.id,
                    loadedModelSupportsThinking: viewModel.loadedModelSupportsThinking,
                    actions: actions(for: message)
                )
                .id(message.id)
                .transition(.messageInsert)
            }
        }
        .padding(.horizontal, Space.screenMargin)
        .padding(.vertical, Space.xl)
        .measured(Measure.text)
        .motionAware(Motion.standardSpring, value: viewModel.messages.count)
    }

    /// Which actions a turn offers.
    ///
    /// Everything is withheld while a generation is running: regenerating or
    /// deleting a message the in-flight turn is indexed against would leave that
    /// turn writing into the wrong slot. Copy always stays, since the bubble owns
    /// it and it mutates nothing.
    private func actions(for message: Message) -> MessageActions {
        guard !viewModel.isGenerating else { return .none }

        let id = message.id
        let delete = { viewModel.deleteMessage(id: id) }

        switch message.role {
        case .assistant:
            // An error bubble is UI feedback, not a reply — retrying the question
            // is the useful action, so it keeps Regenerate.
            let regenerate = { viewModel.regenerateReply(messageID: id) }
            return MessageActions(regenerate: regenerate, edit: nil, delete: delete)

        case .user:
            let edit = {
                viewModel.editQuestion(messageID: id)
                // The question lands in the composer; taking focus with it is
                // what makes this an edit rather than a puzzle.
                isTextFieldFocused = true
            }
            return MessageActions(regenerate: nil, edit: edit, delete: delete)

        case .system:
            return .none
        }
    }
}

// MARK: - Starter Prompts

/// The things a consumer opens an on-device assistant to do, in the set that
/// suits whatever the next turn can actually reach.
///
/// `title` is the shared label — the same string Android's `PromptSuggestions`
/// and the web's `STARTER_PROMPTS` show — so the same chip is recognisable on
/// all three. The three sets and their copy mirror Android's `generalSuggestions`
/// / `toolSuggestions` / `personalizedSuggestions` exactly; only the general set
/// goes without icons there, and it does here too.
struct StarterPrompt: Identifiable {
    let id: String
    let icon: String?
    let title: String
    let text: String

    /// Which set to show. Mirrors Android's `PromptMode`: an adapter outranks
    /// tools, because a personalized model is the more specific fact about what
    /// the next turn will be.
    static func set(toolsEnabled: Bool, loraActive: Bool) -> [StarterPrompt] {
        if loraActive { return personalized }
        return toolsEnabled ? tools : general
    }

    static let general: [StarterPrompt] = [
        StarterPrompt(
            id: "plan",
            icon: nil,
            title: "Plan my day",
            text: "Turn this messy list into a realistic plan with the top three priorities:"
        ),
        StarterPrompt(
            id: "rewrite",
            icon: nil,
            title: "Rewrite clearly",
            text: "Rewrite this so it is clear, warm, and concise:"
        ),
        StarterPrompt(
            id: "compare",
            icon: nil,
            title: "Compare options",
            text: "Compare these options, explain the tradeoffs, and recommend one:"
        ),
        StarterPrompt(
            id: "summarize",
            icon: nil,
            title: "Summarize notes",
            text: "Summarize these notes into decisions, action items, and open questions:"
        )
    ]

    static let tools: [StarterPrompt] = [
        StarterPrompt(
            id: "trip",
            icon: "checklist",
            title: "Trip plan",
            text: "Help me make a practical packing list for a weekend city trip."
        ),
        StarterPrompt(
            id: "time",
            icon: "clock",
            title: "Time check",
            text: "What time is it in London, Tokyo, and San Francisco?"
        ),
        StarterPrompt(
            id: "battery",
            icon: "battery.100",
            title: "Device status",
            text: "Check my battery level and tell me if I should charge before leaving."
        ),
        StarterPrompt(
            id: "math",
            icon: "function",
            title: "Quick math",
            text: "Calculate 15% of 240, then show the shortcut."
        )
    ]

    static let personalized: [StarterPrompt] = [
        StarterPrompt(
            id: "reply",
            icon: "person",
            title: "Draft reply",
            text: "Draft a concise, kind reply to this message:"
        ),
        StarterPrompt(
            id: "tone",
            icon: "slider.horizontal.3",
            title: "Tighten tone",
            text: "Make this message more direct while keeping it friendly:"
        ),
        StarterPrompt(
            id: "memo",
            icon: "doc.text",
            title: "Decision memo",
            text: "Turn this into a one-page decision memo with risks and next steps:"
        ),
        StarterPrompt(
            id: "coach",
            icon: "bolt",
            title: "Coach me",
            text: "Help me think through this situation and suggest my next move:"
        )
    ]
}

// MARK: - Message Insert Transition

extension AnyTransition {
    /// A new turn rises into place. Asymmetric because a removal that mirrors
    /// the insert reads as an undo rather than a delete.
    static var messageInsert: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 12)),
            removal: .opacity.combined(with: .scale(scale: 0.96))
        )
    }
}

// MARK: - Attachment Pills

struct ImageAttachmentPill: View {
    let attachment: ChatImageAttachment
    let isVisionModelReady: Bool
    let onRemove: () -> Void
    let onChooseVisionModel: () -> Void

    var body: some View {
        AttachmentPillLayout(
            title: "Image attached",
            subtitle: isVisionModelReady ? "Ready for a question" : "Choose a vision model",
            isReady: isVisionModelReady,
            actionTitle: "Model",
            onAction: onChooseVisionModel,
            onRemove: onRemove,
            removeLabel: "Remove image"
        ) {
            thumbnail
        }
    }

    @ViewBuilder private var thumbnail: some View {
        #if canImport(UIKit)
        if let image = UIImage(data: attachment.data) {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            fallbackThumbnail
        }
        #elseif canImport(AppKit)
        if let image = NSImage(data: attachment.data) {
            Image(nsImage: image).resizable().scaledToFill()
        } else {
            fallbackThumbnail
        }
        #else
        fallbackThumbnail
        #endif
    }

    private var fallbackThumbnail: some View {
        AppColors.primaryAccent.opacity(0.12)
            .overlay(Image(systemName: "photo").foregroundStyle(AppColors.primaryAccent))
    }
}

struct DocumentAttachmentPill: View {
    let attachment: ChatDocumentAttachment
    let areModelsReady: Bool
    let indexState: ChatDocumentIndexState
    let onRemove: () -> Void
    let onChooseModels: () -> Void

    var body: some View {
        AttachmentPillLayout(
            title: attachment.filename,
            subtitle: indexState.chipSubtitle(modelsReady: areModelsReady),
            isReady: indexState.isChipReady(modelsReady: areModelsReady),
            actionTitle: "Models",
            onAction: onChooseModels,
            onRemove: onRemove,
            removeLabel: "Remove document"
        ) {
            AppColors.primaryPurple.opacity(0.12)
                .overlay(
                    Image(systemName: "doc.text")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppColors.primaryPurple)
                )
        }
    }
}

/// The two attachment pills differed only in their leading icon and their copy,
/// yet each hand-rolled the same 40 lines of layout — and drifted, so the
/// document pill truncated its title in the middle and the image pill did not.
private struct AttachmentPillLayout<Leading: View>: View {
    let title: String
    let subtitle: String
    let isReady: Bool
    let actionTitle: String
    let onAction: () -> Void
    let onRemove: () -> Void
    let removeLabel: String
    @ViewBuilder let leading: Leading

    var body: some View {
        HStack(spacing: Space.md) {
            leading
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: Radius.xs, style: .continuous))

            VStack(alignment: .leading, spacing: Space.hair) {
                Text(title)
                    .appType(.cardTitle)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(subtitle)
                    .appType(.meta)
                    .foregroundStyle(isReady ? AppColors.statusGreen : AppColors.primaryAccent)
                    .lineLimit(1)
            }

            Spacer(minLength: Space.xs)

            if !isReady {
                Button(actionTitle, action: onAction)
                    .buttonStyle(.plain)
                    .appType(.meta)
                    .foregroundStyle(AppColors.primaryAccent)
            }

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(AppColors.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(removeLabel)
        }
        .padding(Space.sm)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(AppColors.backgroundSecondary)
        )
    }
}
