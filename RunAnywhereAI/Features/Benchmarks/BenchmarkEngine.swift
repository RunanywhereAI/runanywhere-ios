import CoreGraphics
import Darwin
import Foundation
import RunAnywhere

/// Runs the measured passes. Every number it returns comes from a call it
/// just made; nothing is estimated and nothing is carried over between runs.
struct BenchmarkEngine: Sendable {
    struct Item: Sendable {
        let model: BenchmarkModelRef
        let workload: BenchmarkWorkload
    }

    /// Seeded and at temperature zero so two runs of the same model on the
    /// same device decode the same tokens, and a difference in the numbers is
    /// a difference in the device rather than in the sampler.
    private static let seed = 20_240_101
    private static let sampleRate = 16_000

    private let clock = ContinuousClock()

    /// Everything that was measured before the run ended, and whether it
    /// ended because it was cancelled. Cancelling keeps the results already
    /// in hand rather than discarding a run someone waited through.
    struct Outcome: Sendable {
        let results: [BenchmarkResult]
        let wasCancelled: Bool
    }

    func run(
        items: [Item],
        trials: Int,
        progress: @Sendable @escaping (BenchmarkProgress) -> Void
    ) async -> Outcome {
        var results: [BenchmarkResult] = []
        results.reserveCapacity(items.count)

        for (index, item) in items.enumerated() {
            guard !Task.isCancelled else { return Outcome(results: results, wasCancelled: true) }
            progress(BenchmarkProgress(
                completed: index,
                total: items.count,
                modelName: item.model.name,
                scenarioName: item.workload.scenario.name
            ))
            do {
                results.append(try await measure(item, trials: trials))
            } catch {
                // `measure` turns every measurement failure into a failed
                // result; cancellation is the only error that escapes it.
                return Outcome(results: results, wasCancelled: true)
            }
        }

        progress(BenchmarkProgress(
            completed: items.count,
            total: items.count,
            modelName: "",
            scenarioName: ""
        ))
        return Outcome(results: results, wasCancelled: false)
    }

