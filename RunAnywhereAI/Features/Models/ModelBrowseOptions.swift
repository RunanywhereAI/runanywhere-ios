import SwiftUI
import Observation

/// One choice in a view-options control: a word for the wide form, a symbol for
/// the icon-only one.
protocol ModelViewOption: CaseIterable, Identifiable, Equatable {
    var title: String { get }
    var symbol: String { get }
}

/// How the catalog draws a set of models: a column that scans well at any
/// width, or cards that use the width when there is some.
enum ModelLayout: String, CaseIterable, Identifiable, ModelViewOption {
    case list
    case grid

    var id: String { rawValue }

    var title: String {
        switch self {
        case .list: "List"
        case .grid: "Grid"
        }
    }

    var symbol: String {
        switch self {
        case .list: "list.bullet"
        case .grid: "square.grid.2x2"
        }
    }
}

/// What the sections stand for: what a model does, or who made it.
enum ModelGrouping: String, CaseIterable, Identifiable, ModelViewOption {
    case category
    case publisher

    var id: String { rawValue }

    var title: String {
        switch self {
        case .category: "Category"
        case .publisher: "Publisher"
        }
    }

    var symbol: String {
        switch self {
        case .category: "rectangle.3.group"
        case .publisher: "building.2"
        }
    }
}

/// The reader's two choices about how the catalog looks, kept across launches.
///
/// One instance rather than one per view: the catalog opens from the models
/// tab and again from the sheet the voice screens push, and a preference that
/// only holds in the screen you set it in is not a preference.
@Observable
@MainActor
final class ModelBrowsePreferences {
    static let shared = ModelBrowsePreferences()

    var layout: ModelLayout {
        didSet { UserDefaults.standard.set(layout.rawValue, forKey: Key.layout) }
    }

    var grouping: ModelGrouping {
        didSet { UserDefaults.standard.set(grouping.rawValue, forKey: Key.grouping) }
    }

    private enum Key {
        static let layout = "models.layout"
        static let grouping = "models.grouping"
    }

    init() {
        let rawLayout = UserDefaults.standard.string(forKey: Key.layout) ?? ModelLayout.list.rawValue
        layout = ModelLayout(rawValue: rawLayout) ?? .list

        let rawGrouping = UserDefaults.standard.string(forKey: Key.grouping) ?? ModelGrouping.category.rawValue
        grouping = ModelGrouping(rawValue: rawGrouping) ?? .category
    }
}

/// A segmented control for a view option.
///
/// Deliberately quieter than the filter chips above it: the selected segment is
/// a raised surface inside a muted well rather than the brand fill, because
/// changing how the catalog is drawn is not the same kind of act as filtering
/// what is in it.
struct ViewOptionControl<Option: ModelViewOption>: View where Option.AllCases == [Option] {
    @Binding var selection: Option
    var showsTitles = true

    @Namespace private var indicator

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Option.allCases) { option in
                segment(option)
            }
        }
        .padding(Space.hair)
        .background(Capsule().fill(AppColors.surfaceMuted))
        .overlay(Capsule().strokeBorder(AppColors.border, lineWidth: Stroke.hairline))
    }

    private func segment(_ option: Option) -> some View {
        let isActive = selection == option
        return Button {
            withAnimation(Motion.fade) { selection = option }
        } label: {
            HStack(spacing: Space.xs) {
                Image(systemName: option.symbol)
                    .glyph(Glyph.xs, weight: .semibold)
                if showsTitles {
                    Text(option.title)
                        .appType(.meta)
                }
            }
            .foregroundStyle(isActive ? AppColors.textPrimary : AppColors.textSecondary)
            .padding(.horizontal, showsTitles ? Space.md : Space.sm)
            .frame(minWidth: Control.well, minHeight: Control.pill - Space.xs)
            .background {
                if isActive {
                    Capsule()
                        .fill(AppColors.surface)
                        .matchedGeometryEffect(id: "selected", in: indicator)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.title)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}

/// The pair of view options, sitting above the content they change.
struct ModelViewOptions: View {
    @Bindable var preferences: ModelBrowsePreferences

    var body: some View {
        HStack(spacing: Space.sm) {
            ViewOptionControl(selection: $preferences.grouping)
            Spacer(minLength: Space.sm)
            ViewOptionControl(selection: $preferences.layout, showsTitles: false)
        }
    }
}

/// The card grid every part of the catalog reflows into.
///
/// The column width is a size class rather than a measured number: a phone in
/// portrait has room for two cards and a Mac window for three or four, and the
/// adaptive grid fills in the sizes between on its own.
struct ModelCardGrid<Item, Content: View>: View {
    let items: [Item]
    let id: KeyPath<Item, String>
    @ViewBuilder let content: (Item) -> Content

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    private var columnMinimum: CGFloat {
        #if os(iOS)
        sizeClass == .compact ? 156 : 220
        #else
        220
        #endif
    }

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: columnMinimum), spacing: Space.sm, alignment: .top)],
            alignment: .leading,
            spacing: Space.sm
        ) {
            ForEach(items, id: id) { item in
                content(item)
                    .frame(maxHeight: .infinity)
            }
        }
    }
}

/// Lays chips left to right, wrapping when the row runs out of width.
///
/// A card is only as wide as the column it lands in, and an `HStack` of
/// capability tags in a two-column phone grid either clips or pushes the column
/// wider than the grid can afford.
struct WrapLayout: Layout {
    var spacing: CGFloat = Space.xs
    var lineSpacing: CGFloat = Space.xs

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        return arrange(sizes: sizes, width: proposal.width ?? .infinity).size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let offsets = arrange(sizes: sizes, width: bounds.width).offsets
        for (index, subview) in subviews.enumerated() {
            subview.place(
                at: CGPoint(x: bounds.minX + offsets[index].x, y: bounds.minY + offsets[index].y),
                anchor: .topLeading,
                proposal: ProposedViewSize(sizes[index])
            )
        }
    }

    private func arrange(sizes: [CGSize], width: CGFloat) -> (size: CGSize, offsets: [CGPoint]) {
        var offsets: [CGPoint] = []
        var cursor = CGPoint.zero
        var lineHeight: CGFloat = 0
        var widest: CGFloat = 0

        for size in sizes {
            if cursor.x > 0, cursor.x + size.width > width {
                cursor.x = 0
                cursor.y += lineHeight + lineSpacing
                lineHeight = 0
            }
            offsets.append(cursor)
            cursor.x += size.width + spacing
            widest = max(widest, cursor.x - spacing)
            lineHeight = max(lineHeight, size.height)
        }

        return (CGSize(width: widest, height: cursor.y + lineHeight), offsets)
    }
}
