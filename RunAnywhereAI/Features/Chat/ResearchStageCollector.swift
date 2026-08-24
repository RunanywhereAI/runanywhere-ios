import Foundation
import RunAnywhere

/// Buffers tool progress arriving off the main actor and republishes it in
/// order.
///
/// Commons calls the progress closure synchronously on the thread running the
/// tool, which is neither the main actor nor a place to block. This collects
/// there under a lock and hands snapshots to the view model through a stream,
/// so nothing writes observable state from the wrong isolation.
final class ResearchStageCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var stages: [String: [ResearchStage]] = [:]
    private let continuation: AsyncStream<[String: [ResearchStage]]>.Continuation
    let stream: AsyncStream<[String: [ResearchStage]]>

    init() {
        var escaped: AsyncStream<[String: [ResearchStage]]>.Continuation!
        stream = AsyncStream { escaped = $0 }
        continuation = escaped
    }

    func record(_ progress: ToolProgress) {
        let snapshot: [String: [ResearchStage]] = lock.withLock {
            var list = stages[progress.toolName] ?? []
            let status = Self.status(for: progress.status)
            let stage = ResearchStage(
                id: "\(progress.stageID)#\(progress.sequence)",
                stageID: progress.stageID,
                label: progress.label,
                status: status,
                detail: progress.detail
            )

            // A step reports started, then finished. Settle the open row in
            // place so it does not read as two. Anything else appends, which
            // is what keeps one row per search rather than one for the whole
            // gathering step.
            if status != .running,
               let index = list.lastIndex(where: { $0.stageID == stage.stageID && $0.status == .running }) {
                list[index] = ResearchStage(
                    id: list[index].id,
                    stageID: stage.stageID,
                    label: stage.label,
                    status: status,
                    detail: stage.detail
                )
            } else {
                list.append(stage)
            }

            stages[progress.toolName] = list
            return stages
        }
        continuation.yield(snapshot)
    }

    func stagesByTool() -> [String: [ResearchStage]] {
        lock.withLock { stages }
    }

    func finish() {
        continuation.finish()
    }

    private static func status(for status: ToolProgress.Status) -> ResearchStage.Status {
        switch status {
        case .started: .running
        case .completed: .done
        case .failed: .failed
        }
    }
}