    private func measure(_ item: Item, trials: Int) async throws -> BenchmarkResult {
        let scenario = item.workload.scenario
        do {
            var samples: [BenchmarkMetrics] = []
            samples.reserveCapacity(trials)
            for _ in 0..<trials {
                try Task.checkCancellation()
                samples.append(try await measureOnce(item))
            }
            let (metrics, spread) = BenchmarkMetrics.combine(samples)
            return BenchmarkResult(
                category: item.workload.category,
                scenario: scenario,
                model: item.model,
                trials: trials,
                metrics: metrics,
                spread: spread
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return BenchmarkResult(
                category: item.workload.category,
                scenario: scenario,
                model: item.model,
                trials: trials,
                metrics: BenchmarkMetrics(),
                failure: message(for: error)
            )
        }
    }

    private func measureOnce(_ item: Item) async throws -> BenchmarkMetrics {
        switch item.workload {
        case .llm(let maxTokens):
            try await measureLLM(model: item.model, maxTokens: maxTokens)
        case .stt(let seconds):
            try await measureSTT(model: item.model, seconds: seconds)
        case .tts(let text, _):
            try await measureTTS(model: item.model, text: text)
        case .vlm(let maxTokens):
            try await measureVLM(model: item.model, maxTokens: maxTokens)
        }
    }

    // MARK: - Language

    private func measureLLM(model: BenchmarkModelRef, maxTokens: Int) async throws -> BenchmarkMetrics {
        try? await RunAnywhere.models.unloadAll(category: .language)
        let before = BenchmarkFootprint.bytes()

        var metrics = BenchmarkMetrics()
        metrics.loadMs = try await time { _ = try await RunAnywhere.models.load(id: model.id) }

        do {
            metrics.warmupMs = try await time {
                let events = try await RunAnywhere.llm.generateStream(
                    prompt: "Hello",
                    options: LlmOptions(maxOutputTokens: 4, temperature: 0, seed: Self.seed)
                )
                for try await event in events where event.isTerminal { break }
            }

            var result: GenerationResult?
            metrics.latencyMs = try await time {
                let events = try await RunAnywhere.llm.generateStream(
                    prompt: BenchmarkPrompts.generation,
                    options: LlmOptions(
                        maxOutputTokens: maxTokens,
                        temperature: 0,
                        seed: Self.seed,
                        systemPrompt: BenchmarkPrompts.system
                    )
                )
                for try await event in events {
                    try Task.checkCancellation()
                    if case .completed(_, let payload) = event {
                        result = payload
                        break
                    }
                }
            }

            if let result { apply(result, to: &metrics) }
            metrics.memoryDeltaBytes = BenchmarkFootprint.bytes() - before
            try? await RunAnywhere.models.unloadAll(category: .language)
            return metrics
        } catch {
            try? await RunAnywhere.models.unloadAll(category: .language)
            throw error
        }
    }

    // MARK: - Speech to text

    private func measureSTT(model: BenchmarkModelRef, seconds: Double) async throws -> BenchmarkMetrics {
        try? await RunAnywhere.models.unloadAll(category: .speechRecognition)
        let before = BenchmarkFootprint.bytes()

        var metrics = BenchmarkMetrics()
        metrics.loadMs = try await time { _ = try await RunAnywhere.models.load(id: model.id) }

        do {
            let audio = BenchmarkInput.speechLikeAudio(seconds: seconds, sampleRate: Self.sampleRate)
            metrics.warmupMs = try await time {
                let warmup = BenchmarkInput.speechLikeAudio(seconds: 0.5, sampleRate: Self.sampleRate)
                _ = try await RunAnywhere.stt.transcribe(.pcm16(warmup, sampleRate: Self.sampleRate))
            }

            metrics.latencyMs = try await time {
                _ = try await RunAnywhere.stt.transcribe(.pcm16(audio, sampleRate: Self.sampleRate))
            }

            metrics.audioSeconds = seconds
            metrics.realTimeFactor = metrics.latencyMs / 1000 / seconds
            metrics.memoryDeltaBytes = BenchmarkFootprint.bytes() - before
            try? await RunAnywhere.models.unloadAll(category: .speechRecognition)
            return metrics
        } catch {
            try? await RunAnywhere.models.unloadAll(category: .speechRecognition)
            throw error
        }
    }

    // MARK: - Text to speech

    private func measureTTS(model: BenchmarkModelRef, text: String) async throws -> BenchmarkMetrics {
        try? await RunAnywhere.models.unloadAll(category: .speechSynthesis)
        let before = BenchmarkFootprint.bytes()

        var metrics = BenchmarkMetrics()
        metrics.loadMs = try await time { _ = try await RunAnywhere.models.load(id: model.id) }

        do {
            // `synthesize`, never `speak`: a benchmark that plays out loud
            // measures the speaker as well as the model.
            metrics.warmupMs = try await time { _ = try await RunAnywhere.tts.synthesize("Hello.") }

            var audio: Audio?
            metrics.latencyMs = try await time { audio = try await RunAnywhere.tts.synthesize(text) }

            metrics.characters = text.count
            if let audio, audio.durationMs > 0 {
                let duration = Double(audio.durationMs) / 1000
                metrics.audioSeconds = duration
                metrics.realTimeFactor = metrics.latencyMs / 1000 / duration
            }
            metrics.memoryDeltaBytes = BenchmarkFootprint.bytes() - before
            try? await RunAnywhere.models.unloadAll(category: .speechSynthesis)
            return metrics
        } catch {
            try? await RunAnywhere.models.unloadAll(category: .speechSynthesis)
            throw error
        }
    }

    // MARK: - Vision

    private func measureVLM(model: BenchmarkModelRef, maxTokens: Int) async throws -> BenchmarkMetrics {
        try? await RunAnywhere.models.unloadAll(category: .multimodal)
        try? await RunAnywhere.models.unloadAll(category: .language)
        // A vision encoder allocates in one burst. Without a pause the
        // previous model's Metal buffers are often still resident and the
        // load fails for memory rather than for anything the benchmark cares
        // about.
        try await Task.sleep(for: .milliseconds(500))

        let before = BenchmarkFootprint.bytes()
        var metrics = BenchmarkMetrics()
        metrics.loadMs = try await time { _ = try await RunAnywhere.models.load(id: model.id) }

        do {
            let image = try BenchmarkInput.benchmarkImage()

            metrics.warmupMs = try await time {
                _ = try await RunAnywhere.vlm.generate(
                    image: image,
                    prompt: "Hi",
                    options: LlmOptions(maxOutputTokens: 1, temperature: 0, seed: Self.seed)
                )
            }

            var result: GenerationResult?
            metrics.latencyMs = try await time {
                result = try await RunAnywhere.vlm.generate(
                    image: image,
                    prompt: BenchmarkPrompts.imageQuestion,
                    options: LlmOptions(maxOutputTokens: maxTokens, temperature: 0, seed: Self.seed)
                )
            }

            if let result { apply(result, to: &metrics) }
            metrics.memoryDeltaBytes = BenchmarkFootprint.bytes() - before
            try? await RunAnywhere.models.unloadAll(category: .multimodal)
            return metrics
        } catch {
            try? await RunAnywhere.models.unloadAll(category: .multimodal)
            throw error
        }
    }

    // MARK: - Shared

    private func apply(_ result: GenerationResult, to metrics: inout BenchmarkMetrics) {
        if result.timeToFirstTokenMs > 0 { metrics.ttftMs = Double(result.timeToFirstTokenMs) }
        if result.tokensPerSecond > 0 { metrics.decodeTokensPerSecond = Double(result.tokensPerSecond) }
        if result.inputTokens > 0 { metrics.inputTokens = result.inputTokens }
        if result.outputTokens > 0 { metrics.outputTokens = result.outputTokens }
        metrics.prefillTokensPerSecond = Self.prefillRate(
            inputTokens: result.inputTokens,
            ttftMs: result.timeToFirstTokenMs
        )
    }

    /// Prompt tokens divided by time to first token.
    ///
    /// `RATokenUsage` carries a measured `prefill_ms`, but the SDK's public
    /// `GenerationResult` does not surface it, so TTFT is the only prefill
    /// clock an app can read. TTFT covers prefill plus the first decode step,
    /// which makes this a floor on prefill throughput rather than an exact
    /// figure — the reports label it as derived for that reason.
    private static func prefillRate(inputTokens: Int, ttftMs: Int64) -> Double? {
        guard inputTokens > 0, ttftMs > 0 else { return nil }
        return Double(inputTokens) / (Double(ttftMs) / 1000)
    }

    private func time(_ work: () async throws -> Void) async rethrows -> Double {
        let start = clock.now
        try await work()
        return start.duration(to: clock.now).milliseconds
    }

    private func message(for error: Error) -> String {
        if let sdk = error as? SDKException { return sdk.message }
        return error.localizedDescription
    }
}

private extension GenerationEvent {
    var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled: true
        default: false
        }
    }
}

