//
//  ImageGenerationView.swift
//  Swift-Starter-Example
//
//  RunAnywhere iOS SDK Starter App - Diffusion Image Generation Demo
//

import SwiftUI
import RunAnywhere

#if os(iOS)
import UIKit
private typealias PlatformImage = UIImage
#elseif os(macOS)
import AppKit
private typealias PlatformImage = NSImage
#endif

struct ImageGenerationView: View {
    @EnvironmentObject var modelService: ModelService
    
    @State private var prompt = ""
    @State private var isGenerating = false
    @State private var generatedImage: PlatformImage?
    @State private var progress: Double = 0
    @State private var statusMessage = "Ready"
    @State private var generationTimeMs: UInt64 = 0
    @State private var errorMessage: String?
    
    // Generation settings
    @State private var steps = 20
    @State private var guidanceScale: Double = 7.5
    @State private var width = 512
    @State private var height = 512
    
    private let quickPrompts = [
        "A serene mountain landscape at sunset",
        "A cute robot reading a book",
        "Abstract colorful digital art",
        "A cozy coffee shop interior",
        "A futuristic city skyline at night",
        "A magical forest with glowing mushrooms",
    ]
    
    var body: some View {
        ZStack {
            AppColors.backgroundGradient.ignoresSafeArea()
            
            if !modelService.isDiffusionLoaded {
                // Diffusion model needs to be downloaded and loaded
                ModelLoaderView(
                    title: "Diffusion Model Required",
                    subtitle: "Download Stable Diffusion 1.5 CoreML (~1.6 GB)\nfor on-device image generation.\n\nFirst-time loading compiles CoreML models\nand may take 5-15 minutes.",
                    icon: "paintbrush.fill",
                    accentColor: AppColors.accentGreen,
                    isDownloading: modelService.isDiffusionDownloading,
                    isLoading: modelService.isDiffusionLoading,
                    progress: modelService.diffusionDownloadProgress
                ) {
                    Task { await modelService.downloadAndLoadDiffusion() }
                }
                .overlay(alignment: .bottom) {
                    if !modelService.diffusionStatusMessage.isEmpty && (modelService.isDiffusionLoading || modelService.isDiffusionDownloading) {
                        Text(modelService.diffusionStatusMessage)
                            .font(AppFonts.bodySmall())
                            .foregroundStyle(AppColors.textSecondary)
                            .padding(.bottom, 40)
                    }
                }
            } else {
                mainContent
            }
        }
        .navigationTitle("Image Generation")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
    
    // MARK: - Main Content
    private var mainContent: some View {
        VStack(spacing: 0) {
            // Status bar
            statusBar
            
            ScrollView {
                VStack(spacing: 20) {
                    // Image display
                    imageDisplay
                    
                    // Prompt input
                    promptSection
                    
                    // Quick prompts
                    quickPromptsSection
                    
                    // Settings
                    settingsSection
                }
                .padding(20)
            }
            
            // Generate button
            generateButton
        }
    }
    
    // MARK: - Status Bar
    private var statusBar: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(AppColors.success)
                .frame(width: 8, height: 8)
            
            Text("SD 1.5 CoreML loaded")
                .font(AppFonts.bodySmall())
                .foregroundStyle(AppColors.textSecondary)
            
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(AppColors.surfaceCard.opacity(0.5))
    }
    
    // MARK: - Image Display
    private var imageDisplay: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(AppColors.surfaceCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(AppColors.accentGreen.opacity(0.2), lineWidth: 1)
                )
            
