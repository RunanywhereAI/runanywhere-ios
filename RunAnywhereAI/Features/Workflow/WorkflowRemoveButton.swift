#if os(macOS)
import SwiftUI

/// Takes one row out of an editable list. The workflow editor has three such
/// lists — headers, pack inputs, pack outputs — and each had written its own.
struct WorkflowRemoveButton: View {
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "minus.circle.fill")
                .glyph(Glyph.sm, weight: .semibold)
                .foregroundStyle(AppColors.textSecondary)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
#endif
