import Foundation
import RunAnywhere

/// A curated model with the standing it earned in its own modality's shortlist.
/// The standing travels with the model so a publisher section can still say
/// which of Liquid AI's models is the one for this device.
struct CuratedEntry: Identifiable {
    let model: ModelInfo
    let standing: ModelStanding

    var id: String { model.id }
}

/// One section of the curated view under whichever grouping is in force.
struct CuratedGroup: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let entries: [CuratedEntry]
}

extension ModelCuration {
    /// The curated shortlists resectioned. Grouping changes which models sit
    /// together, never which models are shown: the five per modality are the
    /// five either way.
    static func groups(from shortlists: [CuratedModels], by grouping: ModelGrouping) -> [CuratedGroup] {
        switch grouping {
        case .category:
            return shortlists.map { shortlist in
                CuratedGroup(
                    id: shortlist.purpose.rawValue,
                    title: shortlist.purpose.title,
                    symbol: shortlist.purpose.symbol,
                    entries: shortlist.models.map {
                        CuratedEntry(model: $0, standing: shortlist.standing(of: $0))
                    }
                )
            }
        case .publisher:
            var buckets: [ModelOrg: [CuratedEntry]] = [:]
            for shortlist in shortlists {
                for model in shortlist.models {
                    let entry = CuratedEntry(model: model, standing: shortlist.standing(of: model))
                    buckets[ModelOrgCatalog.org(for: model), default: []].append(entry)
                }
            }
            return ModelOrg.allCases.compactMap { org in
                guard let entries = buckets[org], !entries.isEmpty else { return nil }
                return CuratedGroup(
                    id: org.rawValue,
                    title: org.displayName,
                    symbol: org.systemImage,
                    entries: entries
                )
            }
        }
    }
}

/// One modality and every catalog row filed under it, for the developer browse
/// grouped by category. Ordered smaller → larger to match the publisher groups.
struct ModelPurposeGroup: Identifiable {
    let purpose: ModelPurpose
    let models: [ModelInfo]

    var id: String { purpose.rawValue }
}

enum ModelPurposeCatalog {
    static func groups(from models: [ModelInfo]) -> [ModelPurposeGroup] {
        var buckets: [ModelPurpose: [ModelInfo]] = [:]
        for model in models where !model.isLoRAAdapterArtifact {
            buckets[ModelPurpose.of(model), default: []].append(model)
        }
        return ModelPurpose.allCases.compactMap { purpose in
            guard let members = buckets[purpose], !members.isEmpty else { return nil }
            return ModelPurposeGroup(
                purpose: purpose,
                models: members.sorted { $0.consumerSizeBytes < $1.consumerSizeBytes }
            )
        }
    }
}
