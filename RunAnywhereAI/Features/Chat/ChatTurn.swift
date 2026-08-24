import Foundation

enum TurnRole: String, Hashable, Codable {
    case user
    case assistant
}

struct TurnMetrics: Hashable, Codable {
    var timeToFirstTokenMs: Int64 = 0
    var tokensPerSecond: Float = 0
    var outputTokens: Int = 0

    var isEmpty: Bool { outputTokens == 0 && timeToFirstTokenMs == 0 }
}

/// One step a multi-step tool reported while it was running.
///
/// The stage identifiers are written by the tool, not by this app: commons has
/// no idea that `web_research` has four steps, and a tool added later with
/// three or nine needs no change here. Anything keyed off `stageID` is a
/// presentation choice with a fallback, never a requirement.
struct ResearchStage: Identifiable, Hashable, Codable {
    enum Status: String, Hashable, Codable {
        case running
        case done
        case failed
    }

    /// Unique per row. A stage key repeats — `gathering` reports once per
    /// search — so identity has to come from the emission, not the key, or
    /// `ForEach` collapses the whole search trail into one line.
    let id: String

    /// The tool's own key for this kind of step, e.g. `gathering`. Repeats
    /// across rows on purpose.
    let stageID: String

    var label: String
    var status: Status
    var detail: String?

    var symbol: String {
        switch status {
        case .running: "circle.dotted"
        case .done: "checkmark.circle.fill"
        case .failed: "exclamationmark.circle.fill"
        }
    }

    /// Icon for the kind of step, when the tool uses a key this app recognises.
    ///
    /// Presentation only, and every unknown key falls back — stage keys belong
    /// to the tool, so a provider added later renders without touching this.
    var kindSymbol: String {
        switch stageID {
        case "understanding": "text.magnifyingglass"
        case "generating_questions": "list.bullet"
        case "gathering": "magnifyingglass"
        case "reading": "doc.text"
        case "composing": "sparkles"
        default: "circle"
        }
    }
}

struct ToolInvocation: Identifiable, Hashable, Codable {
    let id: String
    var name: String
    var arguments: String = ""
    var isComplete: Bool = false
    var stages: [ResearchStage] = []

    var isMultiStage: Bool { !stages.isEmpty }
}

struct ChatTurn: Identifiable, Hashable, Codable {
    let id: UUID
    let role: TurnRole
    var text: String
    var thinking: String
    var tools: [ToolInvocation]
    var metrics: TurnMetrics
    var failure: String?
    var wasCancelled: Bool
    var attachmentName: String?
    var attachmentIsImage: Bool
    let createdAt: Date

    init(
        id: UUID = UUID(),
        role: TurnRole,
        text: String = "",
        thinking: String = "",
        tools: [ToolInvocation] = [],
        metrics: TurnMetrics = TurnMetrics(),
        failure: String? = nil,
        wasCancelled: Bool = false,
        attachmentName: String? = nil,
        attachmentIsImage: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.thinking = thinking
        self.tools = tools
        self.metrics = metrics
        self.failure = failure
        self.wasCancelled = wasCancelled
        self.attachmentName = attachmentName
        self.attachmentIsImage = attachmentIsImage
        self.createdAt = createdAt
    }

    var hasThinking: Bool { !thinking.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var isEmpty: Bool { text.isEmpty && !hasThinking && tools.isEmpty && attachmentName == nil }
}


enum DocumentIndexState: Equatable {
    case idle
    case indexing
    case indexed
    case failed(String)
}
