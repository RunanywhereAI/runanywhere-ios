import SwiftUI

struct DrawerEntry: Identifiable, Hashable {
    let id: String
    let title: String
    var symbol: String = "bubble.left"
}

struct DrawerFooterItem: Identifiable, Hashable {
    let id: String
    let title: String
    let symbol: String
}

enum SideNavTab: String, CaseIterable, Identifiable {
    case chat
    case workflow
    case models
    case settings

    var id: String { rawValue }

    static var available: [SideNavTab] {
        #if os(macOS)
        [.chat, .workflow, .models]
        #else
        [.chat, .models]
        #endif
    }

    var hasLibrary: Bool { self == .chat || self == .workflow }

    var title: String {
        switch self {
        case .chat: "Chat"
        case .workflow: "Workflow"
        case .models: "Manage Models"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .chat: "bubble.left.and.bubble.right"
        case .workflow: "point.3.filled.connected.trianglepath.dotted"
        case .models: "square.stack.3d.up"
        case .settings: "gearshape.fill"
        }
    }

    var searchPrompt: String {
        switch self {
        case .chat: "Search chats"
        case .workflow: "Search workflows"
        case .models, .settings: ""
        }
    }

    var sectionTitle: String {
        switch self {
        case .chat: "Recent"
        case .workflow: "Workflows"
        case .models, .settings: ""
        }
    }

    var emptyTitle: String {
        switch self {
        case .chat: "No chats yet"
        case .workflow: "No workflows yet"
        case .models, .settings: ""
        }
    }

    var emptyDetail: String {
        switch self {
        case .chat: "Start a new private conversation."
        case .workflow: "Build one to automate a task."
        case .models, .settings: ""
        }
    }

    var newTitle: String {
        switch self {
        case .chat: "New Chat"
        case .workflow: "New Workflow"
        case .models, .settings: ""
        }
    }
}

struct SideNav<Content: View>: View {
    @Binding var isOpen: Bool
    let chats: [DrawerEntry]
    let workflows: [DrawerEntry]
    let footer: [DrawerFooterItem]
    @Binding var selection: String
    @Binding var tab: SideNavTab
    var onNew: () -> Void = {}
    var onDelete: (String) -> Void = { _ in }
    var onRename: (String, String) -> Void = { _, _ in }
    var onFooter: (String) -> Void = { _ in }
    let content: Content

    init(
        isOpen: Binding<Bool>,
        chats: [DrawerEntry],
        workflows: [DrawerEntry],
        footer: [DrawerFooterItem],
        selection: Binding<String>,
        tab: Binding<SideNavTab>,
        onNew: @escaping () -> Void = {},
        onDelete: @escaping (String) -> Void = { _ in },
        onRename: @escaping (String, String) -> Void = { _, _ in },
        onFooter: @escaping (String) -> Void = { _ in },
        @ViewBuilder content: () -> Content
    ) {
        self._isOpen = isOpen
        self.chats = chats
        self.workflows = workflows
        self.footer = footer
        self._selection = selection
        self._tab = tab
        self.onNew = onNew
        self.onDelete = onDelete
        self.onRename = onRename
        self.onFooter = onFooter
        self.content = content()
    }

    @State private var query = ""
    @State private var hovered: String?
    @State private var renaming: String?
    @State private var draftTitle = ""

    private let expandedWidth: CGFloat = 300
    private let railWidth: CGFloat = 56

    private var source: [DrawerEntry] {
        tab == .chat ? chats : workflows
    }

