//
//  RunningAppsTool.swift
//  RunAnywhereAI
//
//  list_running_apps — the user-visible applications running on this Mac.
//  macOS only: iOS does not expose other processes to an app.
//

#if os(macOS)
import AppKit
import Foundation
import RunAnywhere

enum RunningAppsTool {
    static var definition: ToolDefinition {
        ToolDefinition(
            name: "list_running_apps",
            description: """
                Lists the applications currently running on this Mac — the ones that appear \
                in the Dock and the app switcher, not background daemons or helper \
                processes. Use when the user asks what apps are open, or whether a \
                particular app is running. Name only apps that literally appear in the \
                result; an app missing from the list is not running as a regular \
                application. This tool cannot launch, quit, or interact with apps.
                """,
            parameters: [],
            category: "System"
        )
    }

    static var executor: ToolExecutor {
        { _ in
            let names = await MainActor.run {
                NSWorkspace.shared.runningApplications
                    .filter { $0.activationPolicy == .regular }
                    .compactMap(\.localizedName)
                    .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            }
            let frontmost = await MainActor.run {
                NSWorkspace.shared.frontmostApplication?.localizedName ?? ""
            }
            return [
                "app_count": RAToolValue(names.count),
                "apps": RAToolValue(names.joined(separator: "; ")),
                "frontmost_app": RAToolValue(frontmost)
            ]
        }
    }
}
#endif
