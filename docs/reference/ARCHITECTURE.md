# Navigation architecture

Full detail behind the one-paragraph summary in the root `AGENTS.md`.

`ContentView` branches on platform.

| Platform | Shell | Structure |
|---|---|---|
| macOS | `ConsumerMacShell` | `NavigationSplitView` over `MacSidebar`. Three destinations (Chat, Models, Advanced) plus the conversation list, which is scoped to Chat. Detail is `ChatInterfaceView`, `SimplifiedModelsView`, or `ConsumerAdvancedHubView`. |
| iOS | `ConsumerCompactShell` | `ChatInterfaceView` alone, plus sheets. |

`MacSidebarSelection` has four cases: `.chat` (the transcript, whatever is current),
`.conversation(String)`, `.models`, and `.advanced`. Splitting `.chat` from `.conversation`
is what lets ⌘1 land somewhere real before anything is saved. ⌘1/⌘2/⌘3 are published from
the shell through `focusedSceneValue(\.shellNavigationActions)` because the chat cannot
navigate away from itself. One `@SceneStorage` key, `mac.sidebar.visibility`, persists
whether the sidebar is showing; column width is fixed by `navigationSplitViewColumnWidth`
and the selection is re-derived from the current conversation on restore.

On iOS, Settings and the Advanced hub are sheets, both opened from the conversation drawer
rather than the toolbar. Models is not the same kind of sheet: the chat presents
`ModelSelectionSheet` (a picker, cross-platform), while the full `SimplifiedModelsView`
management screen is reached through a `NavigationLink` inside `CombinedSettingsView`. On
macOS `SimplifiedModelsView` is the `.models` sidebar destination.

`ConsumerAdvancedHubView` has five sections and eight rows:

| Section | Rows | Availability |
|---|---|---|
| Connect | Host this Mac | macOS only (`#if os(macOS)`) |
| Voice Utilities | Transcribe, Read Aloud, Voice Activity | both |
| Voice Utilities | Diarization | iOS only (`#if canImport(UIKit)`) |
| Vision Utilities | Segmentation | iOS only, and so is the whole section |
| Agents | Talk, Computer Use | both |
| Management | Benchmarks | both |

Storage and tool calling live in Settings and Manage Models instead.
