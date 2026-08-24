#if os(macOS)
import SwiftUI

/// How tall a text field in the workflow editor opens.
///
/// Three sizes for three jobs: a line or two of arguments, a paragraph of
/// prose, a body of code. The inspector had eight different numbers for those
/// three questions, including 70 and 90 for the same prompt field on two
/// adjacent node kinds.
enum EditorHeight {
    static let short: CGFloat = 80
    static let prose: CGFloat = 90
    static let code: CGFloat = 160
}

/// Fixed columns in the inspector and the pack editor, so a slider readout and
/// a key field line up wherever they appear.
enum InspectorWidth {
    /// A numeric readout beside a slider — wide enough for "1.00".
    static let readout: CGFloat = 44
    /// The left column of a key/value or name/type pair.
    static let keyColumn: CGFloat = 110
}

/// The inset well every free-text field in the workflow editor sits in.
struct WorkflowCodeEditor: View {
    @Binding var text: String
    var minHeight: CGFloat = EditorHeight.short
    var monospaced = true

    var body: some View {
        TextEditor(text: $text)
            .appType(monospaced ? .mono : .body)
            .scrollContentBackground(.hidden)
            .padding(Space.xs)
            .frame(minHeight: minHeight)
            .background(
                AppColors.surfaceMuted,
                in: RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
            )
    }
}
#endif
