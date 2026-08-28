import Foundation
import Observation
import RunAnywhere
import os

/// A ready-made passage, so the screen can be tried without typing.
struct ReadAloudSample: Identifiable {
    let id: String
    let title: String
    let text: String

    static let all: [ReadAloudSample] = [
        ReadAloudSample(
            id: "greeting",
            title: "Greeting",
            text: "Hello. Everything you are hearing was generated on this device, "
                + "with no network connection and nothing sent anywhere."
        ),
        ReadAloudSample(
            id: "numbers",
            title: "Numbers",
            text: "The meeting moved to 3:45 on Tuesday the 12th, in room 208. "
                + "Bring the £1,200 estimate and the revised figures."
        ),
        ReadAloudSample(
            id: "paragraph",
            title: "Paragraph",
            text: "A speech model works in short windows. It listens to a slice of sound, "
                + "guesses which sounds it contains, and revises that guess as more arrives. "
                + "That is why a live transcript changes its mind halfway through a sentence."
        )
    ]
}

@Observable
@MainActor
final class ReadAloudViewModel {
    let tts = VoiceModelSlot(.voice)

    var text = ReadAloudSample.all[0].text
    var rate: Double = 1.0

    private(set) var isSpeaking = false
    private(set) var isPreparing = false
    private(set) var lastError: String?

    private let defaults = DefaultModels()
    private let logger = Logger(subsystem: "com.runanywhere.RunAnywhereAI", category: "ReadAloud")
    private var speech: SpeechHandle?
    /// Set when playback is stopped on purpose, so the interruption thrown back
    /// into `speak` is not reported as a failure.
    private var didRequestStop = false

    var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    var canSpeak: Bool { !trimmed.isEmpty && !isPreparing }

    func prepare(store: ModelStore) async {
        tts.observe(store: store)
        await tts.adopt(store: store, preferred: defaults.ttsID)
    }

    func choose(_ model: InstalledModel) {
        tts.select(model)
        defaults.ttsID = model.id
    }

    func use(_ sample: ReadAloudSample) {
        text = sample.text
    }

    func speak() async {
        guard !isSpeaking, canSpeak else { return }
        lastError = nil
        didRequestStop = false

        isPreparing = true
        let ready = await tts.ensureLoaded()
        isPreparing = false
        guard ready else {
            lastError = tts.lastError ?? "No voice is loaded."
            return
        }

        let phrase = trimmed
        isSpeaking = true
        do {
            // `speak` returns once playback *starts*; only the handle knows when
            // the sound actually ends, and treating the return as the end takes
            // the Stop control off screen for the whole utterance.
            let handle = try await RunAnywhere.tts.speak(
                phrase,
                options: TtsOptions(speed: Float(rate))
            )
            speech = handle
            await handle.waitForPlayout()
            if let failure = handle.error, !didRequestStop {
                logger.error("playback failed: \(failure, privacy: .public)")
                lastError = "Playback failed: \(failure.localizedDescription)"
            }
        } catch {
            if !didRequestStop {
                logger.error("speech failed: \(error, privacy: .public)")
                lastError = "Speech failed: \(error.localizedDescription)"
            }
        }

        speech = nil
        isSpeaking = false
    }

    func stop() async {
        guard isSpeaking else { return }
        didRequestStop = true
        await speech?.interrupt()
        isSpeaking = false
    }

    func teardown() {
        tts.stopObserving()
        guard let closing = speech else { return }
        didRequestStop = true
        speech = nil
        isSpeaking = false
        Task { await closing.interrupt() }
    }
}
