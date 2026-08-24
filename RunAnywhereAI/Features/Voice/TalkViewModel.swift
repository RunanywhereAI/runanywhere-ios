import Foundation
import Observation
import RunAnywhere
import os

/// What the agent is doing, as the screen needs to say it.
enum TalkPhase: Equatable {
    case idle
    case connecting
    case listening
    case thinking
    case speaking
    case failed(String)

    var isLive: Bool {
        switch self {
        case .connecting, .listening, .thinking, .speaking: true
        case .idle, .failed: false
        }
    }
}

@Observable
@MainActor
final class TalkViewModel {
    let stt = VoiceModelSlot(.speech)
    let llm = VoiceModelSlot(.language)
    let tts = VoiceModelSlot(.voice)

    private(set) var phase: TalkPhase = .idle
    private(set) var transcript = ""
    private(set) var isTranscriptFinal = false
    private(set) var reply = ""
    private(set) var isSpeechDetected = false
    private(set) var isInterrupting = false
    /// The session is healthy but hearing nothing. Not an error, and shown as
    /// its own line so the screen stops claiming to listen while it holds.
    private(set) var inputSilentDetail: String?
    private(set) var lastError: String?

    private let defaults = DefaultModels()
    private let logger = Logger(subsystem: "com.runanywhere.RunAnywhereAI", category: "Talk")
    private var session: VoiceSession?
    private var eventTask: Task<Void, Never>?
    private var closeTask: Task<Void, Never>?
    private var isStopping = false

    var isReady: Bool { stt.model != nil && llm.model != nil && tts.model != nil }

    var canInterrupt: Bool { phase == .speaking && !isInterrupting }

    func prepare(store: ModelStore) async {
        for slot in [stt, llm, tts] { slot.observe(store: store) }
        await stt.adopt(store: store, preferred: defaults.sttID)
        await llm.adopt(store: store, preferred: defaults.llmID)
        await tts.adopt(store: store, preferred: defaults.ttsID)
    }

    func choose(_ slot: VoiceSlot, model: InstalledModel) {
        switch slot {
        case .speech:
            stt.select(model)
            defaults.sttID = model.id
        case .language:
            llm.select(model)
            defaults.llmID = model.id
        case .voice:
            tts.select(model)
            defaults.ttsID = model.id
        case .activity:
            break
        }
    }

    func activeID(for slot: VoiceSlot) -> String? {
        switch slot {
        case .speech: stt.id
        case .language: llm.id
        case .voice: tts.id
        case .activity: nil
        }
    }

    // MARK: - Conversation

    func start() async {
        guard !phase.isLive, !isStopping else { return }
        guard let sttID = stt.id, let llmID = llm.id, let ttsID = tts.id else {
            lastError = "Choose a speech, language and voice model before starting."
            return
        }

        // A previous session that failed still owns a microphone until its
        // close lands; starting on top of it would run two capture engines.
        if let closing = closeTask {
            closeTask = nil
            await closing.value
        }
        if let stale = session {
            session = nil
            await stale.close()
        }
        eventTask?.cancel()
        eventTask = nil

        phase = .connecting
        transcript = ""
        isTranscriptFinal = false
        reply = ""
        isSpeechDetected = false
        isInterrupting = false
        inputSilentDetail = nil
        lastError = nil

        do {
            // The session owns its prerequisites: it downloads, loads and wires
            // the three models plus a VAD, so nothing is preloaded here.
            let opened = try await RunAnywhere.voice.createSession(
                stt: ModelRef(id: sttID),
                llm: ModelRef(id: llmID),
                tts: ModelRef(id: ttsID)
            )
            session = opened

            let events = opened.events
            eventTask = Task { [weak self] in
                do {
                    for try await event in events {
                        guard let self else { return }
                        await MainActor.run { self.apply(event) }
                    }
                } catch {
                    guard let self else { return }
                    await MainActor.run { self.fail(error.localizedDescription) }
                }
            }

            try opened.start()
            phase = .listening
        } catch {
            logger.error("voice session failed to start: \(error, privacy: .public)")
            fail(error.localizedDescription)
        }
    }

    /// Cut the reply off and hand the turn back, without ending the session.
    func interrupt() async {
        guard let session, !isInterrupting else { return }
        isInterrupting = true
        await session.interrupt()
        isInterrupting = false
    }

    func stop() async {
        guard !isStopping else { return }
        isStopping = true
        eventTask?.cancel()
        eventTask = nil
        phase = .idle
        isSpeechDetected = false
        isInterrupting = false
        inputSilentDetail = nil
        let closing = session
        session = nil
        await closing?.close()
        isStopping = false
    }

    func teardown() {
        eventTask?.cancel()
        eventTask = nil
        for slot in [stt, llm, tts] { slot.stopObserving() }
        guard let closing = session else { return }
        session = nil
        phase = .idle
        Task { await closing.close() }
    }

    // MARK: - Events

    private func apply(_ event: VoiceEvent) {
        switch event {
        case .agentStateChanged(let state):
            apply(state)

        case .speechStarted:
            isSpeechDetected = true
            // A voice arrived, so "I can't hear you" has stopped being true.
            inputSilentDetail = nil
            lastError = nil

        case .speechEnded:
            isSpeechDetected = false

        case let .userTranscribed(text, isFinal):
            transcript = text
            isTranscriptFinal = isFinal
            if isFinal { reply = "" }

        case .agentResponse(let text):
            reply += text

        case .inputSilent(let detail):
            logger.warning("microphone delivering no signal: \(detail, privacy: .public)")
            inputSilentDetail = detail

        case let .error(message, recoverable):
            logger.error("voice session error: \(message, privacy: .public)")
            lastError = message
            if !recoverable { fail(message) }
        }
    }

    private func apply(_ state: AgentState) {
        switch state {
        case .listening:
            phase = .listening
            isSpeechDetected = false
        case .thinking:
            // A new turn begins here, so the previous answer stops being the
            // answer on screen. The transcript stays until the next one lands.
            reply = ""
            phase = .thinking
            isSpeechDetected = false
        case .speaking:
            phase = .speaking
        }
        if case .speaking = state {} else { isInterrupting = false }
    }

    /// A dead pipeline must not keep a live microphone, so the session is
    /// released here rather than left running behind an error message.
    private func fail(_ message: String) {
        guard !isStopping else { return }
        phase = .failed(message)
        lastError = message
        isSpeechDetected = false
        isInterrupting = false
        eventTask?.cancel()
        eventTask = nil
        guard let closing = session else { return }
        session = nil
        closeTask = Task { await closing.close() }
    }
}
