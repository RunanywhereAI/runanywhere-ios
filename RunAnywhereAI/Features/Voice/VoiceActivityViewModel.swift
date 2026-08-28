import Foundation
import Observation
import RunAnywhere
import os

/// One speech boundary the detector reported.
struct SpeechActivityEntry: Identifiable {
    enum Kind {
        case started
        case ended

        var label: String {
            switch self {
            case .started: "Speech started"
            case .ended: "Speech ended"
            }
        }

        var symbol: String {
            switch self {
            case .started: "waveform"
            case .ended: "waveform.slash"
            }
        }
    }

    let id = UUID()
    let kind: Kind
    let at: Date
    /// Seconds since listening began, which is what a reader is actually
    /// comparing entries by. Wall-clock time is shown too, but a log of
    /// timestamps four seconds apart reads better as an offset.
    let offset: TimeInterval
}

@Observable
@MainActor
final class VoiceActivityViewModel {
    let vad = VoiceModelSlot(.activity)
    let levels = AudioLevelTrack()

    private(set) var isListening = false
    private(set) var isPreparing = false
    private(set) var isSpeechDetected = false
    private(set) var probability: Float = 0
    private(set) var utterances = 0
    private(set) var speechSeconds: TimeInterval = 0
    private(set) var log: [SpeechActivityEntry] = []
    private(set) var lastError: String?

    private static let sampleRate = 16_000
    private static let logLimit = 60

    private let capture = AudioCaptureManager()
    private let logger = Logger(subsystem: "com.runanywhere.RunAnywhereAI", category: "VoiceActivity")

    private var stream: VadStream?
    private var streamTask: Task<Void, Never>?
    private var startedAt: Date?
    private var speechStartedAt: Date?

    func prepare(store: ModelStore) async {
        vad.observe(store: store)
        await vad.adopt(store: store)
    }

    func choose(_ model: InstalledModel) {
        vad.select(model)
    }

    func clearLog() {
        log.removeAll()
        utterances = 0
        speechSeconds = 0
    }

    func toggleListening() async {
        if isListening {
            await stop()
        } else {
            await start()
        }
    }

    // MARK: - Listening

    private func start() async {
        guard !isListening, !isPreparing else { return }
        lastError = nil

        isPreparing = true
        let ready = await vad.ensureLoaded()
        isPreparing = false
        guard ready else {
            lastError = vad.lastError ?? "No voice-activity model is loaded."
            return
        }

        guard await capture.requestPermission() else {
            lastError = "Microphone access was declined."
            return
        }

        startedAt = Date()
        speechStartedAt = nil
        isSpeechDetected = false
        probability = 0
        openStream()

        do {
            try await capture.startRecording { [weak self] data in
                MainActor.assumeIsolated {
                    self?.stream?.pushFrame(
                        AudioFrame(samples: data, sampleCount: data.count / 2)
                    )
                }
            }
        } catch {
            logger.error("microphone failed: \(error, privacy: .public)")
            lastError = "The microphone could not start: \(error.localizedDescription)"
            await closeStream()
            return
        }

        isListening = true
        levels.start(sampling: { [capture] in capture.audioLevel })
    }

    private func stop() async {
        guard isListening else { return }
        capture.stopRecording()
        levels.stop()
        isListening = false
        isSpeechDetected = false
        probability = 0
        if let began = speechStartedAt {
            speechSeconds += Date().timeIntervalSince(began)
            speechStartedAt = nil
        }
        await closeStream()
    }

    private func openStream() {
        let live = RunAnywhere.vad.openStream(
            format: AudioFormatSpec(encoding: .pcmS16Le, sampleRate: Self.sampleRate)
        )
        stream = live
        streamTask = Task { [weak self] in
            do {
                for try await event in live.events {
                    guard let self, !Task.isCancelled else { return }
                    await MainActor.run { self.apply(event) }
                }
            } catch {
                guard let self else { return }
                await MainActor.run {
                    self.logger.error("detection failed: \(error, privacy: .public)")
                    self.lastError = "Detection stopped: \(error.localizedDescription)"
                }
            }
        }
    }

    private func closeStream() async {
        streamTask?.cancel()
        streamTask = nil
        guard let live = stream else { return }
        stream = nil
        live.finish()
        await live.close()
    }

    private func apply(_ event: VadEvent) {
        switch event {
        case .speechStarted:
            guard !isSpeechDetected else { return }
            isSpeechDetected = true
            speechStartedAt = Date()
            utterances += 1
            record(.started)

        case .speechEnded:
            guard isSpeechDetected else { return }
            isSpeechDetected = false
            if let began = speechStartedAt {
                speechSeconds += Date().timeIntervalSince(began)
                speechStartedAt = nil
            }
            record(.ended)

        case let .activity(isSpeech, probability, _):
            self.probability = probability
            isSpeechDetected = isSpeech

        case .failed(let error):
            logger.error("detection failed: \(error, privacy: .public)")
            lastError = "Detection failed: \(error.localizedDescription)"

        case .completed:
            break
        }
    }

    private func record(_ kind: SpeechActivityEntry.Kind) {
        let now = Date()
        let entry = SpeechActivityEntry(
            kind: kind,
            at: now,
            offset: now.timeIntervalSince(startedAt ?? now)
        )
        log.insert(entry, at: 0)
        if log.count > Self.logLimit { log.removeLast() }
    }

    // MARK: - Cleanup

    func teardown() {
        capture.stopRecording()
        levels.stop()
        isListening = false
        vad.stopObserving()
        streamTask?.cancel()
        streamTask = nil
        guard let live = stream else { return }
        stream = nil
        live.finish()
        Task { await live.close() }
    }
}
