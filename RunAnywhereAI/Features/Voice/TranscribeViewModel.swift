import Foundation
import Observation
import RunAnywhere
import os

enum TranscribeMode: String, CaseIterable, Identifiable {
    case batch
    case live

    var id: String { rawValue }

    var title: String {
        switch self {
        case .batch: "Record"
        case .live: "Live"
        }
    }

    var detail: String {
        switch self {
        case .batch: "Record first, transcribe when you stop. Best accuracy."
        case .live: "Words appear as you speak, corrected as the engine hears more."
        }
    }
}

/// Why the transcript is empty once a run has finished.
///
/// Three facts, not one flag. A recording nobody made, a recording the engine
/// listened to and heard no words in, and a stream that never answered at all
/// are different problems, and telling a reader their microphone is broken when
/// the engine simply stayed silent sends them to hardware that works.
enum TranscribeOutcome: Equatable {
    case nothingRecorded
    case recognisedNothing
    case engineSilent

    var message: String {
        switch self {
        case .nothingRecorded: "Nothing recorded yet."
        case .recognisedNothing: "That recording came back with no words in it."
        case .engineSilent: "The speech model never answered. Try loading it again."
        }
    }
}

@Observable
@MainActor
final class TranscribeViewModel {
    let stt = VoiceModelSlot(.speech)
    let levels = AudioLevelTrack()

    var mode: TranscribeMode = .batch {
        didSet {
            guard oldValue != mode else { return }
            // The previous mode's result must not survive under the new mode's
            // description; one mode's output read as another's is worse than
            // an empty pane.
            text = ""
            partial = ""
            outcome = .nothingRecorded
            lastError = nil
        }
    }

    private(set) var text = ""
    private(set) var partial = ""
    private(set) var isRecording = false
    private(set) var isTranscribing = false
    private(set) var isPreparing = false
    private(set) var recordedSeconds: Double = 0
    private(set) var outcome: TranscribeOutcome = .nothingRecorded
    private(set) var lastError: String?

    private static let sampleRate = 16_000

    private let capture = AudioCaptureManager()
    private let defaults = DefaultModels()
    private let logger = Logger(subsystem: "com.runanywhere.RunAnywhereAI", category: "Transcribe")

    private var buffer = Data()
    private var live: SttStream?
    private var liveTask: Task<Void, Never>?
    private var committed = ""
    private var eventsSeen = 0

    var isBusy: Bool { isPreparing || isTranscribing }
    var hasResult: Bool { !text.isEmpty || !partial.isEmpty }

    var displayText: String {
        guard !partial.isEmpty else { return text }
        return text.isEmpty ? partial : text + "\n" + partial
    }

    func prepare(store: ModelStore) async {
        stt.observe(store: store)
        await stt.adopt(store: store, preferred: defaults.sttID)
    }

    func choose(_ model: InstalledModel) {
        stt.select(model)
        defaults.sttID = model.id
    }

    func clear() {
        text = ""
        partial = ""
        committed = ""
        outcome = .nothingRecorded
        recordedSeconds = 0
        lastError = nil
    }

    func toggleRecording() async {
        if isRecording {
            await stop()
        } else {
            await start()
        }
    }

    // MARK: - Recording

    private func start() async {
        guard !isRecording, !isBusy else { return }
        lastError = nil
        buffer = Data()
        text = ""
        partial = ""
        committed = ""
        eventsSeen = 0
        recordedSeconds = 0
        outcome = .nothingRecorded

        isPreparing = true
        let ready = await stt.ensureLoaded()
        isPreparing = false
        guard ready else {
            lastError = stt.lastError ?? "No speech-to-text model is loaded."
            return
        }

        guard await capture.requestPermission() else {
            lastError = "Microphone access was declined."
            return
        }

        if mode == .live, !(await openLiveStream()) { return }

        do {
            // Yielded straight through on the main actor. Hopping a task per
            // chunk reorders the audio, and a recogniser fed out-of-order
            // frames returns nothing at all.
            try await capture.startRecording { [weak self] data in
                MainActor.assumeIsolated { self?.accept(data) }
            }
        } catch {
            logger.error("microphone failed: \(error, privacy: .public)")
            lastError = "The microphone could not start: \(error.localizedDescription)"
            await closeLiveStream()
            return
        }

        isRecording = true
        levels.start(sampling: { [capture] in capture.audioLevel })
    }

