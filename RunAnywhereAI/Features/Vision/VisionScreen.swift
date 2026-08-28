import AVFoundation
import SwiftUI
#if os(iOS)
import PhotosUI
import UIKit
#endif
#if os(macOS)
import AppKit
#endif

struct VisionScreen: View {
    @Environment(ModelStore.self) private var store
    @State private var viewModel = VisionViewModel()
    @State private var isPickingModel = false
    @State private var isImporting = false
    @State private var isDropTargeted = false
    #if os(iOS)
    @State private var photo: PhotosPickerItem?
    #endif

    /// The viewfinder keeps its own height: tall enough to frame a scene, short
    /// enough that the answer is still on screen on a phone.
    private let subjectMinHeight: CGFloat = 200
    private let subjectMaxHeight: CGFloat = 340

    var body: some View {
        @Bindable var model = viewModel

        VStack(spacing: Space.lg) {
            header
            subject
            controls
            question(binding: $model.prompt)
            answer
        }
        .padding(Space.lg)
        .measured()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background)
        .task { await viewModel.start(store: store) }
        .task(id: viewModel.isLive) {
            guard viewModel.isLive else { return }
            await viewModel.runLiveLoop()
        }
        .onDisappear { viewModel.leave() }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: AttachmentLoader.imageTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { load(url) }
            case .failure(let error):
                viewModel.notice = error.localizedDescription
            }
        }
        #if os(iOS)
        .onChange(of: photo) { _, item in
            guard let item else { return }
            loadPhoto(item)
        }
        #endif
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: Space.md) {
            ModelBadge(state: viewModel.modelState) { isPickingModel = true }
                .modelPicker(
                    isPresented: $isPickingModel,
                    models: store.installed.filter { $0.purpose == .vision },
                    activeID: activeModelID,
                    onSelect: { model in Task { await viewModel.load(model, store: store) } },
                    onManage: {
                        viewModel.notice = "Vision models are downloaded in Manage Models, in the sidebar."
                    }
                )

            Spacer(minLength: Space.sm)

            liveToggle
        }
    }

    private var activeModelID: String? { viewModel.loadedModelID }

    private var liveToggle: some View {
        Button {
            viewModel.isLive.toggle()
        } label: {
            HStack(spacing: Space.xs) {
                Circle()
                    .fill(viewModel.isLive ? AppColors.brand : AppColors.textTertiary)
                    .frame(width: 7, height: 7)
                Text("Live")
                    .appType(.meta)
                    .fontWeight(.semibold)
            }
            .foregroundStyle(viewModel.isLive ? AppColors.brand : AppColors.textSecondary)
            .padding(.horizontal, Space.md)
            .frame(height: 28)
            .background(Capsule().fill(viewModel.isLive ? AppColors.brandMuted : AppColors.surfaceMuted))
            .overlay(Capsule().strokeBorder(AppColors.border, lineWidth: Stroke.hairline))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.isModelReady || viewModel.still != nil)
        .opacity(viewModel.isModelReady && viewModel.still == nil ? 1 : 0.4)
        .accessibilityLabel("Live, re-ask every \(VisionViewModel.liveIntervalLabel)")
    }

    // MARK: - Subject

    private var subject: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
        return ZStack {
            shape.fill(AppColors.surfaceMuted)
            subjectContent
        }
        .frame(minHeight: subjectMinHeight, maxHeight: subjectMaxHeight)
        .clipShape(shape)
        .overlay(
            shape.strokeBorder(
                isDropTargeted ? AppColors.brand : AppColors.border,
                lineWidth: isDropTargeted ? Stroke.heavy : Stroke.hairline
            )
        )
        .overlay(alignment: .topLeading) { stillLabel }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            load(url)
            return true
        } isTargeted: { isDropTargeted = $0 }
    }

    @ViewBuilder
    private var subjectContent: some View {
        if let still = viewModel.still {
            still.preview
                .resizable()
                .scaledToFit()
        } else if let session = viewModel.captureSession, viewModel.cameraStatus == .ready {
            VisionCameraPreview(session: session)
        } else {
            EmptyState(symbol: waiting.symbol, title: waiting.title, detail: waiting.detail)
        }
    }

    private var waiting: (symbol: String, title: String, detail: String) {
        guard viewModel.isModelReady else {
            return (
                "eye",
                "No vision model loaded",
                "Choose one above to ask about the camera, a photo, or a picture you drop here."
            )
        }
        switch viewModel.cameraStatus {
        case .idle:
            return ("camera", "Camera off", "Start it below, or choose an image instead.")
        case .requestingAccess:
            return ("camera", "Waiting for permission", "Allow camera access to use the viewfinder.")
        case .ready:
            return ("camera", "Starting the camera", "The first frame is on its way.")
        case .denied:
            return (
                "camera.badge.ellipsis",
                "Camera access is off",
                "Turn it on in privacy settings, or choose an image instead."
            )
        case .restricted:
            return (
                "lock",
                "Camera access is restricted",
                "A policy on this device forbids it. Choose an image instead."
            )
        case .unavailable(let reason):
            return ("camera.badge.ellipsis", "No camera", reason)
        }
    }

    @ViewBuilder
    private var stillLabel: some View {
        if let still = viewModel.still {
            Text(still.filename)
                .appType(.caption)
                .foregroundStyle(AppColors.textSecondary)
                .lineLimit(1)
                .padding(.horizontal, Space.sm)
                .frame(height: 22)
                .background(Capsule().fill(AppColors.surface))
                .padding(Space.sm)
        }
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(spacing: Space.sm) {
                #if os(iOS)
                PhotosPicker(selection: $photo, matching: .images) {
                    PillLabel(title: "Photos", symbol: "photo.on.rectangle")
                }
                .buttonStyle(.plain)
                #endif

                PillButton(title: "Choose Image", symbol: "folder") { isImporting = true }

                if viewModel.still != nil {
                    PillButton(title: "Use Camera", symbol: "camera") {
                        Task { await viewModel.clearStill() }
                    }
                }

                if viewModel.still == nil, viewModel.isModelReady {
                    cameraRecovery
                }

                Spacer(minLength: 0)
            }

            if let notice = viewModel.notice {
                Text(notice)
                    .appType(.meta)
                    .foregroundStyle(AppColors.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var cameraRecovery: some View {
        switch viewModel.cameraStatus {
        case .denied, .restricted:
            PillButton(title: "Privacy Settings", symbol: "gearshape", tint: AppColors.accent) {
                openPrivacySettings()
            }
        case .unavailable, .idle:
            PillButton(title: "Start Camera", symbol: "camera") {
                Task { await viewModel.retryCamera() }
            }
        case .ready, .requestingAccess:
            EmptyView()
        }
    }

    // MARK: - Question

    private func question(binding: Binding<String>) -> some View {
        HStack(spacing: Space.sm) {
            TextField("Ask about the picture", text: binding, axis: .vertical)
                .textFieldStyle(.plain)
                .appType(.body)
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1...3)
                .padding(.horizontal, Space.md)
                .padding(.vertical, Space.sm)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(AppColors.surfaceMuted)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(AppColors.border, lineWidth: Stroke.hairline)
                )
                .onSubmit(viewModel.ask)

            if viewModel.isAsking {
                PillButton(title: "Stop", symbol: "stop.fill", tint: AppColors.danger, fill: AppColors.dangerMuted) {
                    viewModel.cancel()
                }
            } else {
                PillButton(
                    title: "Ask",
                    symbol: "sparkles",
                    tint: AppColors.brand,
                    fill: AppColors.brandMuted,
                    isEnabled: viewModel.canAsk,
                    action: viewModel.ask
                )
            }
        }
    }

    // MARK: - Answer

    private var answer: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            ScrollView {
                Text(viewModel.answer.isEmpty ? "The answer appears here." : viewModel.answer)
                    .appType(.body)
                    .foregroundStyle(viewModel.answer.isEmpty ? AppColors.textTertiary : AppColors.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .defaultScrollAnchor(.bottom)

            if let line = statusLine {
                Text(line.text)
                    .appType(.meta)
                    .foregroundStyle(line.tint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Space.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .card()
    }

    private var statusLine: (text: String, tint: Color)? {
        switch viewModel.status {
        case .idle:
            return nil
        case .running:
            let text = viewModel.isLive
                ? "Looking, every \(VisionViewModel.liveIntervalLabel)…"
                : "Looking…"
            return (text, AppColors.info)
        case .answered(let tokens, let rate):
            guard tokens > 0 else { return ("Answered.", AppColors.textSecondary) }
            return ("\(tokens) tokens · \(String(format: "%.1f", rate)) tok/s", AppColors.textSecondary)
        case .silent:
            return ("The model finished without saying anything.", AppColors.textSecondary)
        case .cancelled:
            return ("Stopped.", AppColors.textSecondary)
        case .failed(let reason):
            return (reason, AppColors.danger)
        }
    }

    // MARK: - Loading a still

    private func load(_ url: URL) {
        Task {
            do {
                viewModel.use(try await AttachmentLoader.load(from: url))
            } catch {
                viewModel.notice = error.localizedDescription
            }
        }
    }

    #if os(iOS)
    private func loadPhoto(_ item: PhotosPickerItem) {
        Task {
            defer { photo = nil }
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    viewModel.notice = "That photo could not be read."
                    return
                }
                viewModel.use(
                    ChatAttachment(filename: "Photo", byteCount: data.count, payload: .image(data))
                )
            } catch {
                viewModel.notice = error.localizedDescription
            }
        }
    }
    #endif

    private func openPrivacySettings() {
        #if os(iOS)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
        #elseif os(macOS)
        let path = "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera"
        guard let url = URL(string: path) else { return }
        NSWorkspace.shared.open(url)
        #endif
    }
}
