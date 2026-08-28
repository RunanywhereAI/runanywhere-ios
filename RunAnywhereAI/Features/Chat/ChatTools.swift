import Foundation
import RunAnywhere

enum ChatTools {
    /// What the model is told about its tools, loaded from `Skill.md`.
    ///
    /// Kept as a document rather than a string literal because it is prose the
    /// model reads, and prose is edited far more often than code. Bundled, so
    /// changing how tools are described does not mean touching Swift.
    static let skill: String = {
        guard let url = Bundle.main.url(forResource: "Skill", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            // A missing document must not silently strip every instruction the
            // model has about its tools, so say enough to keep them usable.
            return """
                You have two tools: web_research, which searches the live web and \
                answers from the pages it reads, and calculate, which evaluates one \
                arithmetic expression. Use web_research for anything you cannot know \
                from training alone. Answer from tool results, never from memory, \
                whenever a tool ran.
                """
        }
        return text
    }()

    /// Chat offers two tools and no more. A longer list measurably degraded
    /// answers on the small models this app runs, so the set is pinned rather
    /// than left to default: an empty `tools` means "everything registered",
    /// and the app now registers a dozen for the workflow editor.
    ///
    /// Three names for two tools. `web_research` is commons' own, read live
    /// from the provider registry so the wording the model sees stays
    /// commons' rather than a copy that goes stale; `search_web` is the Swift
    /// stand-in `AppTools` falls back to when that provider is missing. One or
    /// the other is registered, never both.
    private static let offeredNames: Set<String> = ["calculate", "web_research", "search_web"]

    static func offeredTools() async -> [ToolDefinition] {
        let host = await RunAnywhere.llm.tools.list()
        let hostNames = Set(host.map(\.name))
        let providers = RunAnywhere.llm.tools.nativeProviders()
            .filter { !hostNames.contains($0.name) }
        return (host + providers).filter { offeredNames.contains($0.name) }
    }
}
