//
//  ConsumerModelName.swift
//  RunAnywhereAI
//
//  Publisher + family + size. Nothing about how the weights are stored or
//  which engine executes them.
//

import Foundation
import RunAnywhere

/// Derives the name a person reads from the name the catalog registers.
///
/// A catalog row is named for the artifact it fetches — `MLX Qwen3.5 0.8B
/// 4bit`, `LiquidAI LFM2.5 1.2B Instruct Q4_K_M` — because two rows can be the
/// same model at different precisions and the name is what tells them apart in
/// a log. None of that is language a reader has. The catalog name is kept
/// untouched and shown in developer mode; this is what user mode shows.
///
/// Ids are never derived from — downloads, the registry and `DefaultModels`
/// all key on the real ones.
enum ConsumerModelName {
    /// The consumer name for one model, before any list-level disambiguation.
    static func derive(_ model: ModelInfo) -> String {
        derive(
            rawName: model.name.isEmpty ? model.id : model.name,
            publisher: ModelOrgCatalog.org(for: model)
        )
    }

    static func derive(rawName: String, publisher: ModelOrg) -> String {
        let parsed = splitParentheticals(rawName)
        let body = clean(parsed.base)
        let named = prefixed(body, with: publisher)
        let full = ([named] + parsed.kept).joined(separator: " ")
        let trimmed = full.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? rawName : trimmed
    }

    /// Unique consumer names for every model in one list, keyed by id.
    ///
    /// Collisions are designed into the catalog rather than accidental:
    /// LFM2.5 2.6B is registered three times on purpose so one model can be
    /// compared across the CPU, the GPU and the Neural Engine. Stripping the
    /// engine out of the name is what makes those three read identically, so
    /// the engine is what goes back in — and an accelerator is a difference a
    /// reader can act on, unlike the quantisation that used to stand in for it.
    static func uniqueNames(for models: [ModelInfo]) -> [String: String] {
        var resolved: [String: String] = [:]
        var byName: [String: [ModelInfo]] = [:]

        for model in models {
            let name = derive(model)
            resolved[model.id] = name
            byName[name, default: []].append(model)
        }

        for (name, group) in byName where group.count > 1 {
            let accelerators = group.map { acceleratorLabel($0.framework) }
            if Set(accelerators).count == group.count {
                for (model, accelerator) in zip(group, accelerators) {
                    resolved[model.id] = "\(name) · \(accelerator)"
                }
                continue
            }
            // Same model, same engine, different precision. The size is the
            // honest consumer-legible form of that difference.
            let sizes = group.map(\.consumerSizeLabel)
            guard Set(sizes).count == group.count else { continue }
            for (model, size) in zip(group, sizes) {
                resolved[model.id] = "\(name) · \(size)"
            }
        }

        return resolved
    }

    /// What runs the model, named for the hardware rather than the library that
    /// drives it. "Sherpa" and "llama.cpp" are the same answer to a reader
    /// asking what this will cost their battery: the CPU.
    static func acceleratorLabel(_ framework: InferenceFramework) -> String {
        switch framework {
        case .coreml: return "Neural Engine"
        case .mlx: return "GPU"
        case .llamaCpp, .onnx, .sherpa, .piperTts: return "CPU"
        case .foundationModels, .builtIn, .systemTts: return "Built in"
        case .qhexrt: return "NPU"
        default: return framework.consumerBackendBadgeLabel
        }
    }

    // MARK: - Parentheticals

    private struct Parsed {
        var base: String
        var kept: [String]
    }

    /// Splits trailing qualifiers out of the name so a kept one survives token
    /// cleaning intact — `(US English - Medium)` must not be filtered word by
    /// word, and `(NeuRT / Neural Engine)` must go as a unit.
    private static func splitParentheticals(_ text: String) -> Parsed {
        var base = ""
        var inner = ""
        var kept: [String] = []
        var depth = 0

        for character in text {
            switch character {
            case "(":
                depth += 1
                if depth == 1 { inner = "" } else { inner.append(character) }
            case ")" where depth > 0:
                depth -= 1
                if depth == 0 {
                    if !isTechnicalQualifier(inner) { kept.append("(\(inner))") }
                } else {
                    inner.append(character)
                }
            default:
                if depth > 0 { inner.append(character) } else { base.append(character) }
            }
        }

        // An unbalanced "(" is a typo in the catalog, not a qualifier; keep the
        // characters rather than swallowing the rest of the name.
        if depth > 0 { base += "(\(inner)" }
        return Parsed(base: base, kept: kept)
    }

    /// True when a parenthetical says only which runtime, precision or vendor
    /// this row is — all of which the name already carries or does not need.
    private static func isTechnicalQualifier(_ inner: String) -> Bool {
        let words = inner
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber && $0 != "." }
            .map(String.init)
        guard !words.isEmpty else { return true }

