//
//  EndToEndTests.swift
//  RunAnywhereAITests
//
//  Real models, real inference, no mocks. Every test here loads something off
//  disk and asks it to do the job the app asks it to do, because the failures
//  worth catching — a model that loads but answers nothing, reasoning that
//  arrives as the answer, a vision model that cannot hold a text conversation —
//  all look fine to a unit test that stops at the SDK boundary.
//
//  Tests run in the app's own container, so they see the same catalog and the
//  same files the app does. A test whose model is not installed reports that
//  and stops rather than passing quietly: an absent model is a gap in coverage,
//  not a pass.
//
//  Slow by nature. A model load is tens of seconds and several run here.
//

import RunAnywhere
import XCTest
@testable import RunAnywhereAI

final class EndToEndTests: XCTestCase {
    // MARK: - Shared bootstrap

    /// The SDK initializes once per process; catalog registration is not
    /// idempotent enough to want it per test, and each load is expensive.
    private actor Bootstrap {
        static let shared = Bootstrap()
        private var started = false

        func ensure() async throws {
            guard !started else { return }
            started = true
            try RunAnywhere.initialize(environment: .development)
            await ModelCatalogBootstrap.registerAll(mlxRegistered: true)
            await RunAnywhere.models.refresh()
        }
    }

    override func setUp() async throws {
        try await Bootstrap.shared.ensure()
    }

    /// xcodebuild swallows this suite's stdout and reports a thrown error as a
    /// bare "failed", which says nothing about which model or which call. Each
    /// case therefore writes its own verdict where it can be read afterwards.
    private static let reportPath = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        .appendingPathComponent("Documents/e2e-report.txt").path(percentEncoded: false)

    private func report(_ line: String) {
        print(line)
        let stamped = line + "\n"
        if let handle = FileHandle(forWritingAtPath: Self.reportPath) {
            handle.seekToEndOfFile()
            handle.write(Data(stamped.utf8))
            try? handle.close()
        } else {
            try? stamped.write(toFile: Self.reportPath, atomically: true, encoding: .utf8)
        }
    }

    /// Runs `body`, recording whatever happened — including a thrown error,
    /// which is the outcome this suite most needs named.
    private func step(_ name: String, _ body: () async throws -> String) async {
        do {
            let detail = try await body()
            report("PASS \(name) — \(detail)")
        } catch {
            report("FAIL \(name) — \(error)")
            XCTFail("\(name): \(error)")
        }
    }

    // MARK: - Catalog and loading

    func test01_catalogIsPopulated() async {
        await step("catalog") {
            let catalog = try await RunAnywhere.models.list()
            let onDisk = catalog.filter { !$0.localPath.isEmpty }
            guard !onDisk.isEmpty else {
                throw E2EProblem("catalog=\(catalog.count) but nothing is installed")
            }
            let names = onDisk.prefix(12).map(\.id).joined(separator: ", ")
            return "catalog=\(catalog.count) installed=\(onDisk.count): \(names)"
        }
    }

