import SwiftUI
import Observation
import RunAnywhere
import os

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

@Observable
@MainActor
final class AppSettings {
    var theme: AppTheme { didSet { UserDefaults.standard.set(theme.rawValue, forKey: Key.theme) } }

    private(set) var usedBytes: Int64 = 0
    private(set) var freeBytes: Int64 = 0
    private(set) var isBusy = false
    var lastError: String?

    private let logger = Logger(subsystem: "com.runanywhere.RunAnywhereAI", category: "Settings")

    private enum Key {
        static let theme = "app.theme"
    }

    init() {
        let raw = UserDefaults.standard.string(forKey: Key.theme) ?? AppTheme.system.rawValue
        theme = AppTheme(rawValue: raw) ?? .system
    }

    func refreshStorage() async {
        let state = await RunAnywhere.models.state()
        usedBytes = state.storageUsedBytes
        freeBytes = state.storageFreeBytes
    }

    func clearCache() async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await RunAnywhere.clearCache()
            try await RunAnywhere.cleanTempFiles()
            await refreshStorage()
            lastError = nil
        } catch {
            logger.error("cache clear failed: \(error, privacy: .public)")
            lastError = String(describing: error)
        }
    }

    static func format(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "0 MB" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