            if let image = generatedImage {
                platformImage(image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(8)
            } else if isGenerating {
                VStack(spacing: 20) {
                    ProgressView(value: progress)
                        .progressViewStyle(LinearProgressViewStyle(tint: AppColors.accentGreen))
                        .frame(width: 200)
                    
                    Text(statusMessage)
                        .font(AppFonts.bodySmall())
                        .foregroundStyle(AppColors.accentGreen)
                    
                    Text("\(Int(progress * 100))%")
                        .font(AppFonts.headlineMedium())
                        .foregroundStyle(AppColors.textPrimary)
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "paintbrush.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(AppColors.accentGreen.opacity(0.5))
                    
                    Text("Enter a prompt to generate")
                        .font(AppFonts.bodyMedium())
                        .foregroundStyle(AppColors.textSecondary)
                }
                .padding(40)
            }
            
            if let error = errorMessage {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(AppColors.error)
                    Text(error)
                        .font(AppFonts.bodySmall())
                        .foregroundStyle(AppColors.error)
                        .multilineTextAlignment(.center)
                }
                .padding(20)
            }
        }
        .frame(minHeight: 300)
        .frame(maxHeight: 350)
    }
    
    // MARK: - Prompt Section
    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Prompt")
                .font(AppFonts.labelLarge())
                .foregroundStyle(AppColors.textSecondary)
            
            TextEditor(text: $prompt)
                .font(AppFonts.bodyMedium())
                .foregroundStyle(AppColors.textPrimary)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 60, maxHeight: 100)
                .padding(14)
                .background(AppColors.surfaceCard)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(AppColors.textMuted.opacity(0.2), lineWidth: 1)
                )
        }
    }
    
    // MARK: - Quick Prompts
    private var quickPromptsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick Prompts")
                .font(AppFonts.labelLarge())
                .foregroundStyle(AppColors.textSecondary)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(quickPrompts, id: \.self) { qp in
                        Button {
                            prompt = qp
                        } label: {
                            Text(qp)
                                .font(AppFonts.bodySmall())
                                .foregroundStyle(AppColors.accentGreen)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(AppColors.accentGreen.opacity(0.1))
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Settings
    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings")
                .font(AppFonts.labelLarge())
                .foregroundStyle(AppColors.textSecondary)
            
            // Steps
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Steps")
                        .font(AppFonts.bodySmall())
                        .foregroundStyle(AppColors.textMuted)
                    Spacer()
                    Text("\(steps)")
                        .font(AppFonts.bodySmall())
                        .foregroundStyle(AppColors.accentGreen)
                }
                Slider(value: Binding(
                    get: { Double(steps) },
                    set: { steps = Int($0) }
                ), in: 1...50, step: 1)
                .tint(AppColors.accentGreen)
            }
            
            // Guidance Scale
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Guidance Scale")
                        .font(AppFonts.bodySmall())
                        .foregroundStyle(AppColors.textMuted)
                    Spacer()
                    Text(String(format: "%.1f", guidanceScale))
                        .font(AppFonts.bodySmall())
                        .foregroundStyle(AppColors.accentGreen)
                }
                Slider(value: $guidanceScale, in: 1...20, step: 0.5)
                    .tint(AppColors.accentGreen)
            }
            
            // Generation time
            if generationTimeMs > 0 {
                HStack {
                    Image(systemName: "clock.fill")
                        .foregroundStyle(AppColors.textMuted)
                    Text("Last generation: \(String(format: "%.1f", Double(generationTimeMs) / 1000.0))s")
                        .font(AppFonts.bodySmall())
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
        }
        .padding(16)
        .background(AppColors.surfaceCard.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppColors.textMuted.opacity(0.1), lineWidth: 1)
        )
    }
    
    // MARK: - Generate Button
    private var generateButton: some View {
        HStack(spacing: 12) {
            Button {
                if isGenerating {
                    isGenerating = false
                } else {
                    Task { await generateImage() }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isGenerating ? "stop.fill" : "paintbrush.fill")
                    Text(isGenerating ? "Cancel" : "Generate Image")
                }
                .font(AppFonts.titleMedium())
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(
                    isGenerating
                    ? AnyShapeStyle(AppColors.error)
                    : AnyShapeStyle(LinearGradient(colors: [AppColors.accentGreen, Color(hex: "059669")], startPoint: .topLeading, endPoint: .bottomTrailing))
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(prompt.isEmpty && !isGenerating)
        }
        .padding(20)
        .background(AppColors.primaryDark.opacity(0.9))
    }
    
    private func generateImage() async {
        guard !prompt.isEmpty else { return }

        // On-device image generation (diffusion) is not exposed by the current
        // RunAnywhere SDK surface, so surface a clear message instead of
        // pretending to generate.
        generatedImage = nil
        progress = 0
        statusMessage = "Ready"
        errorMessage = "Image generation is not available in this SDK version."
    }

    private func platformImage(_ image: PlatformImage) -> Image {
        #if os(iOS)
        return Image(uiImage: image)
        #elseif os(macOS)
        return Image(nsImage: image)
        #endif
    }
}

#Preview {
    NavigationStack {
        ImageGenerationView()
            .environmentObject(ModelService())
    }
}
