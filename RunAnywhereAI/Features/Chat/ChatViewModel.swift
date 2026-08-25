import Foundation
import Observation
import RunAnywhere
import os

@Observable
@MainActor
final class ChatViewModel {
    private(set) var turns: [ChatTurn] = []
    private(set) var draft: ChatTurn?
    private(set) var isGenerating = false
    private(set) var isStopping = false
    private(set) var speakingTurnID: UUID?
    private(set) var speakingProgress: Double = 0
    private(set) var isListening = false
    var lastError: String?
    var toolsUnavailable: String?

    var loadedModelName: String?
    var loadedModelID: String?
    var modelContextLength = 0
    var modelBackend = ""
    /// A vision model answers text through the VLM component, because that is
    /// the component it loads into — the LLM path cannot see it at all.
    var modelIsVision = false
    var attachment: ChatAttachment?
    var embeddingModelID: String?
    private(set) var indexState: DocumentIndexState = .idle

    private var ragSession: RagSession?
    private var ragKey: String?
    var toolsEnabled = false
    var thinkingEnabled = false

    private var task: Task<Void, Never>?
    private var speechTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.runanywhere.RunAnywhereAI", category: "Chat")

    var isEmpty: Bool { turns.isEmpty && draft == nil }

    var visibleTurns: [ChatTurn] {
        draft.map { turns + [$0] } ?? turns
    }

    // MARK: - Sending

    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let staged = attachment
        guard !trimmed.isEmpty || staged != nil, !isGenerating else { return }

        toolsUnavailable = nil
        turns.append(ChatTurn(
            role: .user,
            text: trimmed,
            attachmentName: staged?.filename,
            attachmentIsImage: staged?.isImage ?? false
        ))

        if let staged {
            attachment = nil
            switch staged.payload {
            case .image:
                startVision(staged, prompt: trimmed)
            case .document(let body):
                startDocument(staged, body: body, prompt: trimmed)
            }
            return
        }

