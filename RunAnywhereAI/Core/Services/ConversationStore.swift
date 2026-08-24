import Foundation
import Observation
import os

struct Conversation: Identifiable, Hashable, Codable {
    let id: String
    var title: String
    var updatedAt: Date
    var turns: [ChatTurn]

    init(id: String = UUID().uuidString, title: String = "New Chat", updatedAt: Date = Date(), turns: [ChatTurn] = []) {
        self.id = id
        self.title = title
        self.updatedAt = updatedAt
        self.turns = turns
    }

    var isUntouched: Bool { turns.isEmpty }
}

@Observable
@MainActor
final class ConversationStore {
    private(set) var conversations: [Conversation] = []
    private(set) var currentID: String?

    private let logger = Logger(subsystem: "com.runanywhere.RunAnywhereAI", category: "Conversations")
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var directory: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Conversations", isDirectory: true)
    }

    init() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        // Foundation's default double-seconds encoding, not `.iso8601`: ISO-8601
        // drops sub-second precision, so a reloaded turn never compares equal to
        // the one still in memory and every reopen looks like an edit.
        encoder.dateEncodingStrategy = .deferredToDate
        decoder.dateDecodingStrategy = .deferredToDate
        load()
    }

    var current: Conversation? {
        currentID.flatMap { id in conversations.first { $0.id == id } }
    }

    func search(_ query: String) -> [Conversation] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return conversations }
        return conversations.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed)
                || $0.turns.contains { $0.text.localizedCaseInsensitiveContains(trimmed) }
        }
    }

    @discardableResult
    func createConversation() -> Conversation {
        if let existing = conversations.first(where: \.isUntouched) {
            currentID = existing.id
            return existing
        }
        let conversation = Conversation()
        conversations.insert(conversation, at: 0)
        currentID = conversation.id
        return conversation
    }

    func select(_ id: String) {
        currentID = id
    }

    func turns(for id: String) -> [ChatTurn] {
        conversations.first { $0.id == id }?.turns ?? []
    }

    func update(id: String, turns: [ChatTurn]) {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[index].turns = turns
        conversations[index].updatedAt = Date()
        if conversations[index].title == "New Chat",
           let first = turns.first(where: { $0.role == .user })?.text {
            conversations[index].title = Self.title(from: first)
        }
        let updated = conversations[index]
        conversations.sort { $0.updatedAt > $1.updatedAt }
        save(updated)
    }

    func rename(id: String, to title: String) {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        conversations[index].title = trimmed
        save(conversations[index])
    }

    func delete(id: String) {
        conversations.removeAll { $0.id == id }
        if currentID == id { currentID = conversations.first?.id }
        try? FileManager.default.removeItem(at: file(for: id))
    }

    // MARK: - Disk

    private func file(for id: String) -> URL {
        directory.appendingPathComponent("\(id).json")
    }

    private func save(_ conversation: Conversation) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try encoder.encode(conversation).write(to: file(for: conversation.id), options: .atomic)
        } catch {
            logger.error("save failed: \(error, privacy: .public)")
        }
    }

    private func load() {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return }

        conversations = urls
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(Conversation.self, from: data)
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private static func title(from text: String) -> String {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        guard cleaned.count > 42 else { return cleaned.isEmpty ? "New Chat" : cleaned }
        return String(cleaned.prefix(42)).trimmingCharacters(in: .whitespaces) + "…"
    }
}
