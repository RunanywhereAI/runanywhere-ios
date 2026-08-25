//
//  AppTools.swift
//  RunAnywhereAI
//
//  The whole tool set the app can execute, registered once while the SDK
//  starts.
//
//  Registration deliberately does not hang off Chat's tools switch. The
//  workflow editor's Tool Call node lists whatever is in the registry, so a
//  workflow built before anyone had opened Chat and turned tools on had
//  nothing to choose from. What Chat *offers a model* is a separate decision
//  and lives in `ChatTools`.
//

import Foundation
import RunAnywhere

enum AppTools {
    static func registerAll() async {
        await RunAnywhere.llm.tools.clear()

        for tool in portable {
            await RunAnywhere.llm.tools.register(tool.definition, executor: tool.executor)
        }
        #if os(macOS)
        await RunAnywhere.llm.tools.register(
            RunningAppsTool.definition,
            executor: RunningAppsTool.executor
        )
        #endif

        // The commons `web_research` provider. It lives in the native registry
        // rather than this one, so it never appears in `llm.tools.list()`;
        // `llm.tools.nativeProviders()` is what reads it. `search_web` is the
        // Swift stand-in for a build where the provider symbol is missing, and
        // the early return is what keeps the two from both being registered.
        if RunAnywhere.registerWebResearchTool() {
            return
        }
        await RunAnywhere.registerWebSearchTool()
    }

    private struct Tool {
        let definition: ToolDefinition
        let executor: ToolExecutor
    }

    private static var portable: [Tool] {
        [
            Tool(definition: CalculateTool.definition, executor: CalculateTool.executor),
            Tool(definition: DateTimeTool.definition, executor: DateTimeTool.executor),
            Tool(definition: WorldClockTool.definition, executor: WorldClockTool.executor),
            Tool(definition: ClipboardReadTool.definition, executor: ClipboardReadTool.executor),
            Tool(definition: ClipboardWriteTool.definition, executor: ClipboardWriteTool.executor),
            Tool(definition: NotificationTool.definition, executor: NotificationTool.executor),
            Tool(definition: OpenURLTool.definition, executor: OpenURLTool.executor),
            Tool(definition: CalendarEventsTool.definition, executor: CalendarEventsTool.executor),
            Tool(definition: CalendarCreateTool.definition, executor: CalendarCreateTool.executor),
            Tool(definition: CalendarListTool.definition, executor: CalendarListTool.executor),
            Tool(definition: ReminderCreateTool.definition, executor: ReminderCreateTool.executor),
            Tool(definition: ReminderListTool.definition, executor: ReminderListTool.executor)
        ]
    }
}
