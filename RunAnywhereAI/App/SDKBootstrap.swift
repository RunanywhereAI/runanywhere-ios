import Foundation
import Observation
import RunAnywhere
import os
#if canImport(LlamaCPPRuntime)
import LlamaCPPRuntime
#endif
import MLXRuntime
#if canImport(NeuRTRuntime)
import NeuRTRuntime
#endif
#if canImport(ONNXRuntime)
import ONNXRuntime
#endif

@Observable
@MainActor
final class SDKBootstrap {
    enum Phase: Equatable {
        case idle
        case running(Double)
        case ready
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private let logger = Logger(subsystem: "com.runanywhere.RunAnywhereAI", category: "SDKBootstrap")
    private var isRunning = false

    var progress: Double {
        switch phase {
        case .idle: 0
        case .running(let value): value
        case .ready: 1
        case .failed: 0
        }
    }

    var isReady: Bool { phase == .ready }

    func start() async {
        guard !isRunning, !isReady else { return }
        isRunning = true
        defer { isRunning = false }

        phase = .running(0)

        let mlxRegistered = registerBackends()
        phase = .running(0.30)

        do {
            try initializeSDK()
        } catch {
            logger.error("SDK initialization failed: \(error, privacy: .public)")
            phase = .failed(String(describing: error))
            return
        }

        await AppTools.registerAll()
        phase = .running(0.45)

        await ModelCatalogBootstrap.registerAll(mlxRegistered: mlxRegistered)
        reportAppleFoundationAvailability()
        phase = .running(0.90)

        await RunAnywhere.models.refresh()
        phase = .running(1)
        phase = .ready
    }

    /// Read once at startup so "Apple's model does nothing" is answerable from
    /// the log alone, without reproducing it. The screens re-read it per
    /// catalog refresh rather than caching this, so turning Apple Intelligence
    /// on mid-session still takes effect.
    private func reportAppleFoundationAvailability() {
        if let reason = HardwareTierResolver().appleFoundationUnavailableReason {
            logger.info("Apple built-in model unavailable: \(reason, privacy: .public)")
        } else {
            logger.info("Apple built-in model is available")
        }
    }

    private func registerBackends() -> Bool {
        #if canImport(LlamaCPPRuntime)
        LlamaCPP.register(priority: 100)
        #endif
        let mlxRegistered = MLX.register(priority: 100)
        #if canImport(ONNXRuntime)
        ONNX.register(priority: 100)
        #endif
        #if canImport(NeuRTRuntime)
        NeuRT.register(priority: 100)
        #endif
        return mlxRegistered
    }

    private func initializeSDK() throws {
        if let credentials = bundledCredentials() {
            try RunAnywhere.initialize(
                apiKey: credentials.apiKey,
                baseUrl: credentials.baseURL,
                environment: .production
            )
        } else {
            #if DEBUG
            try RunAnywhere.initialize(environment: .development)
            #else
            fatalError("Release builds require RUNANYWHERE_API_KEY and RUNANYWHERE_BASE_URL")
            #endif
        }
    }

    private func bundledCredentials() -> (apiKey: String, baseURL: String)? {
        if let url = Bundle.main.url(forResource: "RunAnywhereLocalSecrets", withExtension: "plist"),
           let data = try? Data(contentsOf: url),
           let object = try? PropertyListSerialization.propertyList(from: data, format: nil),
           let dictionary = object as? [String: String],
           let apiKey = usable(dictionary["apiKey"]),
           let baseURL = usable(dictionary["baseURL"]),
           isHTTPURL(baseURL) {
            return (apiKey, baseURL)
        }

        guard let apiKey = usable(Bundle.main.object(forInfoDictionaryKey: "RUNANYWHERE_API_KEY") as? String),
              let baseURL = usable(Bundle.main.object(forInfoDictionaryKey: "RUNANYWHERE_BASE_URL") as? String),
              isHTTPURL(baseURL) else {
            return nil
        }
        return (apiKey, baseURL)
    }

    private func usable(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty,
              trimmed.range(of: "YOUR_|<your|REPLACE_ME|PLACEHOLDER|\\$\\(", options: [.regularExpression, .caseInsensitive]) == nil else {
            return nil
        }
        return trimmed
    }

    private func isHTTPURL(_ value: String) -> Bool {
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = url.host, !host.isEmpty else {
            return false
        }
        return true
    }
}
