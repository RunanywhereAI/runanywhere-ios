import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// One renderer for a reply, block by block.
///
/// The shape never depends on what the text currently looks like, so a fence
/// arriving mid-stream appends a block instead of swapping the whole reply for
/// a different kind of view. See `MarkdownBlock` for why that matters.
struct MarkdownView: View {
    let blocks: [MarkdownBlock]
    var trailing: Text?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                view(for: block, isLast: index == blocks.count - 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func view(for block: MarkdownBlock, isLast: Bool) -> some View {
        switch block {
        case .paragraph(let text):
            paragraph(text, isLast: isLast)

        case .heading(let level, let text):
            InlineMarkdown(text)
                .appType(level <= 2 ? .sectionTitle : .cardTitle)
                .foregroundStyle(AppColors.textPrimary)
                .padding(.top, Space.xs)

        case .list(let items):
            MarkdownList(items: items)

        case .quote(let text):
            HStack(alignment: .top, spacing: Space.md) {
                Capsule()
                    .fill(AppColors.brand.opacity(0.5))
                    .frame(width: 3)
                InlineMarkdown(text)
                    .appType(.body)
                    .foregroundStyle(AppColors.textSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)

        case .code(let language, let source):
            MarkdownCodeBlock(language: language, source: source)

        case .rule:
            Rectangle()
                .fill(AppColors.border)
                .frame(height: Stroke.hairline)
                .padding(.vertical, Space.xs)
        }
    }

    /// The caret rides inside the final paragraph so it sits against the last
    /// token instead of on a line of its own below the reply.
    @ViewBuilder
    private func paragraph(_ text: String, isLast: Bool) -> some View {
        if isLast, let trailing {
            (InlineMarkdown.text(text) + trailing)
                .appType(.body)
                .foregroundStyle(AppColors.textPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            InlineMarkdown(text)
                .appType(.body)
                .foregroundStyle(AppColors.textPrimary)
                .textSelection(.enabled)
        }
    }
}

/// Inline emphasis, links and code spans, via `AttributedString(markdown:)`.
struct InlineMarkdown: View {
    let raw: String

    init(_ raw: String) {
        self.raw = raw
    }

    var body: some View {
        Self.text(raw)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    static func text(_ raw: String) -> Text {
        Text(attributed(raw))
    }

    /// `.inlineOnlyPreservingWhitespace` keeps a hard-wrapped paragraph looking
    /// the way the model wrote it. Full parsing would collapse the newlines the
    /// block parser already decided to keep.
    static func attributed(_ raw: String) -> AttributedString {
        guard var string = try? AttributedString(
            markdown: raw,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) else {
            return AttributedString(raw)
        }

        for run in string.runs {
            guard let intent = run.inlinePresentationIntent else { continue }
            if intent.contains(.stronglyEmphasized) {
                // Semibold, not bold: bold body copy in a chat reply reads as
                // shouting next to the surrounding text.
                string[run.range].font = AppType.font(.body).weight(.semibold)
            }
            if intent.contains(.emphasized) {
                string[run.range].font = AppType.font(.body).italic()
            }
            if intent.contains(.code) {
                string[run.range].font = AppType.font(.mono)
                string[run.range].foregroundColor = AppColors.info
            }
        }
        return string
    }
}

private struct MarkdownList: View {
    let items: [MarkdownListItem]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                    Text(item.label)
                        .appType(.body)
                        .foregroundStyle(item.isOrdered ? AppColors.textSecondary : AppColors.brand)
                        .monospacedDigit()
                    InlineMarkdown(item.text)
                        .appType(.body)
                        .foregroundStyle(AppColors.textPrimary)
                }
                .padding(.leading, CGFloat(item.depth) * Space.lg)
            }
        }
    }
}

private struct MarkdownCodeBlock: View {
    let language: String?
    let source: String

    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.sm) {
                Text(language?.uppercased() ?? "CODE")
                    .appType(.overline)
                    .foregroundStyle(AppColors.textSecondary)

                Spacer(minLength: 0)

                Button {
                    copy()
                } label: {
                    HStack(spacing: Space.xs) {
                        Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                            .glyph(Glyph.xs - 2)
                        Text(didCopy ? "Copied" : "Copy")
                            .appType(.caption)
                    }
                    .foregroundStyle(didCopy ? AppColors.success : AppColors.textSecondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Space.md)
            .frame(height: 30)
            .background(AppColors.surfaceMuted)

            Divider().overlay(AppColors.border)

            ScrollView(.horizontal, showsIndicators: false) {
                Text(source)
                    .appType(.mono)
                    .foregroundStyle(AppColors.textPrimary)
                    .textSelection(.enabled)
                    .padding(Space.md)
            }
        }
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(AppColors.border, lineWidth: Stroke.hairline)
        )
    }

    private func copy() {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(source, forType: .string)
        #else
        UIPasteboard.general.string = source
        #endif
        withAnimation(.easeOut(duration: 0.15)) { didCopy = true }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.easeOut(duration: 0.2)) { didCopy = false }
        }
    }
}
