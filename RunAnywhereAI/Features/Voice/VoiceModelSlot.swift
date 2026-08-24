import Combine
import Foundation
import Observation
import RunAnywhere
import os

/// A model slot a voice screen fills.
///
/// Narrower than `ModelPurpose` on purpose: every case here maps onto exactly
/// one SDK component and one model category, so the mapping below is total and
/// no screen can ask for a slot the SDK has no home for.
enum VoiceSlot: CaseIterable {
    case speech
    case language
    case voice
    case activity

    var purpose: ModelPurpose {
        switch self {
        case .speech: .speechToText
        case .language: .language
        case .voice: .textToSpeech
        case .activity: .voiceActivity
        }
    }

    var category: ModelCategory {
        switch self {
        case .speech: .speechRecognition
        case .language: .language
        case .voice: .speechSynthesis
        case .activity: .voiceActivityDetection
        }
    }

    var component: RASDKComponent {
        switch self {
        case .speech: .stt
        case .language: .llm
        case .voice: .tts
        case .activity: .vad
        }
    }

    var title: String {
        switch self {
        case .speech: "Speech"
        case .language: "Language"
        case .voice: "Voice"
        case .activity: "Detector"
        }
    }

    var detail: String {
        switch self {
        case .speech: "Turns what you say into text"
        case .language: "Writes the reply"
        case .voice: "Reads the reply out loud"
        case .activity: "Decides whether a frame is speech"
        }
    }

    var symbol: String { purpose.symbol }
}

/// One slot's model: which one is chosen, whether it is resident, and how to
/// make it so.
///
/// Composed rather than inherited. Every voice screen needs the same three
/// facts about each model it drives, and `@Observable` does not survive class
/// inheritance, so the screens own one of these per slot instead of deriving
/// from a shared base.
@Observable
@MainActor
final class VoiceModelSlot {
    let slot: VoiceSlot
    private(set) var model: InstalledModel?
    /// Whether the SDK has this exact model loaded for the slot's category.
    private(set) var isResident = false
    private(set) var isLoading = false
    private(set) var lastError: String?

    private weak var store: ModelStore?
    private var lifecycle: AnyCancellable?
    private let logger = Logger(subsystem: "com.runanywhere.RunAnywhereAI", category: "VoiceModels")

    init(_ slot: VoiceSlot) {
        self.slot = slot
    }

    var id: String? { model?.id }
    var name: String? { model?.name }

    func candidates(in store: ModelStore) -> [InstalledModel] {
        store.installed.filter { $0.purpose == slot.purpose }
    }

    /// Reflect what the SDK already has resident, then fall back to a
    /// remembered choice, then to the only candidate on the device.
    func adopt(store: ModelStore, preferred: String? = nil) async {
        self.store = store
        let installed = candidates(in: store)
        let state = await RunAnywhere.models.state()

        if let resident = state.loaded[slot.category]?.id,
           let match = installed.first(where: { $0.id == resident }) {
            model = match
            isResident = true
            return
        }

        isResident = false
        guard model == nil else { return }
        if let preferred, let match = installed.first(where: { $0.id == preferred }) {
            model = match
        } else if installed.count == 1 {
            model = installed[0]
        }
    }

    func select(_ candidate: InstalledModel) {
        guard candidate.id != model?.id else { return }
        model = candidate
        isResident = false
        lastError = nil
    }

    /// Make the chosen model resident, and report whether it really is.
    ///
    /// The residency check after the load is not belt and braces: a model can
    /// be evicted natively without the app hearing, and a load that returns
    /// without filling the slot is how a session opens against nothing.
    @discardableResult
    func ensureLoaded() async -> Bool {
        guard let model else {
            lastError = "Choose a \(slot.title.lowercased()) model first."
            return false
        }
        if isResident, await isCurrent(model.id) { return true }

        isLoading = true
        defer { isLoading = false }
        do {
            _ = try await RunAnywhere.models.load(id: model.id)
        } catch {
            logger.error("load failed for \(model.id, privacy: .public): \(error, privacy: .public)")
            lastError = "\(model.name) would not load: \(error.localizedDescription)"
            isResident = false
            return false
        }

        isResident = await isCurrent(model.id)
        if !isResident {
            lastError = "\(model.name) loaded but is not the active \(slot.title.lowercased()) model."
        }
        return isResident
    }

    /// Track loads and unloads made anywhere else in the app, so a slot never
    /// claims a model the SDK has already released.
    func observe(store: ModelStore) {
        self.store = store
        guard lifecycle == nil else { return }
        let component = slot.component
        lifecycle = RunAnywhere.eventBus.modelLifecycle
            .filter { $0.component == component }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] change in
                MainActor.assumeIsolated { self?.apply(change) }
            }
    }

    func stopObserving() {
        lifecycle = nil
    }

    private func apply(_ change: RAModelLifecycleChange) {
        switch change.kind {
        case .loaded:
            guard !change.modelID.isEmpty else { return }
            if let store, let match = candidates(in: store).first(where: { $0.id == change.modelID }) {
                model = match
            }
            isResident = change.modelID == model?.id
        case .unloaded:
            guard change.modelID.isEmpty || change.modelID == model?.id else { return }
            isResident = false
        }
    }

    private func isCurrent(_ id: String) async -> Bool {
        await RunAnywhere.models.state().loaded[slot.category]?.id == id
    }
}
