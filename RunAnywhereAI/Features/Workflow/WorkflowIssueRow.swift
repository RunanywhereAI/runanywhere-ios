#if os(macOS)
import SwiftUI

/// One validation problem, in the canvas popover and in the inspector.
///
/// `warning`, not `danger`: the problems this lists are overwhelmingly
/// "'prompt' is required: connect it or type a value" — work the user has not
/// finished, not work that broke.
struct WorkflowIssueRow: View {
    let message: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .glyph(Glyph.sm, weight: .semibold)
                .foregroundStyle(AppColors.warning)
            Text(message)
                .foregroundStyle(AppColors.textPrimary)
                .multilineTextAlignment(.leading)
        }
        .appType(.caption)
        .contentShape(Rectangle())
    }
}
#endif
