//
//  WorkflowPackDraft.swift
//  RunAnywhereAI
//
//  What the two pack-creation flows fill in before a NodePack exists. Both a
//  composite pack turned out of the current graph and a hand-written script pack
//  declare the same metadata and the same ports, so they share one draft and one
//  form; only the implementation arm and the capability block differ.
//

import Foundation
import RunAnywhere
import SwiftUI

/// A declared port being edited. `WorkflowToolPort` keys identity off its name,
/// which changes on every keystroke while the user names it, so the draft keeps
/// its own stable identity and converts on the way out.
struct WorkflowPackPortDraft: Identifiable, Equatable {
    let id = UUID()
    var name = ""
    var summary = ""
    var required = false
    var type: RAToolArgumentType = .string

    var port: WorkflowToolPort {
        WorkflowToolPort(name: name, summary: summary, required: required, type: type)
    }
}

struct WorkflowPackOutputDraft: Identifiable, Equatable {
    let id = UUID()
    var name = ""
}

/// The swatches a pack may pick from. A free colour picker would let a pack
/// choose a card that reads as broken next to every other card, so the choice is
/// this app's own accents.
///
/// The raw values are the wire encoding — `NodePack.accent_rgb` is a packed RGB
/// integer another app has to be able to read — and they are the light-mode
/// values of the tokens `color` resolves to. Nothing draws the raw number:
/// `color` is what reaches the screen, so a swatch follows the theme.
enum WorkflowPackAccent: UInt32, CaseIterable, Identifiable {
    case brand = 0xFF_69_00
    case blue = 0x2F_6F_ED
    case green = 0x15_8A_4E
    case red = 0xC8_32_1F
    case purple = 0x6D_4A_C4
    case slate = 0x5A_64_73

    var id: UInt32 { rawValue }

    var color: Color {
        switch self {
        case .brand: AppColors.brand
        case .blue: AppColors.info
        case .green: AppColors.success
        case .red: AppColors.danger
        case .purple: AppColors.primaryPurple
        case .slate: AppColors.textSecondary
        }
    }

    var label: String {
        switch self {
        case .brand: "Orange"
        case .blue: "Blue"
        case .green: "Green"
        case .red: "Red"
        case .purple: "Purple"
        case .slate: "Slate"
        }
    }
}

struct WorkflowPackDraft: Equatable {
    var name = ""
    var summary = ""
    var author = ""
    var version = "1.0.0"
    var category = WorkflowNodeCategory.integration.rawValue
    var icon = WorkflowPackCatalog.fallbackSymbol
    var accent: WorkflowPackAccent = .purple

    var inputs: [WorkflowPackPortDraft] = []
    var outputs: [WorkflowPackOutputDraft] = []

    /// Empty entry means the composite's own trigger; empty exit means the last
    /// node in topological order. Both are what most packs want.
    var entryNodeID = ""
    var exitNodeID = ""

    var script = "return items;"
    var allowsNetwork = false
    var allowsFilesystem = false
    var allowsTools = false
    var toolNames = ""

    /// A problem the user has to fix, or nil when the draft is ready to save.
    var validationMessage: String? {
        if name.workflowTrimmed.isEmpty { return "Give the pack a name." }
        let inputNames = inputs.map { $0.name.workflowTrimmed }
        if inputNames.contains(where: \.isEmpty) { return "Every input needs a name." }
        if Set(inputNames).count != inputNames.count { return "Input names have to be unique." }
        let outputNames = outputs.map { $0.name.workflowTrimmed }
        if outputNames.contains(where: \.isEmpty) { return "Every output needs a name." }
        if Set(outputNames).count != outputNames.count { return "Output names have to be unique." }
        return nil
    }

    var scriptValidationMessage: String? {
        if let message = validationMessage { return message }
        if script.workflowTrimmed.isEmpty { return "A script pack needs a body." }
        return nil
    }

    // MARK: - Building the pack

    func compositePack(id: String, graph: RAWorkflowDocument) -> RANodePack {
        var pack = basePack(id: id)
        var composite = RACompositeImplementation()
        composite.graph = graph
        composite.entryNodeID = entryNodeID
        composite.exitNodeID = exitNodeID
        pack.composite = composite
        return pack
    }

    func scriptPack(id: String) -> RANodePack {
        var pack = basePack(id: id)
        var script = RAScriptImplementation()
        script.source = self.script
        pack.script = script

        var capabilities = RANodePackCapabilities()
        capabilities.network = allowsNetwork
        capabilities.filesystem = allowsFilesystem
        capabilities.tools = allowsTools
        capabilities.toolNames = allowsTools ? parsedToolNames : []
        pack.capabilities = capabilities
        return pack
    }

    var parsedToolNames: [String] {
        toolNames
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func basePack(id: String) -> RANodePack {
        var pack = RANodePack()
        pack.id = id
        pack.name = name.workflowTrimmed
        pack.description_p = summary.workflowTrimmed
        pack.author = author.workflowTrimmed
        pack.version = version.workflowTrimmed
        pack.category = category.workflowTrimmed
        pack.icon = icon.workflowTrimmed
        pack.accentRgb = accent.rawValue
        pack.inputs = inputs.map { draft in
            var normalized = draft
            normalized.name = draft.name.workflowTrimmed
            return normalized.port.wire
        }
        pack.outputs = outputs.map { $0.name.workflowTrimmed }
        return pack
    }
}

extension String {
    var workflowTrimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
