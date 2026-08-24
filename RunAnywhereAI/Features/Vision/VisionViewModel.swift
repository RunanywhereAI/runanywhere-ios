import AVFoundation
import Combine
import CoreMedia
import CoreVideo
import Foundation
import Observation
import RunAnywhere
import SwiftUI
import os

#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

/// Why the viewfinder is, or is not, showing a camera.
///
/// One value rather than a Bool: "you declined", "policy declined for you" and
/// "there is no camera here" each need a different sentence and a different way
/// forward, and a Simulator has no camera to grant access to.
enum VisionCameraStatus: Equatable {
    case idle
    case requestingAccess
    case ready
    case denied
    case restricted
    case unavailable(String)
}

/// What the last — or current — question did. `silent` is kept apart from
/// `answered` because an empty answer pane cannot tell the reader which of the
/// two happened.
enum VisionRunStatus: Equatable {
    case idle
    case running
    case answered(outputTokens: Int, tokensPerSecond: Float)
    case silent
    case cancelled
    case failed(String)
}

/// A still standing in for the live camera as the subject of the next question.
struct VisionStill: Identifiable {
    let id = UUID()
    let filename: String
    let input: ImageInput
    let preview: Image
}

struct VisionFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

@Observable
@MainActor
final class VisionViewModel: NSObject {
    static let defaultPrompt = "Describe what you see in this image."
    static let liveInterval: TimeInterval = 2.5

    private(set) var modelState: ModelState = .none
    private(set) var loadedModelID: String?
    private(set) var isModelReady = false

    var prompt = VisionViewModel.defaultPrompt
    private(set) var still: VisionStill?

    private(set) var answer = ""
    private(set) var status: VisionRunStatus = .idle
    private(set) var isAsking = false
    var isLive = false

    /// Why an attachment was refused, kept apart from `status`: a rejected file
    /// says nothing about what the model last did, and folding the two together
    /// would have "too large" wipe a perfectly good answer.
    var notice: String?

    private(set) var cameraStatus: VisionCameraStatus = .idle
    private(set) var captureSession: AVCaptureSession?

    /// Flipped once per session rather than per frame: the view needs to know
    /// whether there is anything to ask about, and observing the buffer itself
    /// would redraw the screen at frame rate.
    private(set) var hasFrame = false

    private var frame: CVPixelBuffer?
    private let frameQueue = DispatchQueue(label: "com.runanywhere.vision.camera")
    private var isStartingCamera = false

    private var installed: [InstalledModel] = []
    private var lifecycle: AnyCancellable?
    private var run: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.runanywhere.RunAnywhereAI", category: "Vision")

    private static let askTokens = 192
    private static let liveTokens = 64

    var hasSubject: Bool { still != nil || hasFrame }

    var canAsk: Bool { isModelReady && !isAsking && hasSubject }

    /// The interval as a sentence, so the copy and the loop driving it cannot
    /// drift apart: `Int(2.5)` promises two seconds and delivers two and a half.
    static var liveIntervalLabel: String {
        liveInterval == liveInterval.rounded()
            ? "\(Int(liveInterval))s"
            : String(format: "%.1fs", liveInterval)
    }

    // MARK: - Lifecycle

    func start(store: ModelStore) async {
        installed = store.installed
        if lifecycle == nil { observeLifecycle() }
        await adoptLoadedModel()
        await startCameraIfPossible()
    }

    func leave() {
        isLive = false
        run?.cancel()
        run = nil
        stopCamera()
    }

