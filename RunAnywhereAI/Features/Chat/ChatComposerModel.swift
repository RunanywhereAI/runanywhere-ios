import SwiftUI
import Observation

enum AttachmentKind {
    case document
    case image

    var symbol: String {
        switch self {
        case .document: "doc.text"
        case .image: "photo"
        }
    }
}

struct ComposerAttachment: Equatable {
    let name: String
    let kind: AttachmentKind
    var isReady: Bool
}

@Observable
final class ChatComposerModel {
    var draft = ""
    var toolsEnabled = false
    var thinkingEnabled = false
    var thinkingSupported = true
    var isGenerating = false
    var isStopping = false
    var isListening = false

    var blockedReason: String?
    var attachmentRejection: String?
    var notice: String? {
        didSet { if notice == nil { noticeKind = .general } }
    }
    var noticeKind: NoticeKind = .general

    enum NoticeKind {
        case general
        case dictation
        case attachment
    }

    var noticeTitle: String {
        switch noticeKind {
        case .dictation: "Dictation stopped"
        case .attachment: "Cannot send this attachment"
        case .general: "Cannot send"
        }
    }

    var noticeSymbol: String {
        switch noticeKind {
        case .dictation: "waveform.badge.exclamationmark"
        case .attachment: "paperclip.badge.ellipsis"
        case .general: "exclamationmark.triangle"
        }
    }
    var staged: ChatAttachment?
    /// Set while a staged attachment needs a model the reader has not chosen.
    /// Send stays blocked until they answer it, so an image is never handed to
    /// a model that cannot see.
    var modelSwitch: AttachmentModelOffer?
    var indexState: DocumentIndexState = .idle
    var toolsUnavailableMessage: String?
    var hasModel = false
    var isConversationEmpty = true
    var toolsSupported = true

    var hasActiveModes: Bool {
        toolsEnabled || thinkingEnabled
    }

    var hasTrimmedDraft: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canSend: Bool {
        guard hasModel, blockedReason == nil, modelSwitch == nil else { return false }
        return hasTrimmedDraft || staged != nil
    }

    var stagedTint: Color {
        switch indexState {
        case .failed: AppColors.danger
        case .indexing: AppColors.info
        default: staged?.isImage == true ? AppColors.brand : AppColors.success
        }
    }

    var stagedWash: Color {
        switch indexState {
        case .failed: AppColors.dangerMuted
        case .indexing: AppColors.infoMuted
        default: staged?.isImage == true ? AppColors.brandMuted : AppColors.successMuted
        }
    }

    var stagedDetail: String {
        switch indexState {
        case .indexing: "Indexing…"
        case .failed(let message): message
        default: staged?.detail ?? ""
        }
    }

    var placeholder: String {
        guard hasModel else { return "Choose a model to start" }
        if let staged {
            return staged.isImage
                ? "Add a question, or send to describe this image"
                : "Add a question, or send to ask about this file"
        }
        return "Ask anything"
    }

    var prompts: [StarterPrompt] {
        StarterPrompt.set(toolsEnabled: toolsEnabled)
    }

    /// Starters belong to an empty conversation, not to an empty text box.
    /// Keying them off the draft made them reappear between every turn.
    var showsPrompts: Bool {
        isConversationEmpty && staged == nil && !isGenerating
    }

    func apply(_ prompt: StarterPrompt) {
        draft = prompt.text + " "
    }

    func removeAttachment() {
        staged = nil
        modelSwitch = nil
    }

    func dismissRejection() {
        attachmentRejection = nil
    }
}
