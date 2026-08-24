#if os(iOS)
import PhotosUI
import RunAnywhere
import SwiftUI
import UIKit

struct SegmentationScreen: View {
    @Environment(ModelStore.self) private var store
    @State private var viewModel = SegmentationViewModel()
    @State private var isPickingModel = false
    @State private var photo: PhotosPickerItem?
    @State private var showsMask = true

    /// Enough of the mask to read the regions, enough of the photograph to
    /// recognise what they are.
    private let maskOpacity = 0.55
    /// The share of a row tinted behind it is the class's share of the picture,
    /// faint enough to stay behind the text.
    private let rowBarOpacity = 0.14
    private let pictureMinHeight: CGFloat = 220
    private let pictureMaxHeight: CGFloat = 420
    private let percentColumnWidth: CGFloat = 52

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                header
                picture
                controls
                if !viewModel.classes.isEmpty { breakdown }
                if let line = statusLine {
                    Text(line.text)
                        .appType(.meta)
                        .foregroundStyle(line.tint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(Space.lg)
            .measured()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background)
        .task { await viewModel.start(store: store) }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            loadPhoto(item)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: Space.md) {
            ModelBadge(state: viewModel.modelState) { isPickingModel = true }
                .modelPicker(
                    isPresented: $isPickingModel,
                    models: candidates,
                    activeID: viewModel.loadedModelID,
                    onSelect: { model in Task { await viewModel.load(model, store: store) } },
                    onManage: {
                        viewModel.notice = "Segmentation models are downloaded in Manage Models, in the sidebar."
                    }
                )

            Spacer(minLength: Space.sm)

            if let label = viewModel.sourceLabel {
                Text(label)
                    .appType(.caption)
                    .foregroundStyle(AppColors.textSecondary)
                    .monospacedDigit()
            }
        }
    }

    /// The registry, not the display label: `ModelInfo.category` is the only
    /// place segmentation is named as a kind rather than as a word.
    private var candidates: [InstalledModel] {
        let ids = Set(store.raw.filter { $0.category == .semanticSegmentation }.map(\.id))
        return store.installed.filter { ids.contains($0.id) }
    }

    // MARK: - Picture

    private var picture: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
        return ZStack {
            shape.fill(AppColors.surfaceMuted)

            if let source = viewModel.source {
                ZStack {
                    Image(uiImage: source)
                        .resizable()
                        .scaledToFit()

                    if showsMask, let mask = viewModel.mask {
                        Image(uiImage: mask)
                            .resizable()
                            .scaledToFit()
                            .opacity(maskOpacity)
                    }
                }
            } else {
                EmptyState(
                    symbol: "photo",
                    title: viewModel.isModelReady ? "No picture yet" : "No segmentation model loaded",
                    detail: viewModel.isModelReady
                        ? "Choose one from your library, then run the model over it."
                        : "Choose one above to label every region of a picture."
                )
            }
        }
        .frame(minHeight: pictureMinHeight, maxHeight: pictureMaxHeight)
        .clipShape(shape)
        .overlay(shape.strokeBorder(AppColors.border, lineWidth: Stroke.hairline))
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(spacing: Space.sm) {
                PhotosPicker(selection: $photo, matching: .images) {
                    PillLabel(
                        title: viewModel.source == nil ? "Choose Picture" : "Change Picture",
                        symbol: "photo.on.rectangle"
                    )
                }
                .buttonStyle(.plain)

                if viewModel.mask != nil {
                    PillButton(
                        title: "Mask",
                        symbol: showsMask ? "eye" : "eye.slash",
                        tint: showsMask ? AppColors.brand : AppColors.textSecondary,
                        fill: showsMask ? AppColors.brandMuted : AppColors.surfaceMuted
                    ) {
                        showsMask.toggle()
                    }
                }

                Spacer(minLength: 0)

                PillButton(
                    title: viewModel.isRunning ? "Running…" : "Run",
                    symbol: "square.on.square.dashed",
                    tint: AppColors.brand,
                    fill: AppColors.brandMuted,
                    isEnabled: viewModel.canRun
                ) {
                    Task { await viewModel.run() }
                }
            }

            if let notice = viewModel.notice {
                Text(notice)
                    .appType(.meta)
                    .foregroundStyle(AppColors.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Breakdown

    private var breakdown: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text("Classes")
                .appType(.overline)
                .textCase(.uppercase)
                .foregroundStyle(AppColors.textSecondary)

            VStack(spacing: 0) {
                ForEach(viewModel.classes, id: \.classId) { summary in
                    row(summary)

                    if summary.classId != viewModel.classes.last?.classId {
                        Divider().overlay(AppColors.border)
                    }
                }
            }
            .card()
        }
    }

    private func row(_ summary: ClassInfo) -> some View {
        let tint = SegmentationViewModel.tint(for: summary.classId)
        return HStack(spacing: Space.md) {
            RoundedRectangle(cornerRadius: Radius.xs - 2, style: .continuous)
                .fill(tint)
                .frame(width: Glyph.xs, height: Glyph.xs)

            Text(summary.label.isEmpty ? "Class \(summary.classId)" : summary.label)
                .appType(.secondary)
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1)

            Spacer(minLength: Space.sm)

            Text("\(summary.pixelCount.formatted()) px")
                .appType(.caption)
                .foregroundStyle(AppColors.textTertiary)
                .monospacedDigit()

            Text(String(format: "%.1f%%", summary.fraction * 100))
                .appType(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(AppColors.textSecondary)
                .monospacedDigit()
                .frame(width: percentColumnWidth, alignment: .trailing)
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.sm)
        .background(alignment: .leading) {
            GeometryReader { proxy in
                tint.opacity(rowBarOpacity)
                    .frame(width: proxy.size.width * CGFloat(summary.fraction))
            }
        }
    }

    // MARK: - Status

    private var statusLine: (text: String, tint: Color)? {
        switch viewModel.status {
        case .idle:
            return nil
        case .running:
            return ("Labelling every pixel…", AppColors.info)
        case .done(let classes, let milliseconds):
            return ("\(classes) classes in \(milliseconds) ms", AppColors.textSecondary)
        case .failed(let reason):
            return (reason, AppColors.danger)
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem) {
        Task {
            defer { photo = nil }
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else {
                    viewModel.notice = "That picture could not be read."
                    return
                }
                viewModel.use(image)
            } catch {
                viewModel.notice = error.localizedDescription
            }
        }
    }
}

private struct PillLabel: View {
    let title: String
    var symbol: String?
    var tint: Color = AppColors.textPrimary
    var fill: Color = AppColors.surfaceMuted

    var body: some View {
        HStack(spacing: Space.xs) {
            if let symbol {
                Image(systemName: symbol)
                    .glyph(Glyph.xs, weight: .semibold)
            }
            Text(title)
                .appType(.meta)
                .fontWeight(.semibold)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, Space.md)
        .frame(height: 32)
        .background(Capsule().fill(fill))
        .overlay(Capsule().strokeBorder(AppColors.border, lineWidth: Stroke.hairline))
        .contentShape(Capsule())
    }
}

private struct PillButton: View {
    let title: String
    var symbol: String?
    var tint: Color = AppColors.textPrimary
    var fill: Color = AppColors.surfaceMuted
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            PillLabel(title: title, symbol: symbol, tint: tint, fill: fill)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
    }
}
#endif