private extension Duration {
    var milliseconds: Double {
        Double(components.seconds) * 1000 + Double(components.attoseconds) / 1e15
    }
}

/// The process's physical footprint, the same number Instruments and jetsam
/// use. `ProcessInfo.physicalMemory` is device RAM and never moves, so it
/// cannot show what loading a model cost.
enum BenchmarkFootprint {
    static func bytes() -> Int64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size
        )
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), rebound, &count)
            }
        }
        return status == KERN_SUCCESS ? Int64(info.phys_footprint) : 0
    }
}

enum BenchmarkInput {
    /// Two voiced harmonics under a 4 Hz syllable envelope, sampled as mono
    /// little-endian Int16. Not speech, but it exercises the same framing and
    /// feature path as speech does, and it is bit-identical on every device.
    static func speechLikeAudio(seconds: Double, sampleRate: Int) -> Data {
        let frames = Int(seconds * Double(sampleRate))
        guard frames > 0 else { return Data() }
        var samples = [Int16](repeating: 0, count: frames)
        let amplitude = Double(Int16.max) * 0.4
        for index in 0..<frames {
            let time = Double(index) / Double(sampleRate)
            let envelope = 0.5 * (1 - cos(2 * .pi * 4 * time))
            let voiced = sin(2 * .pi * 140 * time) + 0.5 * sin(2 * .pi * 420 * time)
            samples[index] = Int16(max(-amplitude, min(amplitude, amplitude * envelope * voiced / 1.5)))
        }
        return samples.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    /// A 224 × 224 diagonal gradient with a light disc on it, drawn through
    /// Core Graphics so the same bytes reach the model on both platforms.
    static func benchmarkImage(side: Int = 224) throws -> ImageInput {
        let space = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: side * 4,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw BenchmarkInputError.imageUnavailable
        }

        let endpoints = [
            CGColor(colorSpace: space, components: [0.10, 0.22, 0.78, 1]),
            CGColor(colorSpace: space, components: [0.95, 0.55, 0.10, 1])
        ].compactMap { $0 }
        guard endpoints.count == 2,
              let gradient = CGGradient(colorsSpace: space, colors: endpoints as CFArray, locations: [0, 1]),
              let disc = CGColor(colorSpace: space, components: [1, 1, 1, 1]) else {
            throw BenchmarkInputError.imageUnavailable
        }

        context.drawLinearGradient(
            gradient,
            start: .zero,
            end: CGPoint(x: side, y: side),
            options: []
        )
        context.setFillColor(disc)
        let inset = CGFloat(side) / 4
        context.fillEllipse(in: CGRect(x: inset, y: inset, width: inset * 2, height: inset * 2))

        guard let image = context.makeImage() else { throw BenchmarkInputError.imageUnavailable }
        return try ImageInput.cgImage(image)
    }
}

enum BenchmarkInputError: LocalizedError {
    case imageUnavailable

    var errorDescription: String? {
        switch self {
        case .imageUnavailable: "Core Graphics could not draw the benchmark image on this device."
        }
    }
}
