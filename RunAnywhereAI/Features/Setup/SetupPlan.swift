//
//  SetupPlan.swift
//  RunAnywhereAI
//
//  What a first launch offers to download, worked out from the same curation
//  the rest of the app browses.
//

import Foundation
import RunAnywhere

/// One line of the first-launch offer: a modality, the model chosen for it, and
/// what having it buys.
struct SetupCandidate: Identifiable {
    let purpose: ModelPurpose
    let model: ModelInfo

    var id: String { model.id }

    /// Chat is the product. Without it the app opens on the download gate
    /// anyway, so it cannot be turned off here.
    var isEssential: Bool { purpose == .language }

    /// Said in terms of what the reader gets, not which subsystem consumes it.
    var rationale: String {
        switch purpose {
        case .language: "Answers questions and runs everything else"
        case .vision: "Describing photos and screenshots you attach"
        case .speechToText: "Dictation and voice mode"
        case .textToSpeech: "Reading answers back to you"
        case .embedding: "Asking questions about a document"
        default: purpose.title
        }
    }

    /// The bytes this row will fetch, falling back to the memory requirement
    /// exactly as the row's own size label does. Sum and parts have to agree.
    var sizeBytes: Int64 {
        model.downloadSizeBytes > 0 ? model.downloadSizeBytes : model.memoryRequiredBytes
    }

    var isSizeExact: Bool { model.downloadSizeBytes > 0 }
}

@MainActor
enum SetupPlan {
    /// Chat, sight, the two halves of voice, and the index behind document
    /// questions.
    ///
    /// Vision and embedding were left out at first to keep the download small,
    /// and the cost landed on the reader instead: attaching a photo or a file
    /// on a fresh install offered nothing but a trip to Manage Models to pick a
    /// model by name. Anyone who could make that choice well did not need the
    /// setup screen; anyone who needed the setup screen could not make it. Both
    /// picks are small, and they are the difference between the app working and
    /// the app asking.
    static let purposes: [ModelPurpose] = [
        .language, .vision, .speechToText, .textToSpeech, .embedding,
    ]

    /// The offer for this device, in `purposes` order.
    ///
    /// A modality is dropped when the catalog has nothing for it here, when the
    /// pick is already on disk, or when it is built in and has nothing to fetch.
    static func candidates(from models: [ModelInfo]) -> [SetupCandidate] {
        purposes.compactMap { purpose in
            guard let model = ShippedModels.pick(for: purpose, from: models),
                  model.localPath.isEmpty,
                  !model.isBuiltIn else {
                return nil
            }
            return SetupCandidate(purpose: purpose, model: model)
        }
    }

    /// The bytes `candidates` would fetch, and whether any of them was
    /// estimated rather than declared. Nil when even one row has no size at
    /// all: a total that silently omits a model still reads as a promise.
    static func total(of candidates: [SetupCandidate]) -> (bytes: Int64, isApproximate: Bool)? {
        guard !candidates.isEmpty, candidates.allSatisfy({ $0.sizeBytes > 0 }) else { return nil }
        return (
            candidates.reduce(0) { $0 + $1.sizeBytes },
            candidates.contains { !$0.isSizeExact }
        )
    }

}
