//
//  ModelCuration.swift
//  RunAnywhereAI
//
//  Five models per modality, drawn from the whole catalog rather than carved
//  out of it. Developer mode still sees every row.
//

import Foundation
import RunAnywhere

/// One modality's shortlist: the recommendation for this device with two more
/// capable options above it and two faster ones below.
struct CuratedModels: Identifiable {
    let purpose: ModelPurpose
    /// Most capable first, fastest last. The recommendation sits in the middle
    /// whenever the catalog has enough on both sides of it.
    let models: [ModelInfo]
    let recommendedID: String?

    var id: String { purpose.rawValue }
    var isEmpty: Bool { models.isEmpty }

    /// Where a row sits relative to the recommendation, in the only terms a
    /// reader needs: what it costs and what it buys.
    func standing(of model: ModelInfo) -> ModelStanding {
        guard let recommendedID, let pivot = models.firstIndex(where: { $0.id == recommendedID }),
              let position = models.firstIndex(where: { $0.id == model.id }) else {
            return .alternative
        }
        if position == pivot { return .recommended }
        return position < pivot ? .moreCapable : .faster
    }
}

enum ModelStanding {
    case recommended
    case moreCapable
    case faster
    case alternative

    var label: String {
        switch self {
        case .recommended: "Recommended for this device"
        case .moreCapable: "Smarter, slower to answer"
        case .faster: "Faster, lighter on the battery"
        case .alternative: "Alternative"
        }
    }

    /// The same standing in one word, for a grid card that has a column's
    /// width rather than a row's.
    var shortLabel: String {
        switch self {
        case .recommended: "Recommended"
        case .moreCapable: "Smarter"
        case .faster: "Faster"
        case .alternative: "Alternative"
        }
    }

    var symbol: String {
        switch self {
        case .recommended: "sparkles"
        case .moreCapable: "brain"
        case .faster: "bolt"
        case .alternative: "circle"
        }
    }
}

enum ModelCuration {
    /// Five is the brief. Fewer is shown when the catalog holds fewer; nothing
    /// is padded to reach it.
    static let width = 5

    /// The full per-modality curation for this device, skipping modalities the
    /// catalog has nothing for.
    static func shortlists(from models: [ModelInfo]) -> [CuratedModels] {
        let resolver = HardwareTierResolver()
        let recommendation = ModelRecommendationEngine().recommend(
            tier: resolver.resolve(),
            appleFoundationAvailable: resolver.appleFoundationAvailable,
            from: models
        )
        return ModelPurpose.allCases
            .filter { $0 != .other }
            .map { shortlist(purpose: $0, from: models, recommended: pick($0, from: recommendation)) }
            .filter { !$0.isEmpty }
    }

    static func shortlist(
        purpose: ModelPurpose,
        from models: [ModelInfo],
        recommended: ModelInfo?
    ) -> CuratedModels {
        let candidates = collapseAccelerators(
            models.filter { ModelPurpose.of($0) == purpose && !$0.isLoRAAdapterArtifact }
        )
        .sorted { lhs, rhs in
            // Ties on size are ordered by name so the list does not reshuffle
            // between refreshes.
            lhs.consumerSizeBytes == rhs.consumerSizeBytes
                ? lhs.id < rhs.id
                : lhs.consumerSizeBytes > rhs.consumerSizeBytes
        }

        guard !candidates.isEmpty else {
            return CuratedModels(purpose: purpose, models: [], recommendedID: nil)
        }

        let pivot = index(of: recommended, in: candidates) ?? candidates.count / 2
        let window = centred(on: pivot, count: candidates.count)
        let picked = Array(candidates[window])

        return CuratedModels(
            purpose: purpose,
            models: picked,
            recommendedID: candidates[pivot].id
        )
    }

    /// A window of at most `width` entries holding `pivot`, pushed back inside
    /// the bounds when the pivot sits near either end.
    private static func centred(on pivot: Int, count: Int) -> Range<Int> {
        guard count > width else { return 0 ..< count }
        let start = min(max(0, pivot - width / 2), count - width)
        return start ..< (start + width)
    }

    /// The recommendation can be a row that lost the accelerator collapse — the
    /// engine names an MLX id, the collapse kept its llama.cpp twin. Both are
    /// the same model to a reader, so match on the consumer name.
    private static func index(of recommended: ModelInfo?, in candidates: [ModelInfo]) -> Int? {
        guard let recommended else { return nil }
        if let exact = candidates.firstIndex(where: { $0.id == recommended.id }) { return exact }
        let name = ConsumerModelName.derive(recommended)
        return candidates.firstIndex { ConsumerModelName.derive($0) == name }
    }

    /// One row per model. The catalog registers the same weights under several
    /// engines on purpose; a shortlist of five that spends three of them on one
    /// model is not a shortlist.
    private static func collapseAccelerators(_ models: [ModelInfo]) -> [ModelInfo] {
        var best: [String: ModelInfo] = [:]
        for model in models {
            let key = ConsumerModelName.derive(model)
            guard let incumbent = best[key] else {
                best[key] = model
                continue
            }
            if prefers(model, over: incumbent) { best[key] = model }
        }
        return Array(best.values)
    }

    private static func prefers(_ candidate: ModelInfo, over incumbent: ModelInfo) -> Bool {
        let candidateReady = candidate.isBuiltIn || !candidate.localPath.isEmpty
        let incumbentReady = incumbent.isBuiltIn || !incumbent.localPath.isEmpty
        if candidateReady != incumbentReady { return candidateReady }

        let candidateRank = acceleratorRank(candidate.framework)
        let incumbentRank = acceleratorRank(incumbent.framework)
        if candidateRank != incumbentRank { return candidateRank < incumbentRank }

        return candidate.consumerSizeBytes < incumbent.consumerSizeBytes
    }

    /// Fastest Apple silicon path first. Rows for an engine this build cannot
    /// execute are never registered, so a missing engine simply does not appear
    /// here rather than needing to be filtered out.
    private static func acceleratorRank(_ framework: InferenceFramework) -> Int {
        switch framework {
        case .foundationModels, .builtIn, .systemTts: return 0
        case .mlx: return 1
        case .coreml: return 2
        case .llamaCpp: return 3
        case .onnx, .sherpa, .piperTts: return 4
        default: return 5
        }
    }

    private static func pick(_ purpose: ModelPurpose, from selection: RecommendedSelection) -> ModelInfo? {
        switch purpose {
        case .language: return selection.recommendedLLMs.first ?? selection.defaultChatModel
        case .vision: return selection.recommendedVLM
        case .speechToText: return selection.recommendedASR
        case .textToSpeech: return selection.recommendedTTS
        case .embedding: return selection.recommendedEmbedding
        case .voiceActivity, .other: return nil
        }
    }
}