    func test02_languageModelLoadsAndAnswers() async {
        await step("llm.generate") {
            let model = try await self.firstInstalled(.language)
            _ = try await RunAnywhere.models.load(id: model.id)
            let result = try await RunAnywhere.llm.generate(
                prompt: "Reply with exactly one word: ready",
                options: self.shortOptions()
            )
            guard !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw E2EProblem("\(model.id) loaded but produced no text")
            }
            return "\(model.id) -> \"\(result.text.prefix(80))\" (\(result.outputTokens) tokens)"
        }
    }

    // MARK: - Reasoning
    //
    // The template writes a pre-closed `<think></think>` pair whenever
    // `enable_thinking` is undefined, so "unset" meant "off" and the toggle
    // never did anything. Both directions are checked because a fix that turns
    // reasoning permanently on is as wrong as one that leaves it permanently
    // off.

    func test03_reasoningIsHonouredByEveryModelThatAdvertisesIt() async {
        let candidates: [RAModelInfo]
        do {
            candidates = try await allThinkingCapable()
        } catch {
            report("FAIL reasoning — \(error)")
            XCTFail("reasoning: \(error)")
            return
        }

        var broken: [String] = []
        for model in candidates {
            do {
                _ = try await RunAnywhere.models.load(id: model.id)
                let off = try await self.answer(reasoning: .off, from: model)
                let on = try await self.answer(reasoning: .on, from: model)

                let offThinking = (off.thinkingText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let onThinking = (on.thinkingText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let onAnswer = on.text.trimmingCharacters(in: .whitespacesAndNewlines)

                var faults: [String] = []
                if !offThinking.isEmpty { faults.append("off still reasoned (\(offThinking.count) chars)") }
                if onThinking.isEmpty { faults.append("on did not reason") }
                if onAnswer.contains("</think>") { faults.append("a think tag reached the answer") }
                if onAnswer.isEmpty { faults.append("on left no answer") }

                if faults.isEmpty {
                    report("PASS reasoning \(model.id) — off=0, on=\(onThinking.count) chars, answer=\"\(onAnswer.prefix(60))\"")
                } else {
                    report("FAIL reasoning \(model.id) — \(faults.joined(separator: "; "))")
                    broken.append(model.id)
                }
            } catch {
                report("FAIL reasoning \(model.id) — \(error)")
                broken.append(model.id)
            }
        }

        XCTAssertTrue(
            broken.isEmpty,
            "these models show a Thinking badge but do not honour the toggle: \(broken.joined(separator: ", "))"
        )
    }

    /// The options chat really sends, not a bare prompt.
    ///
    /// Judging a model on a prompt with no system instruction measures the
    /// wrong thing: given nothing to go on, a small model has no reason to
    /// reason, and the failure is the harness rather than the model. This is
    /// what a reader with the Thinking toggle on actually gets.
    @MainActor
    private func answer(
        reasoning mode: ReasoningMode,
        from model: RAModelInfo
    ) async throws -> GenerationResult {
        var options = chatOptions(thinking: mode == .on, model: model)
        options.maxOutputTokens = 2048
        var reasoning = ReasoningOptions()
        reasoning.mode = mode
        reasoning.includeInOutput = mode == .on
        options.reasoning = reasoning
        return try await RunAnywhere.llm.generate(
            prompt: "If a train leaves at 3:15pm and takes 95 minutes, what time does it arrive?",
            options: options
        )
    }

    // MARK: - Streaming, as chat actually calls it

    /// Chat streams. The complaints were that nothing appeared until the end,
    /// that the reply was then empty, and that reasoning turned up as the
    /// answer — all three are visible only through the stream, and only with
    /// the options the chat screen really sends.
    func test10_chatStreamsWithThinkingOff() async {
        await step("stream, thinking off") {
            let model = try await self.firstThinkingCapableOrAny()
            _ = try await RunAnywhere.models.load(id: model.id)

            let seen = try await self.collect(
                chatOptions(thinking: false, model: model),
                prompt: "In three sentences, explain why the sky looks blue."
            )
            self.report("  .. off: model=\(model.id) deltas=\(seen.deltas) text=\(seen.text.count) reasoning=\(seen.reasoning.count)")
            guard seen.deltas > 1 else {
                throw E2EProblem("arrived in \(seen.deltas) chunk(s) — not streaming; text=\"\(seen.text.prefix(100))\"")
            }
            guard !seen.text.isEmpty else { throw E2EProblem("streamed nothing") }
            guard seen.reasoning.isEmpty else {
                throw E2EProblem("reasoned with thinking off: \(seen.reasoning.prefix(80))")
            }
            return "\(model.id) -> \(seen.deltas) chunks, \"\(seen.text.prefix(70))\""
        }
    }

    func test11_chatStreamsReasoningSeparatelyWithThinkingOn() async {
        await step("stream, thinking on") {
            let model = try await self.firstThinkingCapableOrAny()
            _ = try await RunAnywhere.models.load(id: model.id)

            let seen = try await self.collect(chatOptions(thinking: true, model: model))
            self.report("  .. on: model=\(model.id) deltas=\(seen.deltas) text=\(seen.text.count) reasoning=\(seen.reasoning.count)")
            guard !seen.reasoning.isEmpty else {
                throw E2EProblem("no reasoning reached the caller; text=\"\(seen.text.prefix(80))\"")
            }
            guard !seen.text.isEmpty else {
                throw E2EProblem("all \(seen.reasoning.count) chars went to reasoning, leaving no answer")
            }
            guard !seen.text.contains("</think>") else {
                throw E2EProblem("a think tag reached the answer")
            }
            return "\(model.id) -> reasoning=\(seen.reasoning.count), answer=\"\(seen.text.prefix(70))\""
        }
    }

    /// The exact options ChatViewModel builds, so a test passing here means the
    /// chat screen behaves the same way.
    @MainActor
    private func chatOptions(thinking: Bool, model: RAModelInfo) -> LlmOptions {
        var options = LlmOptions()
        options.systemPrompt = ChatViewModel.systemPrompt(
            toolsEnabled: false,
            thinkingEnabled: thinking
        )
        options.model = model.id
        options.toolChoice = .none
        options.maxOutputTokens = 2048
        var reasoning = ReasoningOptions()
        reasoning.mode = thinking ? .on : .off
        reasoning.includeInOutput = thinking
        options.reasoning = reasoning
        return options
    }

    private func collect(
        _ options: LlmOptions,
        prompt: String = "If a train leaves at 3:15pm and takes 95 minutes, what time does it arrive?"
    ) async throws -> (text: String, reasoning: String, deltas: Int) {
        var text = ""
        var reasoning = ""
        var deltas = 0
        let stream = try await RunAnywhere.llm.generateStream(prompt: prompt, options: options)
        for try await event in stream {
            switch event {
            case .textDelta(_, _, _, _, let chunk):
                text += chunk
                deltas += 1
            case .reasoningDelta(_, _, _, _, let chunk):
                reasoning += chunk
                deltas += 1
            case .completed(_, let result):
                if !result.text.isEmpty { text = result.text }
                if let thoughts = result.thinkingText, !thoughts.isEmpty { reasoning = thoughts }
            default:
                continue
            }
        }
        return (text.trimmingCharacters(in: .whitespacesAndNewlines),
                reasoning.trimmingCharacters(in: .whitespacesAndNewlines),
                deltas)
    }

    private func firstThinkingCapableOrAny() async throws -> RAModelInfo {
        let capable = try? await allThinkingCapable()
        if let first = capable?.first { return first }
        return try await firstInstalled(.language)
    }
    /// The exact turn from the screenshot: "hi", thinking on, on the model the
    /// app defaults to. It produced a page of self-argument in the answer
    /// bubble, quoting the system prompt back at itself.
    func test12_greetingOnTheDefaultThinkingModel() async {
        await step("greeting, thinking on") {
            let catalog = try await RunAnywhere.models.list()
            guard let model = catalog.first(where: { $0.id == "mlx-qwen3.5-0.8b-mlx-4bit" }) else {
                throw E2EProblem("mlx-qwen3.5-0.8b-mlx-4bit is not installed")
            }
            _ = try await RunAnywhere.models.load(id: model.id)
            let seen = try await self.collect(
                self.chatOptions(thinking: true, model: model),
                prompt: "hi"
            )
            self.report("  .. hi: deltas=\(seen.deltas) text=\(seen.text.count) reasoning=\(seen.reasoning.count)")
            self.report("  .. hi text: \(seen.text.prefix(200))")

            // The instruction is for the model, not for the reader.
            let leaked = ["I need to answer the question", "The prompt says", "this is a bit confusing"]
            if let quote = leaked.first(where: { seen.text.contains($0) }) {
                throw E2EProblem("the reply quotes its own instructions: \"\(quote)\"")
            }
            guard seen.text.count < 400 else {
                throw E2EProblem("a greeting produced \(seen.text.count) chars of answer")
            }
            guard !seen.text.isEmpty else { throw E2EProblem("no reply") }
            return "reasoning=\(seen.reasoning.count), answer=\"\(seen.text.prefix(90))\""
        }
    }
    // MARK: - Vision
    //
    // A vision model loads under the multimodal component, which the LLM path
    // cannot see. Picking one for an ordinary chat used to fail with "no
    // lifecycle LLM model loaded".

    func test05_visionModelHoldsATextOnlyConversation() async {
        await step("vlm text-only") {
            let model = try await self.firstInstalled(.multimodal, fallback: .vision)
            _ = try await RunAnywhere.models.load(id: model.id)
            let result = try await RunAnywhere.vlm.generate(
                prompt: "Reply with exactly one word: ready",
                options: self.shortOptions()
            )
            guard !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw E2EProblem("\(model.id) answered nothing to a text-only turn")
            }
            return "\(model.id) -> \"\(result.text.prefix(80))\""
        }
    }

    func test06_visionModelDescribesAnImage() async {
        await step("vlm image") {
            let model = try await self.firstInstalled(.multimodal, fallback: .vision)
            let picture = try self.fixture("Pictures/small.jpg")
            _ = try await RunAnywhere.models.load(id: model.id)
            let result = try await RunAnywhere.vlm.generate(
                image: .file(picture),
                prompt: "Describe this image in one sentence.",
                options: self.shortOptions(maxTokens: 160)
            )
            guard !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw E2EProblem("\(model.id) said nothing about the image")
            }
            return "\(model.id) -> \"\(result.text.prefix(120))\""
        }
    }

    // MARK: - Speech

    /// Every installed speech model, not just the first. A single failure told
    /// me only "Inference failed" with no way to know which model produced it.
    func test07_transcribesRecordedAudio() async {
        let recording: String
        let installed: [RAModelInfo]
        do {
            recording = try fixture("Music/meeting.wav")
            let catalog = try await RunAnywhere.models.list()
            installed = catalog.filter {
                !$0.localPath.isEmpty && $0.runtimeUnavailableReason == nil
                    && $0.category == .speechRecognition
            }
        } catch {
            report("FAIL stt — \(error)")
            XCTFail("stt: \(error)")
            return
        }
        guard !installed.isEmpty else {
            report("FAIL stt — no speech model installed")
            XCTFail("no speech model installed")
            return
        }

        // The fixture is spoken text about a certificate; a transcript sharing
        // none of its words is a transcript of something else.
        let spoken = ["certificate", "password", "monday", "gateway", "friday", "ops"]
        var broken: [String] = []
        for model in installed {
            do {
                _ = try await RunAnywhere.models.load(id: model.id)
                let text = try await RunAnywhere.stt.transcribe(.file(recording)).text
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if text.isEmpty {
                    report("FAIL stt \(model.id) — transcribed to nothing")
                    broken.append(model.id)
                } else if !spoken.contains(where: { text.lowercased().contains($0) }) {
                    report("FAIL stt \(model.id) — matches none of the spoken words: \"\(text.prefix(120))\"")
                    broken.append(model.id)
                } else {
                    report("PASS stt \(model.id) — \"\(text.prefix(100))\"")
                }
            } catch {
                report("FAIL stt \(model.id) — \(error)")
                broken.append(model.id)
            }
        }
        XCTAssertTrue(broken.isEmpty, "speech models that could not transcribe: \(broken.joined(separator: ", "))")
    }

    func test08_synthesisProducesAudio() async {
        await step("tts") {
            let model = try await self.firstInstalled(.speechSynthesis)
            let audio = try await RunAnywhere.tts.synthesize("The certificate expires on Friday.")
            guard !audio.data.isEmpty, audio.durationMs > 0 else {
                throw E2EProblem("\(model.id) returned a zero-length clip")
            }
            // All-zero PCM passes a byte-count check but is not speech.
            guard audio.data.contains(where: { $0 != 0 }) else {
                throw E2EProblem("\(model.id) returned silence")
            }
            return "\(model.id) -> \(audio.data.count) bytes, \(audio.durationMs) ms @ \(audio.sampleRate) Hz"
        }
    }

    // MARK: - Helpers

    /// `toolChoice` is `.auto` by default, and `llm.generate` then quietly runs
    /// the whole tool-calling loop whenever anything is in the global registry —
    /// which the app's own bootstrap fills. These cases are about plain
    /// generation, so they say so.
    private func shortOptions(maxTokens: Int = 64) -> LlmOptions {
        var options = LlmOptions()
        options.maxOutputTokens = maxTokens
        options.toolChoice = .none
        return options
    }

    /// The first installed model in a category. Throws rather than skipping: a
    /// skipped test reads as a pass in the summary, and "we never checked" is
    /// not a pass.
    private func firstInstalled(
        _ category: RAModelCategory,
        fallback: RAModelCategory? = nil
    ) async throws -> RAModelInfo {
        let catalog = try await RunAnywhere.models.list()
        // `runtimeUnavailableReason` filters out Apple's built-in on a machine
        // with Apple Intelligence off; it is listed and "installed" but cannot
        // load, and picking it would test the refusal rather than the feature.
        let match = catalog.first {
            !$0.localPath.isEmpty && $0.runtimeUnavailableReason == nil
                && ($0.category == category || $0.category == fallback)
        }
        guard let match else {
            throw E2EProblem("no runnable installed model in category \(category)")
        }
        return match
    }

    /// Every installed model whose row carries the "Thinking" badge. Checking
    /// one of them proves nothing about the badge on the others.
    private func allThinkingCapable() async throws -> [RAModelInfo] {
        let catalog = try await RunAnywhere.models.list()
        let matches = catalog.filter {
            !$0.localPath.isEmpty && $0.runtimeUnavailableReason == nil
                && $0.category == .language && $0.supportsThinking
        }
        guard !matches.isEmpty else { throw E2EProblem("no installed model advertises reasoning") }
        return matches
    }

    private func fixture(_ relativePath: String) throws -> String {
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let path = home.appendingPathComponent(relativePath).path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else {
            throw E2EProblem("fixture missing: \(path)")
        }
        return path
    }
}

/// A named end-to-end failure. `SDKException` already reads well; this is for
/// the cases the SDK considers a success and the product does not.
struct E2EProblem: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
