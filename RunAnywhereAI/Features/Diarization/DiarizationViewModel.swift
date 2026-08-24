#if os(iOS)
import Foundation
import Observation
import RunAnywhere
import os

/// One speaker turn as the list shows it. The SDK reports a speaker id; the UI
/// additionally needs a small stable index to pick a colour with.
struct SpeakerTurn: Identifiable, Hashable {
    let id = UUID()
    let speakerIndex: Int
    let speakerID: String
    let startMs: Int64
    let endMs: Int64

    var durationMs: Int64 { max(endMs - startMs, 0) }

    var range: String { "\(Self.stamp(startMs)) – \(Self.stamp(endMs))" }

    var durationLabel: String {
        String(format: "%.1fs", Double(durationMs) / 1000)
    }

    static func stamp(_ ms: Int64) -> String {
        let seconds = Double(ms) / 1000
        let minutes = Int(seconds) / 60
        return String(format: "%d:%05.2f", minutes, seconds - Double(minutes * 60))
    }

    /// Sorted by start time, each distinct speaker id given an index in order of
    /// first appearance so the colours stay stable down the list.
    static func from(_ segments: [SpeakerSegment]) -> [SpeakerTurn] {
        var indexBySpeaker: [String: Int] = [:]
        return segments
            .sorted { $0.startMs < $1.startMs }
            .map { segment in
                let index = indexBySpeaker[segment.speakerId] ?? indexBySpeaker.count
                indexBySpeaker[segment.speakerId] = index
                return SpeakerTurn(
                    speakerIndex: index,
                    speakerID: segment.speakerId,
                    startMs: segment.startMs,
                    endMs: segment.endMs
                )
            }
    }
}

@Observable
@MainActor
final class DiarizationViewModel {
    private(set) var loadedModelID: String?
    private(set) var loadedModelName: String?
    private(set) var isLoadingModel = false

    private(set) var isRecording = false
    private(set) var levels: [Float] = Array(
        repeating: DiarizationViewModel.floorLevel,
        count: DiarizationViewModel.meterBars
    )
    private(set) var elapsed: TimeInterval = 0

    private(set) var isDiarizing = false
    private(set) var turns: [SpeakerTurn] = []
    private(set) var speakerCount = 0
    private(set) var status: String?
    private(set) var lastError: String?

    @ObservationIgnored private let capture = AudioCaptureManager()
    @ObservationIgnored private var buffer = Data()
    @ObservationIgnored private var meterTask: Task<Void, Never>?
    @ObservationIgnored private var startedAt: Date?

    private let logger = Logger(subsystem: "com.runanywhere.RunAnywhereAI", category: "Diarization")

    private static let sampleRate = 16_000
    private static let bytesPerSecond = 32_000
    /// Two speakers need something to tell apart; under a couple of seconds the
    /// run comes back with one turn and reads as a bug.
    private static let minimumBytes = 64_000
    private static let floorLevel: Float = 0.04
    private static let meterBars = 48

    var isBusy: Bool { isLoadingModel || isDiarizing }
    var hasModel: Bool { loadedModelID != nil }

    var recordedSeconds: Double { Double(buffer.count) / Double(Self.bytesPerSecond) }

    /// Registry entries that can diarize.
    static func models(in store: ModelStore) -> [ModelInfo] {
        store.raw.filter { $0.category == .speakerDiarization }
    }

    func refreshLoadedModel(store: ModelStore) async {
        let state = await RunAnywhere.models.state()
        guard let resident = state.loaded[.speakerDiarization] else {
            loadedModelID = nil
            loadedModelName = nil
            return
        }
        loadedModelID = resident.id
        let catalogName = store.raw.first { $0.id == resident.id }?.name
        loadedModelName = [resident.name, catalogName, resident.id]
            .compactMap { $0 }
            .first { !$0.isEmpty }
    }

    func load(_ info: ModelInfo, store: ModelStore) async {
        guard !isLoadingModel else { return }
        isLoadingModel = true
        defer { isLoadingModel = false }

        lastError = nil
        do {
            try await store.load(info.id)
        } catch {
            logger.error("load failed for \(info.id, privacy: .public): \(error, privacy: .public)")
            lastError = error.localizedDescription
            return
        }
        await refreshLoadedModel(store: store)
    }

    func toggleRecording() async {
        if isRecording {
            await stopAndDiarize()
        } else {
            await startRecording()
        }
    }

    func discard() {
        guard isRecording else { return }
        capture.stopRecording()
        teardownMeter()
        buffer = Data()
        isRecording = false
        status = nil
    }

    /// Release the microphone when the screen goes away.
    func stop() {
        capture.stopRecording()
        teardownMeter()
        isRecording = false
    }

    private func startRecording() async {
        guard hasModel else {
            lastError = "Load a diarization model first."
            return
        }
        guard await capture.requestPermission() else {
            lastError = "Microphone access was declined. Turn it on in Settings to record a clip."
            return
        }

        lastError = nil
        status = nil
        turns = []
        speakerCount = 0
        buffer = Data()
        elapsed = 0
        levels = Array(repeating: Self.floorLevel, count: levels.count)

        do {
            try await capture.startRecording { [weak self] data in
                MainActor.assumeIsolated {
                    self?.buffer.append(data)
                }
            }
        } catch {
            logger.error("microphone failed: \(error, privacy: .public)")
            lastError = "The microphone could not start."
            return
        }

        isRecording = true
        startedAt = Date()
        startMeter()
    }

    private func stopAndDiarize() async {
        capture.stopRecording()
        teardownMeter()
        isRecording = false

        let audio = buffer
        buffer = Data()

        guard audio.count >= Self.minimumBytes else {
            status = nil
            lastError = "That clip is too short. Record a couple of seconds of two people talking."
            return
        }
        await diarize(audio)
    }

    private func diarize(_ audio: Data) async {
        isDiarizing = true
        defer { isDiarizing = false }

        lastError = nil
        status = "Working out who spoke when…"

        let started = Date()
        do {
            let result = try await RunAnywhere.diarization.diarize(
                .pcm16(audio, sampleRate: Self.sampleRate)
            )
            turns = SpeakerTurn.from(result.segments)
            speakerCount = result.speakerCount
            let millis = Int((Date().timeIntervalSince(started) * 1000).rounded())
            status = "\(result.speakerCount) \(result.speakerCount == 1 ? "speaker" : "speakers")"
                + " across \(turns.count) \(turns.count == 1 ? "turn" : "turns") in \(millis) ms"
        } catch {
            logger.error("diarization failed: \(error, privacy: .public)")
            lastError = error.localizedDescription
            status = nil
        }
    }

    private func startMeter() {
        meterTask?.cancel()
        meterTask = Task { [weak self] in
            while let self, !Task.isCancelled, isRecording {
                try? await Task.sleep(for: .milliseconds(90))
                guard !Task.isCancelled else { break }
                if let startedAt { elapsed = Date().timeIntervalSince(startedAt) }
                var next = levels
                next.removeFirst()
                next.append(min(max(capture.audioLevel, Self.floorLevel), 1))
                levels = next
            }
        }
    }

    private func teardownMeter() {
        meterTask?.cancel()
        meterTask = nil
        startedAt = nil
        elapsed = 0
        levels = Array(repeating: Self.floorLevel, count: levels.count)
    }
}
#endif
