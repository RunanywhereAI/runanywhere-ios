//
//  WorkflowNodeReference.swift
//  RunAnywhereAI
//
//  Documentation for every node kind, held as data rather than as prose in a
//  view, so the same text can be listed, searched and shown in a detail pane
//  without being duplicated.
//
//  Written against node_executors.cpp and agent_workflow.proto, which decide
//  what a node actually does with its inputs. Where the inspector's wording and
//  the executor's behaviour disagree, this file describes the executor and says
//  so.
//

import Foundation

/// What a socket is for, said in one word next to its name. A node's own
/// arguments are `declared` rather than listed one by one: a Tool Call node
/// grows a socket per argument of whichever tool it names, so the set is not
/// known until the node has one.
enum WorkflowReferencePortRole {
    case flow
    case declared
    case branch
    case emitted

    var label: String {
        switch self {
        case .flow: "flow"
        case .declared: "one per argument"
        case .branch: "branch"
        case .emitted: "output"
        }
    }
}

/// A request to open the reference, optionally already showing one node.
/// Identifiable so it can drive a sheet, and carried on the editor's view model
/// so the top bar and the inspector can both raise it.
struct WorkflowNodeReferenceRequest: Identifiable {
    let id = UUID()
    var focus: WorkflowNodeKind?
}

struct WorkflowReferencePort: Identifiable {
    let name: String
    let role: WorkflowReferencePortRole
    let detail: String

    var id: String { name }
}

struct WorkflowReferenceSetting: Identifiable {
    let label: String
    let detail: String

    var id: String { label }
}

struct WorkflowReferenceExample {
    let caption: String
    let snippet: String
}

struct WorkflowNodeReference: Identifiable {
    let kind: WorkflowNodeKind
    let summary: String
    let inputPorts: [WorkflowReferencePort]
    let settings: [WorkflowReferenceSetting]
    let emits: String
    let outputPorts: [WorkflowReferencePort]
    let example: WorkflowReferenceExample
    let notes: [String]

    var id: String { kind.rawValue }
    var title: String { kind.title }
    var systemImage: String { kind.systemImage }
    var category: WorkflowNodeCategory { kind.category }

    /// Every field a search should reach, flattened once so filtering a
    /// keystroke does not walk the whole structure each time.
    var searchText: String {
        var parts = [title, category.rawValue, summary, emits, example.caption, example.snippet]
        parts.append(contentsOf: inputPorts.flatMap { [$0.name, $0.detail] })
        parts.append(contentsOf: outputPorts.flatMap { [$0.name, $0.detail] })
        parts.append(contentsOf: settings.flatMap { [$0.label, $0.detail] })
        parts.append(contentsOf: notes)
        return parts.joined(separator: " ").lowercased()
    }
}

extension WorkflowNodeReference {
    static let all: [WorkflowNodeReference] = WorkflowNodeKind.allCases.map(reference(for:))

    /// The shared preamble every node's input list starts from. Data travels as
    /// a list, so the plain `in` socket means "the list the upstream node
    /// emitted", never a single value.
    static let flowPort = WorkflowReferencePort(
        name: "in",
        role: .flow,
        detail: "The list of items the upstream node emitted."
    )

    static let outPort = WorkflowReferencePort(
        name: "out",
        role: .emitted,
        detail: "Everything this node emitted, as one list."
    )
}