    private func stop() async {
        guard isRecording else { return }
        capture.stopRecording()
        levels.stop()
        isRecording = false

        switch mode {
        case .live:
            await finishLiveStream()
        case .batch:
            await transcribeBuffer()
        }
    }

    private func accept(_ data: Data) {
        recordedSeconds += Double(data.count / 2) / Double(Self.sampleRate)
        switch mode {
        case .batch:
            buffer.append(data)
        case .live:
            live?.pushFrame(AudioFrame(samples: data, sampleCount: data.count / 2))
        }
    }

    // MARK: - Batch

    private func transcribeBuffer() async {
        guard !buffer.isEmpty else {
            outcome = .nothingRecorded
            return
        }
        isTranscribing = true
        defer { isTranscribing = false }

        do {
            let result = try await RunAnywhere.stt.transcribe(
                .pcm16(buffer, sampleRate: Self.sampleRate)
            )
            text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { outcome = .recognisedNothing }
        } catch {
            logger.error("transcription failed: \(error, privacy: .public)")
            lastError = "Transcription failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Live

    private func openLiveStream() async -> Bool {
        do {
            let stream = try await RunAnywhere.stt.openStream(
                format: AudioFormatSpec(encoding: .pcmS16Le, sampleRate: Self.sampleRate)
            )
            live = stream
            liveTask = Task { [weak self] in
                do {
                    for try await event in stream.events {
                        guard let self, !Task.isCancelled else { return }
                        await MainActor.run { self.apply(event) }
                    }
                } catch {
                    guard let self else { return }
                    await MainActor.run {
                        self.logger.error("live transcription failed: \(error, privacy: .public)")
                        self.lastError = "Live transcription stopped: \(error.localizedDescription)"
                    }
                }
            }
            return true
        } catch {
            logger.error("could not open transcription: \(error, privacy: .public)")
            lastError = "Live transcription could not start: \(error.localizedDescription)"
            return false
        }
    }

    /// Close the stream and wait for the tail.
    ///
    /// The native session flushes on finish, so the last utterance's final
    /// arrives after capture has already stopped; returning before the drain
    /// would drop it.
    private func finishLiveStream() async {
        guard let stream = live else { return }
        isTranscribing = true
        stream.finish()
        await liveTask?.value
        liveTask = nil
        live = nil
        await stream.close()
        isTranscribing = false

        text = committed
        partial = ""
        if text.isEmpty, lastError == nil {
            outcome = eventsSeen == 0 ? .engineSilent : .recognisedNothing
        }
    }

    private func closeLiveStream() async {
        liveTask?.cancel()
        liveTask = nil
        guard let stream = live else { return }
        live = nil
        stream.finish()
        await stream.close()
    }

    private func apply(_ event: TranscriptionEvent) {
        switch event {
        case let .partial(_, _, _, _, alternatives):
            // Counted even when blank: the engine answered, and that is what
            // separates "heard nothing" from "never ran".
            eventsSeen += 1
            partial = (alternatives.first ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            text = committed

        case let .transcriptFinal(_, _, transcription):
            eventsSeen += 1
            let final = transcription.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !final.isEmpty {
                committed = committed.isEmpty ? final : committed + "\n" + final
            }
            partial = ""
            text = committed

        default:
            break
        }
    }

    // MARK: - Cleanup

    func teardown() {
        capture.stopRecording()
        levels.stop()
        isRecording = false
        stt.stopObserving()
        let closing = live
        live = nil
        liveTask?.cancel()
        liveTask = nil
        guard let closing else { return }
        closing.finish()
        Task { await closing.close() }
    }
}
