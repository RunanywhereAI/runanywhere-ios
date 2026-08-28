//
//  AttachmentModelSwitch.swift
//  RunAnywhereAI
//
//  Whether the loaded model can answer what has just been attached.
//

import Foundation

/// A model that can answer the staged attachment, offered to the reader.
struct AttachmentModelOffer: Equatable {
    let modelID: String
    let modelLabel: String
    /// Why the model has to change, said before the model is named.
    let reason: String
}

/// What has to happen before a staged attachment can be answered.
enum AttachmentReadiness: Equatable {
    case ready
    case offer(AttachmentModelOffer)
    case missing(reason: String)
}

/// The rule behind the switch prompt.
///
/// Attaching an image used to change the model silently, on send, while the
/// header went on naming the text model that had not answered. Worse, a text
/// model with an image attached still produced an answer, so the reply looked
/// like it had seen the picture. The change is now a decision the reader makes
/// at the moment they attach, and it is named.
enum AttachmentModelSwitch {
    static func readiness(
        for attachment: ChatAttachment,
        activeModelID: String?,
        installed: [InstalledModel],
        preferredVisionID: String?,
        embeddingModelID: String?
    ) -> AttachmentReadiness {
        attachment.isImage
            ? forImage(activeModelID: activeModelID, installed: installed, preferred: preferredVisionID)
            : forDocument(embeddingModelID: embeddingModelID)
    }

    private static func forImage(
        activeModelID: String?,
        installed: [InstalledModel],
        preferred: String?
    ) -> AttachmentReadiness {
        let active = installed.first { $0.id == activeModelID }
        if active?.purpose == .vision { return .ready }

        guard let candidate = visionCandidate(from: installed, preferred: preferred) else {
            return .missing(
                reason: "Images need a vision model, and none is installed. Open Manage Models to get one."
            )
        }
        return .offer(AttachmentModelOffer(
            modelID: candidate.id,
            modelLabel: candidate.label,
            reason: "\(active?.label ?? "This model") cannot see images."
        ))
    }

    /// A document is answered by the chat model with the embedding model
    /// indexing behind it, so nothing switches. What can be absent is the
    /// index, and that is worth saying before the reader types a question.
    private static func forDocument(embeddingModelID: String?) -> AttachmentReadiness {
        embeddingModelID == nil
            ? .missing(
                reason: "Asking a file questions needs an embedding model, and none is installed. "
                    + "Open Manage Models to get one."
            )
            : .ready
    }

    /// The chosen vision default, then the shipped one, then the first by id.
    ///
    /// The order matters more than it looks. Falling straight to an id sort put
    /// `fara1.5-4b-q4_k_m` first, so attaching a photo offered a computer-use
    /// agent — which is a vision model, and is not what anybody meant. The id
    /// sort survives only as a last resort, where its one virtue is that the
    /// offer does not change between launches.
    private static func visionCandidate(
        from installed: [InstalledModel],
        preferred: String?
    ) -> InstalledModel? {
        let candidates = installed.filter { $0.purpose == .vision && $0.isAvailable }
        if let preferred, let match = candidates.first(where: { $0.id == preferred }) {
            return match
        }
        return candidates.min { $0.id < $1.id }
    }
}
