//
//  WorkflowTemplate.swift
//  RunAnywhereAI
//
//  A named starting point for a new workflow: a graph that arrives wired,
//  positioned and valid, so "New Workflow" can offer something that already
//  does a job instead of an empty canvas.
//

import Foundation
import SwiftUI

struct WorkflowTemplate: Identifiable {
    enum Category: String, CaseIterable, Identifiable {
        case documents = "Documents"
        case media = "Audio and Images"
        case knowledge = "Knowledge"
        case routines = "On a Schedule"
        case device = "On This Device"

        var id: String { rawValue }
    }

    let name: String
    let purpose: String
    let category: Category
    let systemImage: String
    /// The kinds a run walks, in order, with a repeated kind collapsed — a
    /// branch that writes a file down both arms is still "writes a file".
    let chain: [WorkflowNodeKind]

    private let build: () -> WorkflowGraph

    /// Names are unique across the library and are what the new document is
    /// called, so there is nothing for a separate id to say.
    var id: String { name }

    init(
        name: String,
        purpose: String,
        category: Category,
        systemImage: String,
        build: @escaping () -> WorkflowGraph
    ) {
        self.name = name
        self.purpose = purpose
        self.category = category
        self.systemImage = systemImage
        self.build = build
        chain = Self.chain(of: build())
    }

    func graph() -> WorkflowGraph {
        build()
    }

    var chainDescription: String {
        chain.map(\.title).joined(separator: " → ")
    }

    /// Kahn's algorithm, seeded in placement order, which is the same order
    /// commons resolves the graph in. A template is a DAG by construction, so
    /// nothing is left over at the end.
    private static func chain(of graph: WorkflowGraph) -> [WorkflowNodeKind] {
        var remaining: [String: Int] = [:]
        for node in graph.nodes { remaining[node.id] = 0 }
        for edge in graph.edges where remaining[edge.toNode] != nil {
            remaining[edge.toNode]? += 1
        }

        var frontier = graph.nodes.filter { remaining[$0.id] == 0 }.map(\.id)
        var kinds: [WorkflowNodeKind] = []
        var cursor = 0
        while cursor < frontier.count {
            let current = frontier[cursor]
            cursor += 1
            if let kind = graph.node(current)?.kind, kinds.last != kind {
                kinds.append(kind)
            }
            for edge in graph.edges where edge.fromNode == current {
                remaining[edge.toNode]? -= 1
                if remaining[edge.toNode] == 0 { frontier.append(edge.toNode) }
            }
        }
        return kinds
    }
}

/// Assembles a template graph by node name.
///
/// Names rather than ids because expressions address nodes by name too, so a
/// template reads as the chain it draws and there is one spelling of each node
/// to get wrong instead of two.
struct WorkflowTemplateBuilder {
    /// Card pitch on the canvas. A card is 240pt wide, so the column pitch
    /// leaves the rope enough room to read as a rope; the row pitch clears the
    /// tallest card a template places. Both are grid multiples, so a node
    /// dragged after loading does not jump.
    private static let origin = CGPoint(x: 80, y: 120)
    private static let columnPitch: CGFloat = 320
    private static let rowPitch: CGFloat = 176

    private var graph = WorkflowGraph()
    private var ids: [String: String] = [:]

    mutating func node(
        _ kind: WorkflowNodeKind,
        _ name: String,
        column: Int,
        row: Double = 0,
        settings configure: (inout WorkflowNodeSettings) -> Void = { _ in }
    ) {
        var node = WorkflowNode(
            id: "n\(graph.nodes.count + 1)",
            kind: kind,
            name: name,
            position: CGPoint(
                x: Self.origin.x + CGFloat(column) * Self.columnPitch,
                y: Self.origin.y + CGFloat(row) * Self.rowPitch
            )
        )
        configure(&node.settings)
        ids[name] = node.id
        graph.nodes.append(node)
    }

    /// Wire a straight run: each name's `out` into the next one's `in`.
    mutating func chain(_ names: String...) {
        for (from, to) in zip(names, names.dropFirst()) {
            connect(from, to: to)
        }
    }

    mutating func connect(
        _ from: String,
        _ outputPort: WorkflowOutputPort = .out,
        to target: String,
        input inputPort: String = WorkflowInputPort.flowName
    ) {
        guard let fromID = ids[from], let toID = ids[target] else { return }
        graph.edges.append(
            WorkflowEdge(fromNode: fromID, fromPort: outputPort, toNode: toID, toPort: inputPort)
        )
    }

    func build() -> WorkflowGraph {
        graph
    }
}
