# Moving the workflow engine out of commons

## What San asked for

> only tool calling changes + kv cache etc whatever is necessary should go to
> sdks, all the workflows need to be only kept within the swift app
> — San, 2026-08-27

> Now we discuss to keep it in the Swift layer, It's okay to re-implement at
> runElectron. The RunAnywhere SDKs should not be changed for this
> — San, 2026-08-28

So: workflows leave `runanywhere-sdks` entirely and live in the app. Electron
re-implements its own later. Tool calling and KV cache stay in the SDK.

## What is actually in the SDK today

PR 773 carries the whole engine in C++:

| Area | Files |
|---|---|
| Runner | `core/src/agent/workflow_runner.{h,cpp}`, `node_executors.{h,cpp}` |
| Storage | `workflow_store.{h,cpp}`, `pack_store.{h,cpp}`, `bundle.{h,cpp}` |
| Scheduling | `cron.{h,cpp}` |
| Expressions | `expression.{h,cpp}` |
| Validation | `workflow_validator.{h,cpp}` |
| ABI | `core/include/rac/agent/rac_agent_workflow.h`, `core/src/agent/rac_agent_workflow.cpp` |
| Schema | `idl/agent_workflow.proto` |
| Tests | `test_agent_workflow.cpp`, `test_agent_workflow_e2e.cpp`, `test_cron.cpp` |
| Swift binding | `Public/Extensions/Workflows/RunAnywhere+Workflows.swift` |

## What the app depends on

Ten calls, from `WorkflowEditorViewModel`, `WorkflowScheduler`, `WorkflowPackStore`
and `WorkflowNodeInspectorSections`:

`list` · `load` · `save` · `run` · `packs` · `savePack` · `deletePack` ·
`exportBundle` · `importBundle` · `nextCronFireDate`

Everything else under `Features/Workflow/` — about twenty files — is already
Swift and stays exactly as it is. The UI is not the problem; the engine under it
is.

## The shape of the move

1. **`WorkflowStore`** — the four CRUD calls plus packs, over JSON files in
   Application Support. Replaces `workflow_store.cpp` and `pack_store.cpp`.
   Smallest piece, no behaviour to preserve beyond the file format.
2. **`WorkflowBundle`** — export and import. Replaces `bundle.cpp`. The bundle
   format is already a Swift `Codable` in `WorkflowBundleDocument.swift`, so
   this is mostly moving code that exists.
3. **`CronExpression`** — `nextCronFireDate` only. One function, and
   `test_cron.cpp` is a ready-made table of cases to port.
4. **`WorkflowRunner`** — the real work. Node execution against the existing
   `RunAnywhere` LLM and tool APIs, plus `expression.cpp` for interpolation and
   `workflow_validator.cpp` for the issue list the editor already renders.

1 to 3 are mechanical. 4 is where the time goes.

## Order

Land 1–3 first behind the same call signatures, so the app keeps building while
the runner is still the C++ one. Then 4, then delete `core/src/agent/**`,
`idl/agent_workflow.proto`, the three tests and the Swift binding in one commit
that touches nothing else.

## Open question for San, before anything is deleted

He said "swift app" once and "Swift layer" once. Those are different places:
the app (`runanywhere-ios`) or the Swift SDK (`bindings/swift`). "The
RunAnywhere SDKs should not be changed for this" reads as the app, and this plan
assumes the app — but it is worth one line of confirmation, because putting it
in the wrong one is the whole job twice.

## Not started

Deleting from PR 773 is a repo-level action on a pull request under his review,
so it waits. Nothing in this plan has been executed.
