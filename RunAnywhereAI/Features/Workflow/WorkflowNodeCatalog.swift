//
//  WorkflowNodeCatalog.swift
//  RunAnywhereAI
//
//  One case per config arm in agent_workflow.proto, plus the port names commons
//  validates edges against. `ports_for()` in workflow_validator.cpp is the
//  authority: a socket the canvas draws that commons does not know about
//  produces a graph the backend rejects at save, so the two lists must match
//  exactly.
//

import RunAnywhere
import SwiftUI

enum WorkflowNodeCategory: String, CaseIterable, Identifiable {
    case trigger = "Trigger"
    case ai = "AI"
    case speech = "Speech"
    case knowledge = "Knowledge"
    case models = "Models"
    case logic = "Logic"
    case integration = "Integration"

    var id: String { rawValue }

    /// Seven groups against a palette that holds four hues and three text
    /// weights, so the three quietest groups are told apart by weight rather
    /// than by colour. `danger` is left out entirely: on this screen it means a
    /// node failed, and a category that borrowed it would read as an error.
    var accent: Color {
        switch self {
        case .trigger: AppColors.success
        case .ai: AppColors.brand
        case .speech: AppColors.info
        case .knowledge: AppColors.primaryPurple
        case .logic: AppColors.textPrimary
        case .models: AppColors.textTertiary
        case .integration: AppColors.textSecondary
        }
    }
}

/// Output socket names. "out" everywhere except Condition and Filter, which
/// branch into "true" and "false", and a pack node, whose outputs are whatever
/// the pack declared — an open set, which is why this is not an enum.
struct WorkflowOutputPort: RawRepresentable, Identifiable, Hashable {
    let rawValue: String

    private init(name: String) {
        rawValue = name
    }

    /// An empty port name is what a document written by an older writer leaves
    /// behind, and commons has no port by that name, so it is rejected here
    /// rather than drawn as a socket nothing can connect to.
    init?(rawValue: String) {
        guard !rawValue.isEmpty else { return nil }
        self.init(name: rawValue)
    }

    var id: String { rawValue }

    static let out = WorkflowOutputPort(name: "out")
    static let truthy = WorkflowOutputPort(name: "true")
    static let falsy = WorkflowOutputPort(name: "false")

    var tint: Color {
        switch self {
        case .truthy: AppColors.success
        case .falsy: AppColors.danger
        default: AppColors.brand
        }
    }
}

/// One input socket. Tool nodes grow one per declared argument and Merge grows
/// numbered ones, so the list belongs to a node and its settings rather than to
/// its kind alone.
struct WorkflowInputPort: Identifiable, Hashable {
    enum Role: Hashable {
        case flow
        case argument(required: Bool)
    }

    static let flowName = "in"

    let name: String
    let role: Role

    var id: String { name }

    var isArgument: Bool {
        if case .argument = role { return true }
        return false
    }

    var isRequired: Bool {
        if case .argument(let required) = role { return required }
        return false
    }

    static func flow(_ name: String = flowName) -> WorkflowInputPort {
        WorkflowInputPort(name: name, role: .flow)
    }
}

struct WorkflowNodeDescriptor {
    let title: String
    let systemImage: String
    let category: WorkflowNodeCategory
}

enum WorkflowNodeKind: String, CaseIterable, Identifiable, Codable {
    case manualTrigger
    case scheduleTrigger

    case llmGenerate
    case llmStructured
    case vision
    case embed
    case rerank

    case transcribe
    case speak
    case detectVoice
    case diarize
    case segment

    case ragQuery
    case ragIngest

    case loadModel

    case condition
    case filter
    case loopOverItems
    case code
    case setTransform
    case merge
    case splitOut
    case aggregate
    case wait

    case toolCall
    case httpRequest
    case fileRead
    case fileWrite

    case packNode

    var id: String { rawValue }

    var title: String { descriptor.title }
    var systemImage: String { descriptor.systemImage }
    var category: WorkflowNodeCategory { descriptor.category }

