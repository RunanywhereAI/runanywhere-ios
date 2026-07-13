//
//  VisionView.swift
//  Swift-Starter-Example
//
//  RunAnywhere iOS SDK Starter App - Vision Language Model (VLM) Demo
//

import SwiftUI
import PhotosUI
import RunAnywhere

#if os(iOS)
import UIKit
private typealias PlatformImage = UIImage
#elseif os(macOS)
import AppKit
private typealias PlatformImage = NSImage
#endif

struct VisionView: View {
    @EnvironmentObject var modelService: ModelService
    
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedImage: PlatformImage?
    @State private var description = ""
    @State private var isProcessing = false
    @State private var prompt = "Describe this image in detail."
    @State private var tokensPerSecond: Double = 0
    @State private var errorMessage: String?
    
    var body: some View {
        ZStack {
            AppColors.backgroundGradient.ignoresSafeArea()
            
            if !modelService.isVLMLoaded {
                // VLM requires a separate multimodal model (GGUF + mmproj)
                ModelLoaderView(
                    title: "VLM Model Required",
                    subtitle: "Download SmolVLM 256M (~365 MB)\nfor on-device image understanding.",
                    icon: "eye.fill",
                    accentColor: AppColors.accentPink,
                    isDownloading: modelService.isVLMDownloading,
                    isLoading: modelService.isVLMLoading,
                    progress: modelService.vlmDownloadProgress
                ) {
                    Task { await modelService.downloadAndLoadVLM() }
                }
            } else {
                mainContent
            }
        }
        .navigationTitle("Vision (VLM)")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onChange(of: selectedPhoto) { _, newValue in
            Task {
                if let data = try? await newValue?.loadTransferable(type: Data.self),
                   let image = PlatformImage(data: data) {
                    selectedImage = image
                    description = ""
                    errorMessage = nil
                }
            }
        }
    }
    
    // MARK: - Main Content
    private var mainContent: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    // Image display area
                    imageArea
                    
                    // Prompt input
                    promptInput
                    
                    // Description output
                    if !description.isEmpty || isProcessing {
                        descriptionArea
                    }
                    
                    // Error
                    if let error = errorMessage {
                        errorView(error)
                    }
                }
                .padding(20)
            }
            
            // Bottom action bar
            actionBar
        }
    }
    
    // MARK: - Image Area
    private var imageArea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(AppColors.surfaceCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(AppColors.accentPink.opacity(0.2), lineWidth: 1)
                )
            
            if let image = selectedImage {
                platformImage(image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(8)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 48))
                        .foregroundStyle(AppColors.accentPink.opacity(0.5))
                    
                    Text("Select an image to analyze")
                        .font(AppFonts.bodyMedium())
                        .foregroundStyle(AppColors.textSecondary)
                    
                    PhotosPicker(
                        selection: $selectedPhoto,
                        matching: .images
                    ) {
                        HStack(spacing: 8) {
                            Image(systemName: "photo.fill")
                            Text("Choose Photo")
                        }
                        .font(AppFonts.titleMedium())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(AppColors.accentPink)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(40)
            }
        }
        .frame(minHeight: 250, maxHeight: 350)
    }
    
    // MARK: - Prompt Input
    private var promptInput: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Prompt")
                .font(AppFonts.labelLarge())
                .foregroundStyle(AppColors.textSecondary)
            
            TextField("Ask about the image...", text: $prompt)
                .font(AppFonts.bodyMedium())
                .foregroundStyle(AppColors.textPrimary)
                .padding(14)
                .background(AppColors.surfaceCard)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(AppColors.textMuted.opacity(0.2), lineWidth: 1)
                )
            
            // Quick prompts
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    quickPrompt("Describe this image")
                    quickPrompt("What objects are in this?")
                    quickPrompt("What colors do you see?")
                    quickPrompt("Is there text in this image?")
                }
            }
        }
    }
    
    private func quickPrompt(_ text: String) -> some View {
        Button {
            prompt = text
        } label: {
            Text(text)
                .font(AppFonts.bodySmall())
                .foregroundStyle(AppColors.accentPink)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(AppColors.accentPink.opacity(0.1))
                .clipShape(Capsule())
        }
    }
    
    // MARK: - Description Area
    private var descriptionArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("AI Description")
                    .font(AppFonts.labelLarge())
                    .foregroundStyle(AppColors.textSecondary)
                
                Spacer()
                
                if tokensPerSecond > 0 {
                    Text(String(format: "%.1f tok/s", tokensPerSecond))
                        .font(AppFonts.bodySmall())
                        .foregroundStyle(AppColors.accentPink)
                }
                
                if isProcessing {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            
            Text(description.isEmpty ? "Analyzing..." : description)
                .font(AppFonts.bodyMedium())
                .foregroundStyle(AppColors.textPrimary)
                .textSelection(.enabled)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppColors.surfaceCard)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(AppColors.accentPink.opacity(0.2), lineWidth: 1)
                )
        }
    }
    
    // MARK: - Error View
    private func errorView(_ message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AppColors.error)
            
            Text(message)
                .font(AppFonts.bodySmall())
                .foregroundStyle(AppColors.error)
        }
        .padding(16)
        .background(AppColors.error.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    // MARK: - Action Bar
    private var actionBar: some View {
        HStack(spacing: 12) {
            PhotosPicker(
                selection: $selectedPhoto,
                matching: .images
            ) {
                Image(systemName: "photo.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(AppColors.accentPink)
                    .frame(width: 48, height: 48)
                    .background(AppColors.surfaceCard)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(AppColors.accentPink.opacity(0.3), lineWidth: 1)
                    )
            }
            
            Button {
                if isProcessing {
                    Task { await RunAnywhere.cancelVLMGeneration() }
                } else {
                    Task { await processImage() }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isProcessing ? "stop.fill" : "eye.fill")
                    Text(isProcessing ? "Stop" : "Analyze Image")
                }
                .font(AppFonts.titleMedium())
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(
                    isProcessing
                    ? AnyShapeStyle(AppColors.error)
                    : AnyShapeStyle(LinearGradient(colors: [AppColors.accentPink, Color(hex: "DB2777")], startPoint: .topLeading, endPoint: .bottomTrailing))
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(selectedImage == nil && !isProcessing)
        }
        .padding(20)
        .background(AppColors.primaryDark.opacity(0.9))
    }
    
    // MARK: - Process Image
    private func processImage() async {
        guard let uiImage = selectedImage else { return }
        
        isProcessing = true
        description = ""
        errorMessage = nil
        tokensPerSecond = 0
        
        do {
            #if os(iOS)
            guard let image = RAVLMImage.fromUIImage(uiImage) else {
                errorMessage = "Failed to convert image"
                isProcessing = false
                return
            }
            #elseif os(macOS)
            guard let image = RAVLMImage.fromNSImage(uiImage) else {
                errorMessage = "Failed to convert image"
                isProcessing = false
                return
            }
            #endif
            var options = RAVLMGenerationOptions.defaults()
            options.maxTokens = 300
            let stream = try await RunAnywhere.processImageStream(
                image,
                prompt: prompt,
                options: options
            )

            let startTime = Date()
            var tokenCount = 0

            for await event in stream {
                description += event.token
                tokenCount += 1
                let elapsed = Date().timeIntervalSince(startTime)
                if elapsed > 0 {
                    tokensPerSecond = Double(tokenCount) / elapsed
                }
            }
        } catch {
            errorMessage = "VLM Error: \(error.localizedDescription)"
            print("VLM Error: \(error)")
        }
        
        isProcessing = false
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
        VisionView()
            .environmentObject(ModelService())
    }
}
