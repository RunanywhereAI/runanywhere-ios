#if os(macOS)
import Combine
import Foundation
import Observation
import RunAnywhere
import os

@Observable
@MainActor
final class ConnectHostModel {
    struct Entry: Identifiable {
        enum Tone {
            case neutral
            case good
            case bad
        }

        let id = UUID()
        let at: Date
        let text: String
        let tone: Tone
    }

    /// Shared because hosting has to outlive its management screen: the More
    /// hub tears a destination's view down when the reader navigates away, and
    /// a host that stopped advertising the moment they looked elsewhere would
    /// drop every attached device.
    static let shared = ConnectHostModel()

    private(set) var status: ConnectSessionStatus = .idle
    private(set) var clientCount = 0
    private(set) var hostedModel: ConnectModel?
    private(set) var isStarting = false
    private(set) var lastError: String?
    private(set) var entries: [Entry] = []
    private(set) var startedAt: Date?

    var selectedModelID: String?

    @ObservationIgnored private let session = ConnectSession()
    @ObservationIgnored private var subscriptions = Set<AnyCancellable>()
    private let logger = Logger(subsystem: "com.runanywhere.RunAnywhereAI", category: "Connect")

    private static let maxEntries = 40

    var isHosting: Bool { status == .hosting }

    var hostName: String { ProcessInfo.processInfo.hostName }

    private init() {
        session.objectWillChange
            // The publisher fires before the change lands, so the values are
            // read back one main-queue turn later, once they have settled.
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.adopt() }
            }
            .store(in: &subscriptions)

        RunAnywhere.eventBus.modelLifecycle
            .receive(on: DispatchQueue.main)
            .sink { [weak self] change in
                MainActor.assumeIsolated { self?.handle(change) }
            }
            .store(in: &subscriptions)
    }

    /// Installed language models, the only thing a host can advertise.
    static func candidates(in store: ModelStore) -> [InstalledModel] {
        store.installed.filter { $0.purpose == .language }
    }

    func start(_ model: InstalledModel, store: ModelStore) async {
        guard !isStarting, !isHosting else { return }
        isStarting = true
        defer { isStarting = false }

        lastError = nil
        do {
            // Advertise only what is actually resident: a model picked from the
            // catalog may not be the one in memory, and a client that joined
            // would reach a host that cannot answer.
            if store.loadedLanguageModel?.id != model.id {
                note("Loading \(model.name)…", tone: .neutral)
                try await store.load(model.id)
            }

            let descriptor = ConnectModel(
                id: model.id,
                displayName: model.name,
                framework: model.backend,
                contextWindow: model.contextLength > 0 ? UInt32(model.contextLength) : 0,
                supportsStreaming: true
            )

            try await session.startHosting(model: descriptor) { request in
                // The only public producer of the proto stream `ConnectSession`
                // asks for. `llm.generateStream` returns the app-level event
                // enum, which this handler cannot accept.
                try await RunAnywhere.generateStream(request)
            }
            startedAt = Date()
            note("Hosting \(model.name) as \(hostName)", tone: .good)
        } catch {
            logger.error("hosting failed: \(error, privacy: .public)")
            lastError = error.localizedDescription
            note(error.localizedDescription, tone: .bad)
        }
    }

    func stop() {
        guard isHosting else { return }
        session.stopHosting()
        startedAt = nil
        note("Stopped hosting", tone: .neutral)
    }

    func clearLog() {
        entries = []
    }

    private func adopt() {
        let previousClients = clientCount

        status = session.status
        clientCount = session.activeClientCount
        hostedModel = session.activeModel

        if clientCount > previousClients {
            let joined = clientCount - previousClients
            note("\(joined) \(joined == 1 ? "device" : "devices") connected", tone: .good)
        } else if clientCount < previousClients {
            let left = previousClients - clientCount
            note("\(left) \(left == 1 ? "device" : "devices") disconnected", tone: .neutral)
        }

        if let error = session.lastError, error != lastError {
            lastError = error
            note(error, tone: .bad)
        }

        if !isHosting { startedAt = nil }
    }

    /// A host whose advertised model was unloaded elsewhere in the app is
    /// advertising something it can no longer serve; stop rather than let a
    /// client discover that mid-request.
    private func handle(_ change: RAModelLifecycleChange) {
        guard change.kind == .unloaded,
              isHosting,
              let hosted = hostedModel,
              change.modelID == hosted.id else {
            return
        }
        session.stopHosting()
        startedAt = nil
        lastError = "\(hosted.displayName) was unloaded, so hosting stopped."
        note(lastError ?? "", tone: .bad)
    }

    private func note(_ text: String, tone: Entry.Tone) {
        entries.insert(Entry(at: Date(), text: text, tone: tone), at: 0)
        if entries.count > Self.maxEntries {
            entries.removeLast(entries.count - Self.maxEntries)
        }
    }
}

extension ConnectSessionStatus {
    var title: String {
        switch self {
        case .idle: "Not hosting"
        case .discovering: "Looking for hosts"
        case .connecting: "Connecting"
        case .hosting: "Hosting"
        case .connected: "Connected"
        case .disconnected: "Disconnected"
        case .failed: "Failed"
        }
    }
}
#endif
