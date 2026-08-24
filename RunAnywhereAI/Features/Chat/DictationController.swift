import Foundation
import Observation
import RunAnywhere
import os

@Observable
@MainActor
final class DictationController {
    private(set) var isListening = false
    private(set) var isPaused = false
    private(set) var partial = ""
    private(set) var levels: [Float] = Array(repeating: 0.04, count: 42)
    private(set) var elapsed: TimeInterval = 0
    var lastError: String?

    private var task: Task<Void, Never>?
    private var meterTask: Task<Void, Never>?
    private var continuation: AsyncStream<AudioInput>.Continuation?
    private var startedAt: Date?
    private var accepted = ""
    private var eventCount = 0
    private(set) var chunks = 0
    private(set) var eventsSeen = 0
    private(set) var bytes = 0
    private let capture = AudioCaptureManager()
    private let logger = Logger(subsystem: "com.runanywhere.RunAnywhereAI", category: "Dictation")

    func start(onFinal: @escaping (String) -> Void) {
        guard !isListening else { return }
        isListening = true
        isPaused = false
        partial = ""
        accepted = ""
        eventCount = 0
        chunks = 0
        eventsSeen = 0
        bytes = 0
        elapsed = 0
        startedAt = Date()
        levels = Array(repeating: 0.04, count: 42)
        startMeter()

        task = Task { [weak self] in
            guard let self else { return }

            guard await capture.requestPermission() else {
                lastError = "Microphone access was declined."
                teardown()
                return
            }

            let (audio, continuation) = AsyncStream<AudioInput>.makeStream()
            self.continuation = continuation

            // Open the transcription session BEFORE the microphone. Starting
            // capture first meant chunks piled into a stream nobody was reading
            // yet, and a failure to open the session left the mic running with
            // no consumer.
            let events: AsyncThrowingStream<TranscriptionEvent, Error>
            do {
                events = try await RunAnywhere.stt.transcribeStream(audio)
            } catch {
                logger.error("could not open transcription: \(error, privacy: .public)")
                lastError = "No speech-to-text model is loaded."
                continuation.finish()
                teardown()
                return
            }

            do {
                // Yielded synchronously on the main actor. Hopping through a new
                // Task per chunk reordered the audio, and a recogniser fed
                // out-of-order frames returns nothing at all.
                try await capture.startRecording { [weak self] data in
                    MainActor.assumeIsolated {
                        guard let self, !self.isPaused else { return }
                        self.chunks += 1
                        self.bytes += data.count
                        continuation.yield(.pcm16(data, sampleRate: 16_000))
                    }
                }
            } catch {
                logger.error("microphone failed: \(error, privacy: .public)")
                lastError = "The microphone could not start."
                continuation.finish()
                teardown()
                return
            }

            do {
                for try await event in events {
                    if Task.isCancelled { break }
                    switch event {
                    case .partial(_, _, _, _, let alternatives):
                        eventCount += 1
                        eventsSeen += 1
                        if let first = alternatives.first, !first.isEmpty { partial = first }
                    case .transcriptFinal(_, _, let transcription):
                        eventCount += 1
                        eventsSeen += 1
                        let text = transcription.text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !text.isEmpty {
                            accepted = accepted.isEmpty ? text : accepted + " " + text
                        }
                        partial = ""
                    default:
                        continue
                    }
                }
            } catch {
                logger.error("transcription failed: \(error, privacy: .public)")
                lastError = "Transcription stopped: \(error.localizedDescription)"
            }

            if eventCount == 0, lastError == nil {
                lastError = "The speech model produced no result. Check that a speech-to-text model is loaded."
            }

            let result = [accepted, partial]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !result.isEmpty { onFinal(result) }
            teardown()
        }
    }

    func togglePause() {
        guard isListening else { return }
        isPaused.toggle()
    }

    /// Stop and keep what was heard.
    ///
    /// Order matters: the microphone stops first, then the audio stream closes.
    /// Closing the stream first drops the tail of the utterance and the native
    /// session flushes with nothing to emit, so no final ever arrives.
    func finish() {
        guard isListening else { return }
        capture.stopRecording()
        continuation?.finish()
        continuation = nil
    }

    /// Stop and throw it away.
    func discard() {
        accepted = ""
        partial = ""
        capture.stopRecording()
        continuation?.finish()
        continuation = nil
        task?.cancel()
        teardown()
    }

    private func startMeter() {
        meterTask?.cancel()
        meterTask = Task { [weak self] in
            while let self, !Task.isCancelled, isListening {
                try? await Task.sleep(for: .milliseconds(90))
                guard !Task.isCancelled else { break }
                if let startedAt { elapsed = Date().timeIntervalSince(startedAt) }
                guard !isPaused else { continue }
                var next = levels
                next.removeFirst()
                next.append(min(max(capture.audioLevel, 0.04), 1))
                levels = next
            }
        }
    }

    private func teardown() {
        meterTask?.cancel()
        meterTask = nil
        continuation = nil
        task = nil
        startedAt = nil
        isListening = false
        isPaused = false
        partial = ""
        elapsed = 0
    }
}
