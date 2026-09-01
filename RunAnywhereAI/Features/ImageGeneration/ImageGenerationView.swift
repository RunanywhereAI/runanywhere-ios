//
//  ImageGenerationView.swift
//  RunAnywhereAI
//
//  UI for text-to-image (CoreML Stable Diffusion) over `RunAnywhere.images`.
//  Pure SwiftUI: model picker, prompt fields, and the painted result — no
//  inference or model logic lives here.
//
//  Cross-platform on purpose: no PhotosPicker, no UIImage, and design-system
//  surface tokens instead of `Color(.secondarySystemBackground)`, so the same
//  file serves iOS and macOS.
//

import SwiftUI
import RunAnywhere

struct ImageGenerationView: View {
    @State private var viewModel = ImageGenerationViewModel()
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
                            promptCard
                            resultCard
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
                    ModelRequiredOverlay(modality: .imageGeneration) {
                        showModelPicker = true
                    }
                }
            }
            .navigationTitle(hasModelSelected ? "Image Generation" : "")
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
            ModelSelectionSheet(context: .imageGeneration) { model in
                Task {
                    await viewModel.loadModelFromSelection(model)
                }
            }
        }
        .task { await viewModel.refreshModelStatus() }
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
            Text("Stable Diffusion 1.5 (CoreML) — download from the catalog, then Use.")
                .font(AppTypography.caption)
                .foregroundColor(AppColors.textSecondary)
        }
    }

    // MARK: - Prompt

    private var promptCard: some View {
        card {
            Text("Prompt")
                .font(AppTypography.subheadlineMedium)
                .foregroundColor(AppColors.textPrimary)

            TextField("A red bicycle against a white wall", text: $viewModel.prompt, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)

            TextField("Negative prompt (optional)", text: $viewModel.negativePrompt, axis: .vertical)
                .lineLimit(1...3)
                .textFieldStyle(.roundedBorder)

            HStack {
                Text("Steps")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textSecondary)
                Stepper(
                    value: $viewModel.steps,
                    in: ImageGenerationViewModel.stepRange
                ) {
                    Text("\(viewModel.steps)")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.textPrimary)
                }
            }

            HStack {
                Text("Guidance")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textSecondary)
                Slider(value: $viewModel.guidanceScale,
                       in: ImageGenerationViewModel.guidanceRange,
                       step: ImageGenerationViewModel.guidanceStep)
                Text(String(format: "%.1f", viewModel.guidanceScale))
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textPrimary)
                    .monospacedDigit()
            }

            if viewModel.isGenerating {
                Button(role: .cancel) {
                    viewModel.cancel()
                } label: {
                    Text("Cancel")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            } else {
                Button {
                    viewModel.generate()
                } label: {
                    Text("Generate")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canGenerate)
            }
        }
    }

    // MARK: - Result

    private var resultCard: some View {
        card {
            HStack {
                Text("Result")
                    .font(AppTypography.subheadlineMedium)
                    .foregroundColor(AppColors.textPrimary)
                Spacer()
                if viewModel.generationTimeMs > 0, !viewModel.isGenerating {
                    Text("\(viewModel.generationTimeMs) ms")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.textSecondary)
                }
            }
            resultBody
        }
    }

    @ViewBuilder private var resultBody: some View {
        if let image = viewModel.image {
            // `Image(decorative:scale:)` takes a CGImage on both platforms, so
            // no UIImage/NSImage bridge is needed here.
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusRegular))
        } else if viewModel.isGenerating {
            VStack(spacing: AppSpacing.small) {
                if let fraction = viewModel.progressFraction {
                    ProgressView(value: fraction)
                    Text("Step \(viewModel.currentStep) of \(viewModel.totalSteps)")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.textSecondary)
                        .monospacedDigit()
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, minHeight: 160)
        } else {
            RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusRegular)
                .fill(AppColors.surfaceSunken)
                .frame(height: 160)
                .overlay(
                    Text("Nothing generated yet")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.textSecondary)
                )
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
        .background(AppColors.surface,
                    in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusRegular))
    }
}
