//
//  OCRView.swift
//  RunAnywhereAI
//
//  UI for full-page text recognition over `RunAnywhere.ocr`. Pure SwiftUI:
//  model picker, image picker, quad overlay and transcript — no inference or
//  model logic lives here.
//

#if canImport(UIKit)
import SwiftUI
import PhotosUI
import UIKit

struct OCRView: View {
    @State private var viewModel = OCRViewModel()
    @State private var photoItem: PhotosPickerItem?
    @State private var showModelPicker = false

    private var hasModelSelected: Bool {
        viewModel.isModelLoaded
    }

    var body: some View {
        NavigationView {
            ZStack {
                if hasModelSelected {
                    ScrollView {
                        VStack(alignment: .leading, spacing: AppSpacing.mediumLarge) {
                            modelStatusCard
                            imageCard
                            if !viewModel.regions.isEmpty {
                                transcriptCard
                            }
                            if let error = viewModel.error {
                                errorBanner(error)
                            }
                            if !viewModel.statusMessage.isEmpty {
                                Text(viewModel.statusMessage)
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.textSecondary)
                            }
                        }
                        .padding(AppSpacing.mediumLarge)
                    }
                } else {
                    Spacer()
                }

                if !hasModelSelected && !viewModel.isProcessing {
                    ModelRequiredOverlay(modality: .ocr) {
                        showModelPicker = true
                    }
                }
            }
            .navigationTitle(hasModelSelected ? "Read Text" : "")
            #if os(iOS)
            .navigationBarTitleDisplayModeCompat(.inline)
            .navigationBarHidden(!hasModelSelected)
            #endif
            .toolbar {
                if hasModelSelected {
                    #if os(iOS)
                    ToolbarItem(placement: .navigationBarTrailing) {
                        modelButton
                    }
                    #else
                    ToolbarItem(placement: .automatic) {
                        modelButton
                    }
                    #endif
                }
            }
        }
        #if os(iOS)
        .navigationViewStyle(.stack)
        #endif
        .adaptiveSheet(isPresented: $showModelPicker) {
            ModelSelectionSheet(context: .ocr) { model in
                Task {
                    await viewModel.loadModelFromSelection(model)
                }
            }
        }
        .task { await viewModel.refreshModelStatus() }
        .onChange(of: photoItem) { _, newValue in
            guard let newValue else { return }
            Task {
                if let data = try? await newValue.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    viewModel.setImage(image)
                }
            }
        }
    }

    // MARK: - Model

    private var modelButton: some View {
        Button {
            showModelPicker = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "cube")
                    .font(AppTypography.system14)
                if let modelName = viewModel.loadedModelName {
                    Text(modelName)
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(1)
                } else {
                    Text("Select Model")
                        .font(.caption)
                }
            }
        }
    }

    private var modelStatusCard: some View {
        card {
            HStack {
                Text("Model")
                    .font(AppTypography.subheadlineMedium)
                    .foregroundColor(AppColors.textPrimary)
                Spacer()
                statusPill(ok: viewModel.isModelLoaded, text: "loaded")
            }
            if let name = viewModel.loadedModelName {
                Text(name)
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textSecondary)
            }
            Text("Nemotron-OCR v1 detector + recognizer, on the Neural Engine.")
                .font(AppTypography.caption)
                .foregroundColor(AppColors.textSecondary)
        }
    }

    // MARK: - Image

    private var imageCard: some View {
        card {
            Text("Page")
                .font(AppTypography.subheadlineMedium)
                .foregroundColor(AppColors.textPrimary)
            imagePreview
            PhotosPicker(selection: $photoItem, matching: .images) {
                Text(viewModel.sourceImage == nil ? "Pick image…" : "Change image…")
            }
            .buttonStyle(.bordered)

            Button {
                Task { await viewModel.runOCR() }
            } label: {
                if viewModel.isReading {
                    ProgressView()
                } else {
                    Text("Read text")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.isModelLoaded
                      || viewModel.sourceImage == nil
                      || viewModel.isReading)
        }
    }

    /// Shows the overlay in place of the source once a read has happened — the
    /// boxes are drawn onto a copy of the same image, so stacking both would
    /// just double-expose it.
    @ViewBuilder
    private var imagePreview: some View {
        if let displayed = viewModel.overlayImage ?? viewModel.sourceImage {
            Image(uiImage: displayed)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusRegular))
        } else {
            RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusRegular)
                .fill(Color(.tertiarySystemFill))
                .frame(height: 160)
                .overlay(
                    Text("No image selected")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.textSecondary)
                )
        }
    }

    // MARK: - Result

    private var transcriptCard: some View {
        card {
            HStack {
                Text("Text")
                    .font(AppTypography.subheadlineMedium)
                    .foregroundColor(AppColors.textPrimary)
                Spacer()
                if viewModel.processingTimeMs > 0 {
                    Text("\(viewModel.regions.count) regions · \(viewModel.processingTimeMs) ms")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.textSecondary)
                }
            }
            ForEach(Array(viewModel.regions.enumerated()), id: \.offset) { _, region in
                HStack(alignment: .firstTextBaseline) {
                    Text(region.text.isEmpty ? "—" : region.text)
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.textPrimary)
                        .textSelection(.enabled)
                    Spacer()
                    // Absent, not zero: a model that does not score its output
                    // is not a model that scored it zero.
                    if let confidence = region.confidence {
                        Text(String(format: "%.0f%%", confidence * 100))
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.textSecondary)
                    }
                }
            }
        }
    }

    // MARK: - Building blocks

    private func errorBanner(_ message: String) -> some View {
        Text(message)
            .font(AppTypography.caption)
            .foregroundColor(AppColors.statusRed)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppSpacing.small)
            .background(AppColors.statusRed.opacity(0.1),
                        in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusRegular))
    }

    private func statusPill(ok: Bool, text: String) -> some View {
        Text(text)
            .font(AppTypography.caption)
            .foregroundColor(ok ? AppColors.statusGreen : AppColors.statusGray)
            .padding(.horizontal, AppSpacing.small)
            .padding(.vertical, 2)
            .background((ok ? AppColors.statusGreen : AppColors.statusGray).opacity(0.12),
                        in: Capsule())
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.mediumLarge)
        .background(Color(.secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusRegular))
    }
}
#endif