    private var filtered: [DrawerEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return source }
        return source.filter { $0.title.localizedCaseInsensitiveContains(trimmed) }
    }

    var body: some View {
        #if os(macOS)
        sidebarLayout
        #else
        drawerLayout
        #endif
    }

    #if os(macOS)
    private var sidebarLayout: some View {
        HStack(spacing: 0) {
            Group {
                if isOpen { expanded } else { rail }
            }
            .frame(width: isOpen ? expandedWidth : railWidth)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(AppColors.surfaceMuted)
            .ignoresSafeArea(edges: .bottom)

            Rectangle()
                .fill(AppColors.border)
                .frame(width: Stroke.hairline)
                .ignoresSafeArea(edges: .bottom)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(.easeOut(duration: 0.22), value: isOpen)
    }
    #else
    private var drawerLayout: some View {
        ZStack(alignment: .leading) {
            content

            if isOpen {
                Color.black.opacity(0.32)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture { isOpen = false }
            }

            expanded
                .frame(width: expandedWidth)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(AppColors.surfaceMuted)
                .ignoresSafeArea(edges: .bottom)
                .offset(x: isOpen ? 0 : -expandedWidth)
        }
        .animation(.easeOut(duration: 0.24), value: isOpen)
    }
    #endif

    private var expanded: some View {
        VStack(spacing: 0) {
            header
            tabCards

            if tab.hasLibrary {
                search
                newButton

                Text(tab.sectionTitle)
                    .appType(.overline)
                    .foregroundStyle(AppColors.textSecondary)
                    .textCase(.uppercase)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Space.lg)
                    .padding(.top, Space.sm)
                    .id(tab)
                    .transition(.opacity)

                list
            } else {
                Spacer(minLength: 0)
            }

            Divider().overlay(AppColors.border)

            VStack(spacing: 0) {
                ForEach(footer) { item in
                    footerRow(item)
                }
            }
            .padding(.bottom, footerBottomInset)
        }
    }

    private var footerBottomInset: CGFloat {
        #if os(macOS)
        0
        #else
        Space.xl
        #endif
    }

    private var newButton: some View {
        Button(action: onNew) {
            HStack(spacing: Space.sm) {
                Image(systemName: "plus")
                    .glyph(Glyph.xs, weight: .semibold)
                    .frame(width: Glyph.lg)

                Text(tab.newTitle)
                    .appType(.secondary)

                Spacer(minLength: 0)
            }
            .foregroundStyle(AppColors.brand)
            .padding(.horizontal, Space.md)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(AppColors.brandMuted)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .strokeBorder(
                        AppColors.brand.opacity(0.55),
                        style: StrokeStyle(lineWidth: Stroke.regular, dash: [4, 3])
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.newTitle)
        .padding(.horizontal, Space.lg)
        .padding(.bottom, Space.sm)
        .id(tab)
        .transition(.opacity)
    }

    private var tabCards: some View {
        VStack(spacing: 0) {
            ForEach(Array(SideNavTab.available.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Divider().overlay(AppColors.border)
                }
                tabCard(item)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(AppColors.border, lineWidth: Stroke.hairline)
        )
        .padding(.horizontal, Space.lg)
        .padding(.bottom, Space.xl)
    }

    private func tabCard(_ item: SideNavTab) -> some View {
        let isActive = tab == item
        return Button {
            select(item)
        } label: {
            HStack(spacing: Space.md) {
                Image(systemName: item.symbol)
                    .glyph(Glyph.xs)
                    .foregroundStyle(isActive ? AppColors.onBrand : AppColors.textSecondary)
                    .frame(width: Glyph.lg)

                Text(item.title)
                    .appType(.secondary)
                    .fontWeight(isActive ? .semibold : .regular)
                    .foregroundStyle(isActive ? AppColors.onBrand : AppColors.textPrimary)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, Space.md)
            .frame(height: 36)
            .background(isActive ? AppColors.brandSelected : AppColors.surface)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private func select(_ item: SideNavTab) {
        guard tab != item else { return }
        withAnimation(.easeInOut(duration: 0.22)) {
            tab = item
            query = ""
        }
    }

    private var rail: some View {
        VStack(spacing: Space.xs) {
            railButton(symbol: "sidebar.left", title: "Expand sidebar", isSelected: false) {
                isOpen = true
            }
            .frame(height: Measure.barHeight)

            ForEach(SideNavTab.available) { item in
                railButton(symbol: item.symbol, title: item.title, isSelected: tab == item, size: Glyph.sm) {
                    select(item)
                }
            }

            if tab.hasLibrary {
                    railButton(symbol: "plus", title: tab.newTitle, isSelected: false, size: Glyph.sm, action: onNew)
            }

            Divider().overlay(AppColors.border)

            ScrollView {
                VStack(spacing: Space.xs) {
                    ForEach(tab.hasLibrary ? source : []) { entry in
                        railButton(
                            symbol: entry.symbol,
                            title: entry.title,
                            isSelected: selection == entry.id
                        ) {
                            selection = entry.id
                        }
                    }
                }
                .padding(.top, Space.xs)
            }
            .scrollIndicators(.hidden)

            Divider().overlay(AppColors.border)

            ForEach(footer) { item in
                railButton(
                    symbol: item.symbol,
                    title: item.title,
                    isSelected: false
                ) {
                    onFooter(item.id)
                }
            }
            .padding(.bottom, Space.xs)
        }
    }

    private func railButton(
        symbol: String,
        title: String,
        isSelected: Bool,
        size: CGFloat = Glyph.md,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .glyph(size)
                .foregroundStyle(isSelected ? AppColors.onBrand : AppColors.textSecondary)
                .frame(width: 38, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(isSelected ? AppColors.brandSelected : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }

    private var closeSymbol: String {
        #if os(macOS)
        "sidebar.left"
        #else
        "xmark"
        #endif
    }

    private var header: some View {
        TopBar(
            title: "RunAnywhere",
            trailing: AnyView(
                Button { isOpen = false } label: {
                    Image(systemName: closeSymbol)
                        .glyph(Glyph.sm, weight: .semibold)
                        .foregroundStyle(AppColors.textSecondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            )
        )
        .frame(height: Measure.barHeight)
        .padding(.bottom, Space.md)
    }

    private var search: some View {
        HStack(spacing: Space.sm) {
            Image(systemName: "magnifyingglass")
                .glyph(Glyph.sm)
                .foregroundStyle(AppColors.textSecondary)

            TextField(tab.searchPrompt, text: $query)
                .textFieldStyle(.plain)
                .appType(.secondary)
                .foregroundStyle(AppColors.textPrimary)
                .id(tab)
                .transition(.opacity)

            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .glyph(Glyph.sm)
                        .foregroundStyle(AppColors.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.xs)
        .frame(height: 30)
        .background(
            Capsule().fill(AppColors.background)
        )
        .padding(.horizontal, Space.lg)
        .padding(.bottom, Space.sm)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Space.xs) {
                if filtered.isEmpty {
                    empty
                } else {
                    ForEach(filtered) { entry in
                        row(entry)
                    }
                }
            }
            .padding(.horizontal, Space.sm)
            .padding(.top, Space.xs)
        }
        .id(tab)
        .transition(.opacity)
    }

    @ViewBuilder
    private func row(_ entry: DrawerEntry) -> some View {
        if renaming == entry.id {
            renameField(entry)
        } else {
            conversationRow(entry)
        }
    }

    private func conversationRow(_ entry: DrawerEntry) -> some View {
        let isSelected = selection == entry.id
        let isHovered = hovered == entry.id

        return Button {
            selection = entry.id
        } label: {
            HStack(spacing: Space.xs) {
                Text(entry.title)
                    .appType(.secondary)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)

                if isHovered {
                    rowAction(symbol: "pencil", label: "Rename") {
                        draftTitle = entry.title
                        renaming = entry.id
                    }
                    rowAction(symbol: "trash", label: "Delete", tint: AppColors.danger) {
                        onDelete(entry.id)
                    }
                }
            }
            .padding(.horizontal, Space.md)
            .padding(.vertical, Space.sm)
            .frame(minHeight: Measure.hitTarget - Space.md)
            .background(rowBackground(isSelected: isSelected, isHovered: isHovered))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            withAnimation(.easeOut(duration: 0.14)) {
                hovered = inside ? entry.id : (hovered == entry.id ? nil : hovered)
            }
        }
        .contextMenu {
            Button("Rename") {
                draftTitle = entry.title
                renaming = entry.id
            }
            Button("Delete", role: .destructive) { onDelete(entry.id) }
        }
    }

    /// Hovering lifts the row onto its own card so the two actions have
    /// somewhere to sit. Selection keeps the brand wash and wins over hover,
    /// otherwise pointing at another row makes the current one look unselected.
    @ViewBuilder
    private func rowBackground(isSelected: Bool, isHovered: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
        if isSelected {
            shape.fill(AppColors.brandMuted)
        } else if isHovered {
            shape.fill(AppColors.surface)
                .overlay(shape.strokeBorder(AppColors.border, lineWidth: Stroke.hairline))
        } else {
            shape.fill(.clear)
        }
    }

    private func rowAction(
        symbol: String,
        label: String,
        tint: Color = AppColors.textSecondary,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .glyph(Glyph.xs)
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
        .transition(.opacity)
    }

    @ViewBuilder
    private func renameField(_ entry: DrawerEntry) -> some View {
        let field = TextField("Name", text: $draftTitle)
            .textFieldStyle(.plain)
            .appType(.secondary)
            .foregroundStyle(AppColors.textPrimary)
            .padding(.horizontal, Space.md)
            .padding(.vertical, Space.sm)
            .frame(minHeight: Measure.hitTarget - Space.md)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(AppColors.background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(AppColors.brand.opacity(0.55), lineWidth: Stroke.hairline)
            )
            .onSubmit { commitRename(entry) }

        // Escape-to-cancel is a Mac gesture; `onExitCommand` does not exist on
        // iOS, where tapping elsewhere ends editing instead.
        #if os(macOS)
        field.onExitCommand { renaming = nil }
        #else
        field
        #endif
    }

    private func commitRename(_ entry: DrawerEntry) {
        let trimmed = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed != entry.title {
            onRename(entry.id, trimmed)
        }
        renaming = nil
    }

    private var empty: some View {
        EmptyState(
            symbol: query.isEmpty ? tab.symbol : "magnifyingglass",
            title: query.isEmpty ? tab.emptyTitle : "Nothing found",
            detail: query.isEmpty ? tab.emptyDetail : "Try a different keyword."
        )
    }

    private func footerRow(_ item: DrawerFooterItem) -> some View {
        Button {
            onFooter(item.id)
        } label: {
            HStack(spacing: Space.md) {
                Image(systemName: item.symbol)
                    .glyph(Glyph.sm, weight: .semibold)
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(width: Glyph.lg)

                Text(item.title)
                    .appType(.secondary)
                    .foregroundStyle(AppColors.textPrimary)

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .glyph(Glyph.sm)
                    .foregroundStyle(AppColors.textTertiary)
            }
            .padding(.horizontal, Space.lg)
            .padding(.vertical, Space.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
