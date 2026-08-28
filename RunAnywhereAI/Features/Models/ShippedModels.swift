//
//  ShippedModels.swift
//  RunAnywhereAI
//
//  The models this app ships pointed at, chosen here rather than worked out
//  on the device.
//

import Foundation
import RunAnywhere

/// What the app runs when nobody has chosen anything.
///
/// Curation ranks the catalog by what a device can bear; that is the right
/// answer for someone browsing, and the wrong one for someone who has just
/// installed the app and wants it to work. It also has no opinion about what a
/// model is *for*: a vision shortlist ranked by size put a computer-use agent
/// at the top, so attaching a photo offered to hand the screen to an agent.
///
/// So the picks are named. Each list is ordered by preference and read left to
/// right until one is in the catalog, which means a model can be retired from
/// the catalog without stranding the app on a row that no longer exists.
///
/// The bias is deliberately toward the engine that runs everywhere. MLX is
/// absent from every list even where it would be faster, because it does not
/// register on the simulator and a default that is missing on a developer's
/// machine is a default that gets quietly replaced by something worse.
@MainActor
enum ShippedModels {

    /// The picks, most preferred first.
    static func preferred(for purpose: ModelPurpose) -> [String] {
        switch purpose {
        case .language:
            [
                "lfm2.5-1.2b-instruct-q4_k_m",
                "qwen3.5-0.8b-q4_k_m",
                "lfm2.5-230m-q4_k_m",
            ]
        case .vision:
            // Small vision-language models that describe a picture. Explicitly
            // not `fara1.5-4b`: it is a computer-use agent, it is a vision
            // model by category, and it sorts first by id — which is how it
            // became the answer to "describe this photo".
            [
                "smolvlm2-500m-video-instruct-q8_0",
                "smolvlm2-256m-video-instruct-q8_0",
                "lfm2.5-vl-3b-q4_k_m",
            ]
        case .speechToText:
            [
                "sherpa-onnx-whisper-tiny.en",
                "sherpa-nemo-parakeet-tdt-0.6b-v2-int8",
            ]
        case .textToSpeech:
            [
                "vits-piper-en_US-lessac-medium",
                "vits-piper-en_GB-alba-medium",
            ]
        case .embedding:
            [
                "all-minilm-l6-v2",
            ]
        case .voiceActivity:
            [
                "silero-vad",
            ]
        case .other:
            []
        }
    }

    /// The model this app would choose for `purpose`, or nil when the catalog
    /// holds none of them.
    ///
    /// This is the shipped answer only. A choice the reader has made is held by
    /// the SDK's `DefaultModels`, and the caller applies it — every caller here
    /// already has that instance, and a second store would only disagree with
    /// the first.
    static func pick(for purpose: ModelPurpose, from models: [ModelInfo]) -> ModelInfo? {
        for id in preferred(for: purpose) {
            guard let seed = models.first(where: { $0.id == id }) else { continue }
            // The catalog registers the same weights once per engine, so an id
            // names one accelerator's row rather than the model. Whichever twin
            // is on the device is the one meant here — otherwise the pick is a
            // download the reader already has, under a different id.
            let family = models.filter { ConsumerModelName.derive($0) == ConsumerModelName.derive(seed) }
            return family.first { !$0.localPath.isEmpty || $0.isBuiltIn } ?? seed
        }
        return nil
    }

    /// Whether `model` is the shipped pick for its modality, twins included.
    static func matches(_ model: ModelInfo, from models: [ModelInfo]) -> Bool {
        guard let pick = pick(for: ModelPurpose.of(model), from: models) else { return false }
        return ConsumerModelName.derive(pick) == ConsumerModelName.derive(model)
    }

    /// The default for `purpose` when it is already on the device.
    static func installed(for purpose: ModelPurpose, from models: [ModelInfo]) -> ModelInfo? {
        guard let model = pick(for: purpose, from: models),
              !model.localPath.isEmpty || model.isBuiltIn else {
            return nil
        }
        return model
    }

    /// Whether `model` is what this app would choose for its modality, for a
    /// badge on the row that says so.
    static func isDefault(_ model: ModelInfo, among models: [ModelInfo]) -> Bool {
        matches(model, from: models)
    }
}