        var sawTechnical = false
        for word in words {
            if word.allSatisfy({ $0.isNumber || $0 == "." }) { continue }
            if runtimeWords.contains(word) || publisherWords.contains(word)
                || droppedWords.contains(word) || isQuantization(word) || word == "bit" {
                sawTechnical = true
                continue
            }
            return false
        }
        return sawTechnical
    }

    // MARK: - Token cleaning

    private static func clean(_ base: String) -> String {
        let tokens = base
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .map(collapseMixtureOfExperts)
            .flatMap(splitFamilyFromSize)
            .filter { !isDropped($0) }
        return tokens.joined(separator: " ")
    }

    private static func isDropped(_ token: String) -> Bool {
        let lowered = token.lowercased()
        return droppedWords.contains(lowered) || isQuantization(lowered)
    }

    /// Runtime and vendor prefixes the catalog puts in front of a name, the
    /// training-stage words that mean nothing outside a model card, and the two
    /// words the SDK uses to label its own built-in rows ("CoreML Diffusion",
    /// "Platform LLM") — those name a framework and a hosting arrangement, not
    /// a product.
    private static let droppedWords: Set<String> = [
        "mlx", "gguf", "onnx", "sherpa", "sherpa-onnx", "neurt", "coreml", "liquidai",
        "instruct", "instruction", "it", "base", "platform"
    ]

    private static let runtimeWords: Set<String> = [
        "mlx", "gguf", "onnx", "sherpa", "neurt", "coreml", "core", "ml",
        "neural", "engine", "cpu", "gpu", "npu", "ane", "metal",
        "embedding", "tool", "calling", "quantized", "quantised"
    ]

    private static let publisherWords: Set<String> = {
        let words = ModelOrg.allCases.flatMap {
            $0.displayName.lowercased().split(separator: " ").map(String.init)
        }
        // "open"/"source"/"ai" are the generic halves of publisher labels and
        // would swallow a qualifier that merely mentions them.
        return Set(words).subtracting(["open", "source", "ai"])
    }()

    /// `Q4_K_M`, `TQ1_0`, `INT8`, `4bit`, `1-bit`, `DWQ` — never a family name
    /// that happens to start with a Q.
    private static func isQuantization(_ token: String) -> Bool {
        let lowered = token.lowercased()
        if fixedPrecisionWords.contains(lowered) { return true }

        for suffix in ["-bit", "bit"] where lowered.hasSuffix(suffix) {
            let head = lowered.dropLast(suffix.count)
            return !head.isEmpty && head.allSatisfy(\.isNumber)
        }

        var body = Substring(lowered)
        if body.hasPrefix("tq") || body.hasPrefix("iq") {
            body = body.dropFirst(2)
        } else if body.hasPrefix("q") {
            body = body.dropFirst(1)
        } else {
            return false
        }
        guard let first = body.first, first.isNumber else { return false }
        return body.allSatisfy { $0.isNumber || $0.isLetter || $0 == "_" }
    }

    private static let fixedPrecisionWords: Set<String> = [
        "int4", "int8", "uint8", "fp8", "fp16", "f16", "bf16", "fp32", "f32", "dwq"
    ]

    // MARK: - Size tokens

    /// `35B-A3B` is a mixture-of-experts row stating total and active
    /// parameters. Only the total tells a reader how big the download is.
    private static func collapseMixtureOfExperts(_ token: String) -> String {
        let parts = token.split(separator: "-")
        guard parts.count == 2, isParameterCount(parts[0]) else { return token }
        let active = parts[1]
        guard active.first?.lowercased() == "a", isParameterCount(active.dropFirst()) else {
            return token
        }
        return String(parts[0])
    }

    /// `Bonsai-1.7B` is a family and a size run together. `Qwen3-VL` is not.
    private static func splitFamilyFromSize(_ token: String) -> [String] {
        let parts = token.split(separator: "-")
        guard parts.count == 2, !isParameterCount(parts[0]), isParameterCount(parts[1]) else {
            return [token]
        }
        return parts.map(String.init)
    }

    private static func isParameterCount(_ token: Substring) -> Bool {
        guard let unit = token.last, "bmBM".contains(unit) else { return false }
        let digits = token.dropLast()
        guard let first = digits.first, first.isNumber else { return false }
        return digits.allSatisfy { $0.isNumber || $0 == "." }
    }

    // MARK: - Publisher

    private static func prefixed(_ name: String, with publisher: ModelOrg) -> String {
        guard publisher != .openSource, !name.isEmpty else { return name }
        let label = publisher.displayName
        let alreadyNamed = name.range(
            of: label,
            options: [.caseInsensitive, .anchored, .diacriticInsensitive]
        ) != nil
        return alreadyNamed ? name : "\(label) \(name)"
    }
}

extension ModelInfo {
    /// Publisher, family and size — no quantisation, no runtime prefix.
    /// Not unique on its own; `ConsumerModelName.uniqueNames(for:)` resolves the
    /// catalog's deliberate one-model-three-accelerators rows.
    var consumerDisplayName: String {
        ConsumerModelName.derive(self)
    }
}