        startGeneration()
    }

    // MARK: - Vision

    private func startVision(_ attachment: ChatAttachment, prompt: String) {
        task?.cancel()
        isGenerating = true
        lastError = nil
        var pending = ChatTurn(role: .assistant)
        draft = pending

        task = Task { [weak self] in
            guard let self else { return }
            do {
                let image = try attachment.modelImage()
                let question = prompt.isEmpty ? "Describe this image." : prompt
                // Cap the answer. An unbounded vision decode on a large photo is
                // what took the process down with no crash report: it is killed
                // on memory rather than trapped, so nothing is written.
                var options = LlmOptions()
                options.maxOutputTokens = 320
                // Same instruction the text path sends. Without it the model
                // opens with "The image you have shared appears to be a
                // photograph…" and the 320-token cap then cuts the actual
                // answer off mid-sentence.
                options.systemPrompt = Self.systemPrompt(toolsEnabled: false)
                let stream = try await RunAnywhere.vlm.generateStream(
                    image: image,
                    prompt: question,
                    options: options
                )
                for try await event in stream {
                    if Task.isCancelled { break }
                    switch event {
                    case .textDelta(_, _, _, _, let text):
                        pending.text += text
                        draft = pending
                    case .completed(_, let result):
                        if !result.text.isEmpty { pending.text = result.text }
                        pending.metrics = TurnMetrics(
                            timeToFirstTokenMs: result.timeToFirstTokenMs,
                            tokensPerSecond: result.tokensPerSecond,
                            outputTokens: result.outputTokens
                        )
                    case .failed(_, let partial, let error):
                        if let partial, pending.text.isEmpty { pending.text = partial }
                        pending.failure = Self.describe(error)
                    default:
                        continue
                    }
                }
            } catch {
                pending.failure = Self.describe(error)
            }
            finish(pending)
        }
    }

    // MARK: - Documents

    private func startDocument(_ attachment: ChatAttachment, body: String, prompt: String) {
        task?.cancel()
        isGenerating = true
        lastError = nil
        var pending = ChatTurn(role: .assistant)
        draft = pending

        task = Task { [weak self] in
            guard let self else { return }
            do {
                let session = try await prepareSession(for: attachment, body: body)
                let question = prompt.isEmpty ? "Summarize this document." : prompt
                var answer = ""
                let events: AsyncThrowingStream<RagEvent, Error>
                do {
                    // The RAG graph streams engine tokens straight through with
                    // no splitter, and only extracts thinking from the final
                    // answer. With reasoning unstated a thinking model's whole
                    // chain of thought scrolls into the answer bubble for the
                    // turn, then snaps to the real answer at completion, and
                    // half the generation budget goes to reasoning nobody sees.
                    var generation = LlmOptions()
                    generation.systemPrompt = Self.systemPrompt(toolsEnabled: false)
                    var reasoning = ReasoningOptions()
                    reasoning.mode = thinkingEnabled ? .on : .off
                    reasoning.includeInOutput = false
                    generation.reasoning = reasoning
                    events = try await session.queryStream(
                        question: question,
                        options: RagQueryOptions(generation: generation)
                    )
                } catch {
                    throw RagStageError(stage: "asking the document", underlying: Self.describe(error))
                }
                for try await event in events {
                    if Task.isCancelled { break }
                    switch event {
                    case .token(let text, _):
                        answer += text
                        pending.text = answer
                        draft = pending
                    case .completed(let result):
                        pending.text = result.answer.isEmpty ? answer : result.answer
                    case .retrieved:
                        continue
                    }
                }
            } catch let staged as RagStageError {
                indexState = .failed(staged.message)
                pending.failure = staged.message
            } catch {
                let detail = Self.describe(error)
                indexState = .failed(detail)
                pending.failure = "Answering from the document failed: \(detail)"
            }
            finish(pending)
        }
    }

    /// One session per document + embedding model + answer model, so a follow-up
    /// question reuses the index instead of re-embedding the whole file.
    private func prepareSession(for attachment: ChatAttachment, body: String) async throws -> RagSession {
        guard let embeddingModelID else {
            throw AttachmentError.unsupported(
                "No embedding model is selected. Pick one under Settings, Default models, Documents."
            )
        }
        let key = "\(attachment.id)|\(embeddingModelID)|\(loadedModelName ?? "")"
        if let ragSession, ragKey == key { return ragSession }

        indexState = .indexing

        let session: RagSession
        do {
            session = try await RunAnywhere.rag.open(
                embeddingModel: ModelRef(id: embeddingModelID),
                llmModel: loadedModelID.map { ModelRef(id: $0) }
            )
        } catch {
            throw RagStageError(stage: "opening the index", underlying: Self.describe(error))
        }

        do {
            try await session.ingest(document: RagDocument(
                text: body,
                metadata: ["source": attachment.filename, "filename": attachment.filename]
            ))
        } catch {
            throw RagStageError(stage: "indexing \(attachment.filename)", underlying: Self.describe(error))
        }

        ragSession = session
        ragKey = key
        indexState = .indexed
        return session
    }

    func retryLast() {
        guard !isGenerating else { return }
        while let last = turns.last, last.role == .assistant {
            turns.removeLast()
        }
        guard turns.last?.role == .user else { return }
        startGeneration()
    }

    func stop() {
        guard isGenerating else { return }
        isStopping = true
        task?.cancel()
    }

    private func startGeneration() {
        task?.cancel()
        isGenerating = true
        isStopping = false
        lastError = nil

        let history = turns.map {
            ChatMessage(role: $0.role == .user ? .user : .assistant, content: $0.text)
        }
        let options = makeOptions()
        var pending = ChatTurn(role: .assistant)
        draft = pending

        task = Task { [weak self] in
            guard let self else { return }
            let started = Date()
            var firstTokenAt: Date?

            do {
                if toolsEnabled {
                    if let block = Self.toolsBlockedReason(contextLength: modelContextLength) {
                        pending.failure = block
                        finish(pending)
                        return
                    }
                    // `generateStream` never consults the tool registry; only the
                    // one-shot `generate` runs the call-and-execute loop. With
                    // tools on we trade streaming for tools rather than silently
                    // dropping every tool the model asks for.
                    do {
                        try await runWithTools(history: history, pending: &pending, started: started)
                        finish(pending)
                        return
                    } catch {
                        // A model that cannot drive the loop should still answer.
                        // Falling through to a plain generation beats handing the
                        // reader a native error for a turn they can still have.
                        let detail = Self.describe(error)
                        print("DIAG tool loop failed: \(error) | type=\(type(of: error)) | detail=\(detail)")
                        logger.error("tool loop failed, falling back: \(detail, privacy: .public)")
                        toolsUnavailable = Self.toolFailureAdvice(backend: modelBackend, detail: detail)
                        pending.tools = []
                    }
                }

                let stream = modelIsVision
                    ? try await RunAnywhere.vlm.generateStream(
                        prompt: Self.flatten(history),
                        options: options
                    )
                    : try await RunAnywhere.llm.generateStream(messages: history, options: options)

                for try await event in stream {
                    if Task.isCancelled { break }
                    switch event {
                    case .started:
                        continue

                    case .textDelta(_, _, _, _, let text):
                        if firstTokenAt == nil { firstTokenAt = Date() }
                        pending.text += text
                        draft = pending

                    case .reasoningDelta(_, _, _, _, let text):
                        if firstTokenAt == nil { firstTokenAt = Date() }
                        pending.thinking += text
                        draft = pending

                    case .toolCallAdded(_, _, let itemId, _, let call):
                        pending.tools.append(ToolInvocation(id: itemId, name: call.name))
                        draft = pending

                    case .toolArgumentsDelta(_, _, let itemId, let delta):
                        if let index = pending.tools.firstIndex(where: { $0.id == itemId }) {
                            pending.tools[index].arguments += delta
                            draft = pending
                        }

                    case .toolArgumentsDone(_, _, let itemId, let arguments):
                        if let index = pending.tools.firstIndex(where: { $0.id == itemId }) {
                            pending.tools[index].arguments = arguments
                            pending.tools[index].isComplete = true
                            draft = pending
                        }

                    case .usage(_, _, _, let outputTokens):
                        pending.metrics.outputTokens = outputTokens
                        draft = pending

                    case .completed(_, let result):
                        pending.text = result.text.isEmpty ? pending.text : result.text
                        if let thinking = result.thinkingText, !thinking.isEmpty {
                            pending.thinking = thinking
                        }
                        pending.metrics = TurnMetrics(
                            timeToFirstTokenMs: result.timeToFirstTokenMs,
                            tokensPerSecond: result.tokensPerSecond,
                            outputTokens: result.outputTokens
                        )

                    case .failed(_, let partial, let error):
                        if let partial, pending.text.isEmpty { pending.text = partial }
                        pending.failure = error.message

                    case .cancelled(_, let partial):
                        if let partial, pending.text.isEmpty { pending.text = partial }
                        pending.wasCancelled = true

                    default:
                        continue
                    }
                }
            } catch is CancellationError {
                pending.wasCancelled = true
            } catch {
                let detail = Self.describe(error)
                logger.error("generation failed: \(detail, privacy: .public)")
                pending.failure = detail
            }

            if Task.isCancelled, !pending.wasCancelled {
                pending.wasCancelled = true
            }

            if pending.metrics.isEmpty, let firstTokenAt {
                pending.metrics.timeToFirstTokenMs = Int64(firstTokenAt.timeIntervalSince(started) * 1000)
            }

            finish(pending)
        }
    }

    /// Fold a progress snapshot into the in-flight turn.
    ///
    /// The tool calls in `draft` are not known until the loop returns, so a
    /// placeholder invocation carries the stages until then and is replaced by
    /// the real one, stages and all, when the loop finishes.
    private func applyResearchStages(_ snapshot: [String: [ResearchStage]]) {
        guard var pending = draft else { return }
        for (toolName, stages) in snapshot {
            let placeholderID = "progress-\(toolName)"
            if let index = pending.tools.firstIndex(where: { $0.id == placeholderID }) {
                pending.tools[index].stages = stages
            } else {
                pending.tools.append(
                    ToolInvocation(id: placeholderID, name: toolName, stages: stages)
                )
            }
        }
        draft = pending
    }

    /// Tool runs go through `RunAnywhere.generateWithTools`, not `llm.generate`.
    ///
    /// The v3 `llm.generate` path leaves `autoExecute` false, so it only leaks
    /// the raw tool call instead of running it. The loop also needs a short,
    /// deterministic final answer with reasoning off; leaving sampling loose or
    /// thinking on is what returned -130 (generation failed).
    ///
    /// `tools` is set rather than left empty: an empty list means the whole
    /// registry, and the registry is sized for the workflow editor. Chat's
    /// pair comes from `ChatTools`.
    static func toolCallingOptions(tools: [ToolDefinition]) -> RAToolCallingOptions {
        var options = RAToolCallingOptions()
        options.tools = tools
        options.autoExecute = true
        // Tools stay available so the model can act on a `recall` a result
        // hands back — a thin search answered by searching again is the whole
        // point of that field, and withdrawing the tool after one call made it
        // impossible. Four rounds covers a question with a couple of parts
        // without letting a confused model loop.
        options.maxToolCalls = 4
        options.keepToolsAvailable = true
        options.parallelToolCalls = true
        options.disableThinking = true
        return options
    }

    static func toolGenerationOptions(systemPrompt: String?) -> RALLMGenerationOptions {
        var generation = RALLMGenerationOptions()
        if let systemPrompt, !systemPrompt.isEmpty {
            generation.systemPrompt = systemPrompt
        }
        // 96 was a workaround from the -130 era, when the real fault was MLX
        // discarding tool calls. That is fixed in commons now, and 96 tokens is
        // roughly seventy words: enough to relay `get_current_time`, nowhere
        // near enough for a grounded answer built from web research.
        generation.maxOutputTokens = 512
        generation.temperature = 0
        generation.topP = 1
        var reasoning = RAReasoningOptions()
        reasoning.mode = .off
        generation.reasoning = reasoning
        return generation
    }

    static let minimumToolContextTokens = 1024

    static func toolsBlockedReason(contextLength: Int) -> String? {
        guard contextLength > 0 else {
            return "This model does not publish a context window, so tools cannot run on it. Choose one with at least 1,024 tokens."
        }
        guard contextLength >= minimumToolContextTokens else {
            return "This model has a \(contextLength)-token context window. Tools need at least \(minimumToolContextTokens). Choose a larger model."
        }
        return nil
    }

    private func runWithTools(
        history: [ChatMessage],
        pending: inout ChatTurn,
        started: Date
    ) async throws {
        let prompt = history.last(where: { $0.role == .user })?.content ?? ""

        // Progress arrives on commons' worker thread while the loop blocks
        // here, so it is buffered into an actor and folded into the turn as it
        // lands rather than written straight into observable state.
        let collector = ResearchStageCollector()
        let progressTask = Task { @MainActor [weak self] in
            for await snapshot in collector.stream {
                guard let self, self.draft != nil else { continue }
                self.applyResearchStages(snapshot)
            }
        }
        defer { progressTask.cancel() }

        let loop = try await RunAnywhere.generateWithTools(
            prompt: prompt,
            options: Self.toolGenerationOptions(systemPrompt: Self.systemPrompt(toolsEnabled: true)),
            toolOptions: Self.toolCallingOptions(tools: await ChatTools.offeredTools()),
            // The turn being answered is the prompt, so everything before it is
            // the conversation. Omitting this made every tool-enabled turn a
            // cold start: "who won it?" after a question about a match had
            // nothing to resolve "it" against, while the same follow-up worked
            // with tools off because `generateStream(messages:)` carries them.
            history: history.dropLast().map(\.content),
            onProgress: { progress in collector.record(progress) }
        )
        collector.finish()

        if loop.hasErrorMessage {
            throw SDKException(
                code: RAErrorCode(rawValue: Int(loop.errorCode)) ?? .unspecified,
                message: loop.errorMessage,
                category: .component
            )
        }

        let stagesByTool = collector.stagesByTool()
        pending.tools = loop.toolCalls.enumerated().map { index, call in
            ToolInvocation(
                id: "\(call.name)-\(index)",
                name: call.name,
                arguments: call.argumentsJson,
                isComplete: true,
                stages: stagesByTool[call.name] ?? []
            )
        }
        pending.text = loop.text.isEmpty
            ? "The model finished tool calling without a text answer."
            : loop.text
        if !loop.thinkingContent.isEmpty {
            pending.thinking = loop.thinkingContent
        }
        _ = started
    }

    /// The native loop returns a bare -130 with no message of its own, so the
    /// advice has to come from here. Naming the backend matters because plain
    /// generation on the same model succeeds; the loop is the only thing that
    /// fails, and the backend is the variable worth changing.
    static func toolFailureAdvice(backend: String, detail: String) -> String {
        let base = "Tools did not run on this model, so the reply was generated without them."
        guard !backend.isEmpty, backend != "llama.cpp" else {
            return "\(base) \(detail)"
        }
        return "\(base) It is running on \(backend); try a llama.cpp (GGUF) chat model, which is what the tool loop is exercised against. \(detail)"
    }

    /// The SDK's own message, not the enum case. `String(describing:)` on an
    /// `SDKException` prints the case and swallows the text the native loop
    /// actually reported, which is the only part that says what went wrong.
    static func describe(_ error: Error) -> String {
        if let sdk = error as? SDKException {
            let message = sdk.message.trimmingCharacters(in: .whitespacesAndNewlines)
            let code = String(describing: sdk.code)
            return message.isEmpty ? "Generation failed (\(code))" : "\(message) (\(code))"
        }
        return error.localizedDescription
    }

    private func finish(_ turn: ChatTurn) {
        draft = nil
        isGenerating = false
        isStopping = false
        if turn.failure != nil { lastError = turn.failure }
        guard !turn.isEmpty || turn.failure != nil else { return }
        turns.append(turn)
    }

    /// The VLM text entry takes one prompt rather than a message list, so the
    /// conversation is rendered plainly. Roles are named because dropping them
    /// turns a dialogue into one run-on paragraph the model answers as a whole.
    static func flatten(_ history: [ChatMessage]) -> String {
        var lines = history.map { message in
            (message.role == .user ? "User: " : "Assistant: ") + message.content
        }
        lines.append("Assistant:")
        return lines.joined(separator: "\n\n")
    }

    /// Who the model is, on every turn. Two sentences, no conditionals, and
    /// nothing about how to handle the input.
    ///
    /// Longer drafts kept failing in the same way. "Answer the question that
    /// was asked, then stop" assumes there is a question: given "hi", a 0.8B
    /// model quoted the instruction back, wrote "Wait, this is a bit
    /// confusing", and looped on that for the whole budget. A small model
    /// treats a meta-instruction as something to reason about rather than
    /// something to obey, so this says what it is and how long to be, and
    /// stops there.
    static let assistantPrompt = """
        You are a helpful assistant running privately on this device. \
        Keep your replies brief and direct.
        """
    /// Added only when the reader asked to see the thinking.
    ///
    /// Scoped on purpose. Brevity alone reads as "do not bother working it
    /// out" — a 2.6B model given only that answered "3:15pm + 95 minutes =
    /// 6:50pm". An unscoped "work the problem out before you answer" fixed
    /// that and broke the other end: a 0.8B model applied it to "hi" and spent
    /// its whole budget reasoning about a greeting without ever answering.
    /// Naming the condition is what serves both.
    static let reasoningClause = "Reason through anything that needs it before replying."

    /// The instruction for one turn: who the model is, plus how to use its
    /// tools when it has any, plus a nudge to reason when the reader asked for
    /// reasoning. Composed, never substituted.
    ///
    /// The tool contract used to be passed alone, which swapped out the model's
    /// identity for a page about `web_research`, so a turn that called no tool
    /// answered as if the tool document were the whole brief.
    static func systemPrompt(toolsEnabled: Bool, thinkingEnabled: Bool = false) -> String {
        var prompt = assistantPrompt
        if thinkingEnabled { prompt += " " + reasoningClause }
        if toolsEnabled { prompt += "\n\n" + ChatTools.skill }
        return prompt
    }

    private func makeOptions() -> LlmOptions {
        var options = LlmOptions()
        options.systemPrompt = Self.systemPrompt(
            toolsEnabled: toolsEnabled,
            thinkingEnabled: thinkingEnabled
        )

        // Both directions are stated. Leaving reasoning unset does not mean
        // "no opinion": with a thinking-capable model the splitter reads it as
        // "reasoning might be coming" and withholds the whole answer waiting
        // for a closing tag that a model answering plainly never sends, so
        // nothing streamed and the turn arrived in one lump at the end.
        var reasoning = ReasoningOptions()
        reasoning.mode = thinkingEnabled ? .on : .off
        // Thought tokens are dropped at the boundary unless the caller asks for
        // them. Without this the reasoning channel is a bin: the disclosure
        // never fills while streaming, and once a prefilled `<think>` sends the
        // whole turn down that channel the reply comes back empty.
        reasoning.includeInOutput = thinkingEnabled
        options.reasoning = reasoning
        return options
    }

    // MARK: - Turn actions

    func text(for id: UUID) -> String? {
        visibleTurns.first { $0.id == id }?.text
    }

    func delete(_ id: UUID) {
        turns.removeAll { $0.id == id }
    }

    /// Everything up to and including `id`, as a new conversation.
    func fork(at id: UUID) -> [ChatTurn] {
        guard let index = turns.firstIndex(where: { $0.id == id }) else { return turns }
        return Array(turns.prefix(through: index))
    }

    func adopt(_ forked: [ChatTurn]) {
        task?.cancel()
        turns = forked
        draft = nil
        isGenerating = false
    }

    func newConversation() {
        task?.cancel()
        stopSpeaking()
        turns = []
        draft = nil
        isGenerating = false
        lastError = nil
    }

    // MARK: - Speech

    func speak(_ turn: ChatTurn) {
        guard speakingTurnID != turn.id else {
            stopSpeaking()
            return
        }
        stopSpeaking()

        let segments = Self.segments(of: turn.text)
        guard !segments.isEmpty else { return }

        speakingTurnID = turn.id
        speakingProgress = 0

        let total = Double(segments.reduce(0) { $0 + $1.count })
        speechTask = Task { [weak self] in
            guard let self else { return }
            var spoken = 0.0
            do {
                for segment in segments {
                    if Task.isCancelled { break }
                    let handle = try await RunAnywhere.tts.speak(segment)
                    await handle.waitForPlayout()
                    spoken += Double(segment.count)
                    speakingProgress = min(1, spoken / max(total, 1))
                }
            } catch {
                logger.error("speak failed: \(error, privacy: .public)")
                lastError = "No text-to-speech model is loaded."
            }
            speakingProgress = 0
            speakingTurnID = nil
        }
    }

    /// Sentence-sized pieces, so playback starts after the first one instead of
    /// after the whole reply has been synthesized.
    static func segments(of text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var out: [String] = []
        var current = ""
        for character in trimmed {
            current.append(character)
            if ".!?\n".contains(character), current.count >= 24 {
                out.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                current = ""
            }
        }
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty {
            if tail.count < 24, var last = out.popLast() {
                last += " " + tail
                out.append(last)
            } else {
                out.append(tail)
            }
        }
        return out.filter { !$0.isEmpty }
    }

    func stopSpeaking() {
        speechTask?.cancel()
        speechTask = nil
        speakingTurnID = nil
        speakingProgress = 0
    }
}


/// Which half of the document pipeline broke.
///
/// `rag.open`, `ingest` and `queryStream` all surface the same generic
/// `generationFailed`, so without naming the stage the reader cannot tell an
/// embedding problem from an answering one.
struct RagStageError: Error {
    let stage: String
    let underlying: String

    var message: String { "Failed while \(stage): \(underlying)" }
}