    var isTrigger: Bool { self == .manualTrigger || self == .scheduleTrigger }

    /// The palette's fixed rows. A pack node is left out because there is no
    /// generic one to place: it only exists as an instance of an installed pack,
    /// which the palette lists separately from the pack itself.
    static var placeable: [WorkflowNodeKind] {
        allCases.filter { $0 != .packNode }
    }

    var outputPorts: [WorkflowOutputPort] {
        switch self {
        case .condition, .filter: [.truthy, .falsy]
        default: [.out]
        }
    }

    /// Exhaustive on purpose: a new proto arm does not compile until it has a
    /// title, a symbol, and a palette group.
    private var descriptor: WorkflowNodeDescriptor {
        switch self {
        case .manualTrigger:
            .init(title: "Manual Trigger", systemImage: "play.circle.fill", category: .trigger)
        case .scheduleTrigger:
            .init(title: "Schedule Trigger", systemImage: "clock.fill", category: .trigger)
        case .llmGenerate:
            .init(title: "LLM Generate", systemImage: "brain.head.profile", category: .ai)
        case .llmStructured:
            .init(title: "LLM Structured", systemImage: "curlybraces.square", category: .ai)
        case .vision:
            .init(title: "Vision", systemImage: "eye", category: .ai)
        case .embed:
            .init(
                title: "Embed",
                systemImage: "point.3.connected.trianglepath.dotted",
                category: .ai
            )
        case .rerank:
            .init(title: "Rerank", systemImage: "list.number", category: .ai)
        case .transcribe:
            .init(title: "Transcribe", systemImage: "waveform", category: .speech)
        case .speak:
            .init(title: "Speak", systemImage: "speaker.wave.2.fill", category: .speech)
        case .detectVoice:
            .init(title: "Detect Voice", systemImage: "mic.fill", category: .speech)
        case .diarize:
            .init(title: "Diarize", systemImage: "person.2.wave.2", category: .speech)
        case .segment:
            .init(title: "Segment", systemImage: "scissors", category: .speech)
        case .ragQuery:
            .init(title: "RAG Query", systemImage: "text.magnifyingglass", category: .knowledge)
        case .ragIngest:
            .init(
                title: "RAG Ingest",
                systemImage: "tray.and.arrow.down.fill",
                category: .knowledge
            )
        case .loadModel:
            .init(title: "Load Model", systemImage: "shippingbox.fill", category: .models)
        case .condition:
            .init(title: "Condition", systemImage: "arrow.triangle.branch", category: .logic)
        case .filter:
            .init(
                title: "Filter",
                systemImage: "line.3.horizontal.decrease.circle",
                category: .logic
            )
        case .loopOverItems:
            .init(
                title: "Loop Over Items",
                systemImage: "arrow.triangle.2.circlepath",
                category: .logic
            )
        case .code:
            .init(title: "Code", systemImage: "curlybraces", category: .logic)
        case .setTransform:
            .init(title: "Set / Transform", systemImage: "slider.horizontal.3", category: .logic)
        case .merge:
            .init(title: "Merge", systemImage: "arrow.triangle.merge", category: .logic)
        case .splitOut:
            .init(title: "Split Out", systemImage: "square.split.2x1", category: .logic)
        case .aggregate:
            .init(
                title: "Aggregate",
                systemImage: "rectangle.compress.vertical",
                category: .logic
            )
        case .wait:
            .init(title: "Wait", systemImage: "hourglass", category: .logic)
        case .toolCall:
            .init(
                title: "Tool Call",
                systemImage: "wrench.and.screwdriver.fill",
                category: .integration
            )
        case .httpRequest:
            .init(title: "HTTP Request", systemImage: "globe", category: .integration)
        case .fileRead:
            .init(title: "File Read", systemImage: "doc.text", category: .integration)
        case .fileWrite:
            .init(title: "File Write", systemImage: "doc.badge.plus", category: .integration)
        case .packNode:
            .init(title: "Node Pack", systemImage: "shippingbox", category: .integration)
        }
    }
}