    private func observeLifecycle() {
        lifecycle = RunAnywhere.eventBus.events(for: .component)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                Task { @MainActor in self?.apply(event.componentLifecycle) }
            }
    }

    private func apply(_ event: RAComponentLifecycleEvent) {
        guard event.component == .vlm else { return }
        switch event.currentState {
        case .ready:
            isModelReady = true
            guard event.modelID != loadedModelID else { return }
            loadedModelID = event.modelID
            modelState = describe(id: event.modelID)
        case .notLoaded, .unloading, .shutdown, .deleting:
            isModelReady = false
            loadedModelID = nil
            modelState = .none
            isLive = false
            stopCamera()
        default:
            break
        }
    }

    // MARK: - Model

    private func adoptLoadedModel() async {
        let state = await RunAnywhere.models.state()
        // Both slots, matching how `RunAnywhere.vlm` itself resolves a model:
        // `.multimodal` first, `.vision` as the fallback.
        guard let loaded = state.loaded[.multimodal] ?? state.loaded[.vision] else {
            isModelReady = false
            loadedModelID = nil
            modelState = .none
            return
        }
        isModelReady = true
        loadedModelID = loaded.id
        modelState = describe(id: loaded.id)
    }

    func load(_ model: InstalledModel, store: ModelStore) async {
        installed = store.installed
        notice = nil
        modelState = .loading(model.name, 0.1)
        do {
            try await store.load(model.id)
            isModelReady = true
            loadedModelID = model.id
            modelState = .loaded(model.name, model.backend)
            await startCameraIfPossible()
        } catch {
            isModelReady = false
            loadedModelID = nil
            modelState = .none
            notice = "\(model.name) would not load: \(error.localizedDescription)"
            logger.error("vision model load failed: \(error, privacy: .public)")
        }
    }

    private func describe(id: String) -> ModelState {
        guard let known = installed.first(where: { $0.id == id }) else {
            return .loaded(id, "Local")
        }
        return .loaded(known.name, known.backend)
    }

    // MARK: - Camera

    /// iOS prefers the rear wide-angle camera; a Mac has no device at `.back`,
    /// so asking for one there returns nil and leaves Live permanently stuck.
    private static func device() -> AVCaptureDevice? {
        #if os(macOS)
        AVCaptureDevice.default(for: .video)
        #else
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(for: .video)
        #endif
    }

    private static var noDeviceMessage: String {
        #if targetEnvironment(simulator)
        "The Simulator has no camera. Choose an image instead, or run on a device."
        #elseif os(macOS)
        "No camera is connected to this Mac. Attach one, or choose an image instead."
        #else
        "No camera is available on this device. Choose an image instead."
        #endif
    }

    /// Idempotent: the screen calls this on appear, after a model loads, and
    /// after a still is cleared.
    func startCameraIfPossible() async {
        // Nothing touches the camera until a model can use it — otherwise the
        // privacy indicator runs behind a screen asking the reader to pick a
        // model, and the permission prompt arrives before anything asked for it.
        guard isModelReady, still == nil else { return }
        // A second caller joins rather than races: `authorizeCamera` suspends on
        // the system prompt, and two sessions would leave the loser running.
        guard !isStartingCamera else { return }

        if captureSession == nil {
            isStartingCamera = true
            defer { isStartingCamera = false }
            guard await authorizeCamera(), configureSession() else { return }
        }
        startSession()
    }

    func retryCamera() async {
        // Stop before dropping the reference: releasing a running session does
        // not stop it, and the next `configureSession` then fails at
        // `canAddInput` and blames another app for our own leak.
        stopCamera()
        captureSession = nil
        cameraStatus = .idle
        await startCameraIfPossible()
    }

    private func authorizeCamera() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            cameraStatus = .requestingAccess
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if !granted { cameraStatus = .denied }
            return granted
        case .denied:
            cameraStatus = .denied
            return false
        case .restricted:
            cameraStatus = .restricted
            return false
        @unknown default:
            cameraStatus = .unavailable("This device would not report its camera permission.")
            return false
        }
    }

    private func configureSession() -> Bool {
        guard let device = Self.device() else {
            cameraStatus = .unavailable(Self.noDeviceMessage)
            return false
        }

        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            cameraStatus = .unavailable(error.localizedDescription)
            return false
        }

        let session = AVCaptureSession()
        session.sessionPreset = .medium

        guard session.canAddInput(input) else {
            cameraStatus = .unavailable("\(device.localizedName) is in use by another app.")
            return false
        }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        // BGRA rather than the default YUV: `ImageInput.pixelBuffer` has a
        // direct byte path for it and skips a colour conversion per frame.
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        output.setSampleBufferDelegate(self, queue: frameQueue)
        output.alwaysDiscardsLateVideoFrames = true

        guard session.canAddOutput(output) else {
            cameraStatus = .unavailable("\(device.localizedName) cannot deliver video frames.")
            return false
        }
        session.addOutput(output)

        #if os(iOS)
        // Rotate the frames the way the preview layer already rotates itself.
        // The preview defaults to portrait while a data output hands back the
        // sensor's landscape buffer, so the reader sees an upright scene and the
        // model is asked about a picture lying on its side.
        if let connection = output.connection(with: .video),
           connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        #endif

        captureSession = session
        cameraStatus = .ready
        return true
    }

    private func startSession() {
        guard let session = captureSession, !session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
    }

    func stopCamera() {
        hasFrame = false
        frame = nil
        guard let session = captureSession, session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { session.stopRunning() }
    }

    fileprivate func receive(_ buffer: CVPixelBuffer) {
        frame = buffer
        if !hasFrame { hasFrame = true }
    }

    // MARK: - Stills

    func use(_ attachment: ChatAttachment) {
        do {
            guard let data = attachment.imageData, let preview = Self.preview(from: data) else {
                throw VisionFailure(message: "\(attachment.filename) could not be displayed.")
            }
            let input = try attachment.modelImage()
            // A still and a feed are two subjects; Live would otherwise keep
            // re-describing a photograph that never changes.
            isLive = false
            cancel()
            // And the camera stops: nothing is showing its preview any more, so
            // a running session only drains the battery and holds the platform's
            // camera indicator lit over a screen displaying a photo.
            stopCamera()
            still = VisionStill(filename: attachment.filename, input: input, preview: preview)
            answer = ""
            status = .idle
            notice = nil
        } catch {
            notice = error.localizedDescription
        }
    }

    func clearStill() async {
        still = nil
        answer = ""
        status = .idle
        await startCameraIfPossible()
    }

    private static func preview(from data: Data) -> Image? {
        #if canImport(UIKit)
        UIImage(data: data).map(Image.init(uiImage:))
        #elseif canImport(AppKit)
        NSImage(data: data).map(Image.init(nsImage:))
        #else
        nil
        #endif
    }

    // MARK: - Asking

    func ask() {
        guard !isAsking else { return }
        // `isAsking` is raised inside the task body, which does not start
        // synchronously, so two taps in one turn of the run loop both clear the
        // guard above and the second would orphan the first.
        run?.cancel()
        run = Task { [weak self] in
            await self?.perform(maxTokens: Self.askTokens, keepPreviousUntilFirstToken: false)
        }
    }

    /// Stops the run in flight, and turns Live off with it: a Stop that left
    /// Live armed would fire again seconds later and appear to have cancelled
    /// nothing.
    func cancel() {
        isLive = false
        run?.cancel()
        run = nil
    }

    /// Driven by the view's `.task(id:)`. Each turn is awaited structurally, so
    /// cancelling that view task — turning Live off, leaving the screen — tears
    /// the native stream down with it.
    func runLiveLoop() async {
        while !Task.isCancelled {
            // Skip a turn that can only fail rather than posting "there is
            // nothing to look at" every couple of seconds as if the model broke.
            if hasSubject {
                await perform(maxTokens: Self.liveTokens, keepPreviousUntilFirstToken: true)
            }
            if Task.isCancelled { return }
            try? await Task.sleep(nanoseconds: UInt64(Self.liveInterval * 1_000_000_000))
        }
    }

    private func subject() throws -> ImageInput {
        if let still { return still.input }
        guard let frame else {
            throw VisionFailure(
                message: cameraStatus == .ready
                    ? "The camera has not delivered a frame yet. Give it a moment."
                    : "There is nothing to look at yet. Start the camera, or choose an image."
            )
        }
        return try ImageInput.pixelBuffer(frame)
    }

    private var question: String {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Self.defaultPrompt : trimmed
    }

    /// `keepPreviousUntilFirstToken` is what Live wants: blanking the pane
    /// between captures makes it strobe.
    private func perform(maxTokens: Int, keepPreviousUntilFirstToken: Bool) async {
        isAsking = true
        status = .running
        if !keepPreviousUntilFirstToken { answer = "" }
        defer { isAsking = false }

        do {
            let image = try subject()
            var options = LlmOptions()
            options.maxOutputTokens = maxTokens
            let stream = try await RunAnywhere.vlm.generateStream(
                image: image,
                prompt: question,
                options: options
            )

            var isFirstToken = true
            var sawTerminal = false
            for try await event in stream {
                sawTerminal = fold(
                    event,
                    isFirstToken: &isFirstToken,
                    clearOnFirstToken: keepPreviousUntilFirstToken
                ) || sawTerminal
            }
            if !sawTerminal { status = endedWithoutTerminalEvent() }
        } catch is CancellationError {
            status = .cancelled
        } catch {
            status = .failed(error.localizedDescription)
            logger.error("vision run failed: \(error, privacy: .public)")
        }
    }

    /// Returns true when the event said how the run ended, rather than the
    /// stream merely stopping.
    private func fold(
        _ event: GenerationEvent,
        isFirstToken: inout Bool,
        clearOnFirstToken: Bool
    ) -> Bool {
        switch event {
        case .textDelta(_, _, _, _, let text):
            guard !text.isEmpty else { return false }
            if isFirstToken {
                isFirstToken = false
                if clearOnFirstToken { answer = "" }
            }
            answer += text
            return false

        case .completed(_, let result):
            if answer.isEmpty, !result.text.isEmpty { answer = result.text }
            status = answer.isEmpty
                ? .silent
                : .answered(outputTokens: result.outputTokens, tokensPerSecond: result.tokensPerSecond)
            return true

        case .failed(_, let partial, let error):
            // `vlm.generateStream` reports failure as an event rather than by
            // throwing, so without this a run that died mid-answer looks exactly
            // like one that finished early.
            if let partial, answer.isEmpty { answer = partial }
            status = .failed(error.localizedDescription)
            logger.error("vision run failed: \(error, privacy: .public)")
            return true

        case .cancelled:
            status = .cancelled
            return true

        default:
            return false
        }
    }

    private func endedWithoutTerminalEvent() -> VisionRunStatus {
        if Task.isCancelled { return .cancelled }
        if answer.isEmpty { return .silent }
        return .answered(outputTokens: 0, tokensPerSecond: 0)
    }
}

extension VisionViewModel: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        Task { @MainActor in self.receive(buffer) }
    }
}
