import Foundation
import Observation
import RunAnywhere
import os

#if canImport(UIKit)
import UIKit
typealias ComputerUseImage = UIImage
#else
import AppKit
typealias ComputerUseImage = NSImage
#endif

/// One computer-use step: render the profile's system prompt, run the VLM over
/// a screenshot, parse the reply into a viewport-scaled action.
///
/// Everything model-specific belongs to `RunAnywhere.CUA` — the prompt, the
/// tool schema, and the coordinate convention. The scaffold is stateless, so
/// owning the agent loop is the app's job; this runs exactly one turn.
@Observable
@MainActor
final class ComputerUseViewModel {
    var screenshot: ComputerUseImage?
    var goal = ""

    private(set) var loadedModelID: String?
    private(set) var loadedModelName: String?
    /// The loaded model's declared CUA profile, empty when it is an ordinary
    /// vision model. Driven off the catalog rather than assumed: other
    /// multimodal models emit the same `<tool_call>` shape in absolute pixels,
    /// and running one through a profile rescales it into a confident lie.
    private(set) var profile: String?
    private(set) var isLoadingModel = false

    private(set) var isRunning = false
    private(set) var rawOutput = ""
    private(set) var action: CuaAction?
    private(set) var status: String?
    private(set) var lastError: String?

    @ObservationIgnored private var runTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.runanywhere.RunAnywhereAI", category: "ComputerUse")

    private static let maxOutputTokens = 256

    var canRun: Bool { screenshot != nil && profile != nil && !isRunning }

    /// Registry entries that declare a computer-use profile.
    static func agents(in store: ModelStore) -> [ModelInfo] {
        store.raw.filter { !$0.cuaProfile.isEmpty }
    }

    func refreshLoadedModel(store: ModelStore) async {
        let state = await RunAnywhere.models.state()
        let residentID = (state.loaded[.multimodal] ?? state.loaded[.vision])?.id
        guard let residentID,
              let info = store.raw.first(where: { $0.id == residentID }) else {
            loadedModelID = nil
            loadedModelName = nil
            profile = nil
            return
        }
        loadedModelID = info.id
        loadedModelName = info.name.isEmpty ? info.id : info.name
        profile = info.cuaProfile.isEmpty ? nil : info.cuaProfile
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
        clearResult()
    }

    func run() {
        guard !isRunning, let screenshot, let profile else { return }

        let task = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !task.isEmpty else {
            lastError = "Say what the agent should do."
            return
        }
        guard let systemPrompt = RunAnywhere.CUA.systemPrompt(profile: profile) else {
            lastError = "The SDK has no computer-use prompt for the profile \(profile)."
            return
        }
        guard let image = Self.imageInput(from: screenshot) else {
            lastError = "That screenshot could not be encoded for the model."
            return
        }

        let viewport = Self.pixelSize(of: screenshot)
        clearResult()
        isRunning = true

        runTask = Task { [weak self] in
            guard let self else { return }
            do {
                // Temperature 0: the screen parses a strict `<tool_call>` JSON
                // schema and reports anything else as "the model replied
                // without a tool call". The SDK default of 0.7 samples against
                // that for no benefit; every other structured call site here
                // pins sampling the same way.
                let options = LlmOptions(
                    maxOutputTokens: Self.maxOutputTokens,
                    temperature: 0,
                    systemPrompt: systemPrompt
                )
                let stream = try await RunAnywhere.vlm.generateStream(
                    image: image,
                    prompt: task,
                    options: options
                )
                for try await event in stream {
                    if Task.isCancelled { break }
                    switch event {
                    case .textDelta(_, _, _, _, let text):
                        rawOutput += text
                    case .failed(_, _, let error):
                        throw error
                    default:
                        break
                    }
                }
                if Task.isCancelled {
                    status = "Stopped."
                } else {
                    parse(profile: profile, viewport: viewport)
                }
            } catch is CancellationError {
                status = "Stopped."
            } catch {
                logger.error("step failed: \(error, privacy: .public)")
                lastError = error.localizedDescription
            }
            isRunning = false
            runTask = nil
        }
    }

    /// Cancelling the consuming task is the cancellation path: the VLM stream
    /// tears the native generation down from its own termination handler.
    func cancel() {
        runTask?.cancel()
    }

    func clearResult() {
        rawOutput = ""
        action = nil
        status = nil
        lastError = nil
    }

    func report(_ error: Error) {
        logger.error("screenshot import failed: \(error, privacy: .public)")
        lastError = error.localizedDescription
    }

    private func parse(profile: String, viewport: (width: Int, height: Int)) {
        guard let parsed = RunAnywhere.CUA.parseAction(
            rawOutput,
            profile: profile,
            viewport: viewport
        ) else {
            lastError = "The SDK does not recognise the profile \(profile)."
            return
        }
        action = parsed
        status = parsed.isValid ? nil : "The model replied without a tool call."
    }

    private static func imageInput(from image: ComputerUseImage) -> ImageInput? {
        #if canImport(UIKit)
        try? ImageInput.uiImage(image)
        #else
        try? ImageInput.nsImage(image)
        #endif
    }

    /// Pixel dimensions of the screenshot — the viewport the SDK scales into.
    static func pixelSize(of image: ComputerUseImage) -> (width: Int, height: Int) {
        #if canImport(UIKit)
        (Int(image.size.width * image.scale), Int(image.size.height * image.scale))
        #else
        let representation = image.representations.first
        return (
            representation?.pixelsWide ?? Int(image.size.width),
            representation?.pixelsHigh ?? Int(image.size.height)
        )
        #endif
    }
}

extension CuaAction.Kind {
    /// Plain-language name for the action, for a reader who has not read the
    /// tool schema.
    var title: String {
        switch self {
        case .unknown: "Unknown"
        case .leftClick: "Click"
        case .rightClick: "Right click"
        case .doubleClick: "Double click"
        case .tripleClick: "Triple click"
        case .mouseMove: "Move pointer"
        case .leftClickDrag: "Drag"
        case .type: "Type"
        case .key: "Press key"
        case .scroll: "Scroll"
        case .hscroll: "Scroll sideways"
        case .visitURL: "Open URL"
        case .historyBack: "Go back"
        case .webSearch: "Search the web"
        case .readPageAnswer: "Read the page"
        case .pauseMemorize: "Remember"
        case .askUser: "Ask the user"
        case .wait: "Wait"
        case .terminate: "Finish"
        }
    }

    var symbol: String {
        switch self {
        case .leftClick, .rightClick, .doubleClick, .tripleClick: "cursorarrow.click"
        case .mouseMove: "cursorarrow"
        case .leftClickDrag: "hand.draw"
        case .type, .key: "keyboard"
        case .scroll, .hscroll: "arrow.up.and.down.text.horizontal"
        case .visitURL, .historyBack, .webSearch: "safari"
        case .readPageAnswer: "text.magnifyingglass"
        case .pauseMemorize: "brain"
        case .askUser: "questionmark.bubble"
        case .wait: "hourglass"
        case .terminate: "checkmark.circle"
        case .unknown: "questionmark"
        }
    }

    /// What the action's `text` argument means, so the detail card can label it.
    var textLabel: String? {
        switch self {
        case .type: "Text"
        case .key: "Keys"
        case .visitURL: "URL"
        case .webSearch: "Query"
        case .terminate: "Answer"
        case .askUser, .readPageAnswer: "Question"
        case .pauseMemorize: "Fact"
        default: nil
        }
    }
}
