import SwiftUI
import RunAnywhere
import UniformTypeIdentifiers

#if os(iOS)
import PhotosUI
#endif

struct ComputerUseScreen: View {
    @Environment(ModelStore.self) private var store
    @State private var model = ComputerUseViewModel()
    @State private var isImporting = false

    #if os(iOS)
    @State private var photo: PhotosPickerItem?
    #endif

    /// Tall enough to read a screenshot's own interface without pushing the
    /// goal field below the fold.
    private let canvasHeight = Measure.content / 2

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                ComputerUseModelCard(store: store, model: model)

                if model.profile != nil {
                    ScreenSection(title: "Screenshot") { canvas }
                    ScreenSection(title: "Goal") { goal }
                    if model.isRunning || !model.rawOutput.isEmpty || model.action != nil {
                        ScreenSection(title: "Parsed action") { result }
                    }
                }
            }
            .padding(Space.lg)
            .measured()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background)
        .task { await model.refreshLoadedModel(store: store) }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.image]) { result in
            adopt(result)
        }
        #if os(iOS)
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = ComputerUseImage(data: data) else { return }
                model.screenshot = image
                model.clearResult()
            }
        }
        #endif
    }

    // MARK: - Screenshot

    private var canvas: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            if let screenshot = model.screenshot {
                marked(screenshot)
            } else {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(AppColors.surfaceMuted)
                    .frame(height: canvasHeight / 2)
                    .overlay(
                        Text("Pick a screenshot for the agent to look at")
                            .appType(.meta)
                            .foregroundStyle(AppColors.textSecondary)
                    )
            }

            picker
        }
        .padding(Space.md)
        .card()
    }

    private func marked(_ screenshot: ComputerUseImage) -> some View {
        let size = ComputerUseViewModel.pixelSize(of: screenshot)
        let ratio = size.height > 0 ? CGFloat(size.width) / CGFloat(size.height) : 1

        return ZStack(alignment: .topLeading) {
            image(screenshot)
                .resizable()

            // The SDK already scaled the coordinate into the screenshot's own
            // pixel space, so the only mapping left is pixels to drawn points.
            if let action = model.action,
               action.isValid,
               let point = action.coordinate,
               size.width > 0, size.height > 0 {
                GeometryReader { geo in
                    marker
                        .position(
                            x: geo.size.width * CGFloat(point.x) / CGFloat(size.width),
                            y: geo.size.height * CGFloat(point.y) / CGFloat(size.height)
                        )
                }
            }
        }
        .aspectRatio(ratio, contentMode: .fit)
        .frame(maxWidth: .infinity, maxHeight: canvasHeight)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var marker: some View {
        ZStack {
            Circle()
                .strokeBorder(AppColors.brand, lineWidth: Stroke.heavy)
                .frame(width: Glyph.hero, height: Glyph.hero)
            Circle()
                .fill(AppColors.brand)
                .frame(width: Space.sm, height: Space.sm)
        }
        .shadow(radius: Space.hair)
        .accessibilityLabel("Target of the parsed action")
    }

    @ViewBuilder
    private var picker: some View {
        let title = model.screenshot == nil ? "Choose screenshot" : "Change screenshot"

        // Screenshots on a Mac land on the Desktop, not in the photo library,
        // so the file importer is the only affordance that finds them there.
        #if os(macOS)
        PillButton(title: title, symbol: "photo", tint: AppColors.brand, fill: AppColors.brandMuted) {
            isImporting = true
        }
        #else
        PhotosPicker(selection: $photo, matching: .images) {
            PillLabel(title: title, symbol: "photo", tint: AppColors.brand, fill: AppColors.brandMuted)
        }
        .buttonStyle(.plain)
        #endif
    }

    // MARK: - Goal

    private var goal: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            TextField("What should the agent do?", text: $model.goal, axis: .vertical)
                .textFieldStyle(.plain)
                .appType(.body)
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1...3)
                .padding(Space.md)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(AppColors.surfaceMuted)
                )

            HStack(spacing: Space.sm) {
                if model.isRunning {
                    PillButton(
                        title: "Stop",
                        symbol: "stop.fill",
                        tint: AppColors.danger,
                        fill: AppColors.dangerMuted
                    ) {
                        model.cancel()
                    }
                    ProgressView()
                        .controlSize(.small)
                } else {
                    PillButton(
                        title: "Run one step",
                        symbol: "play.fill",
                        tint: AppColors.brand,
                        fill: AppColors.brandMuted,
                        isEnabled: model.canRun
                    ) {
                        model.run()
                    }
                }

                Spacer(minLength: 0)
            }

            if let status = model.status {
                Text(status)
                    .appType(.meta)
                    .foregroundStyle(AppColors.textSecondary)
            }

            if let error = model.lastError {
                Text(error)
                    .appType(.meta)
                    .foregroundStyle(AppColors.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Space.md)
        .card()
    }

    // MARK: - Result

    private var result: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            if let action = model.action, action.isValid {
                detail(action)
            } else if !model.isRunning {
                Text("No tool call came back in the model's reply.")
                    .appType(.meta)
                    .foregroundStyle(AppColors.textSecondary)
            }

            DisclosureGroup("Raw model output") {
                Text(model.rawOutput.isEmpty ? "…" : model.rawOutput)
                    .appType(.mono)
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(.top, Space.sm)
            }
            .appType(.meta)
            .tint(AppColors.textSecondary)
        }
        .padding(Space.md)
        .card()
    }

    private func detail(_ action: CuaAction) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(spacing: Space.sm) {
                GlyphTile(symbol: action.kind.symbol)

                Text(action.kind.title)
                    .appType(.sectionTitle)
                    .foregroundStyle(AppColors.textPrimary)

                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: Space.xs) {
                if let point = action.coordinate {
                    field("Coordinate", "\(point.x), \(point.y) px")
                }
                if let label = action.kind.textLabel, !action.text.isEmpty {
                    field(label, action.text)
                }
                if action.scrollX != 0 || action.scrollY != 0 {
                    field("Scroll", "\(action.scrollX), \(action.scrollY)")
                }
                if action.waitSeconds != 0 {
                    field("Wait", "\(action.waitSeconds)s")
                }
            }

            if !action.reasoning.isEmpty {
                Text(action.reasoning)
                    .appType(.secondary)
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(Space.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .fill(AppColors.surfaceMuted)
                    )
            }
        }
    }

    private func field(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: Space.md) {
            Text(label)
                .appType(.meta)
                .foregroundStyle(AppColors.textSecondary)
                .frame(width: 92, alignment: .leading)
            Text(value)
                .appType(.meta)
                .foregroundStyle(AppColors.textPrimary)
                .textSelection(.enabled)
        }
    }

    // MARK: - Chrome

    private func adopt(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else {
            if case .failure(let error) = result { model.report(error) }
            return
        }
        // Sandboxed: a picked URL is only readable inside a security-scoped session.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url),
              let image = ComputerUseImage(data: data) else { return }
        model.screenshot = image
        model.clearResult()
    }

    private func image(_ screenshot: ComputerUseImage) -> Image {
        #if canImport(UIKit)
        Image(uiImage: screenshot)
        #else
        Image(nsImage: screenshot)
        #endif
    }
}
