//
//  TextToSpeechView.swift
//  Swift-Starter-Example
//
//  RunAnywhere iOS SDK Starter App - Text to Speech
//

import SwiftUI
import RunAnywhere

struct TextToSpeechView: View {
    @EnvironmentObject var modelService: ModelService
    @Environment(\.dismiss) var dismiss
    
    @State private var inputText = ""
    @State private var isSynthesizing = false
    @State private var speechRate: Float = 1.0
    
    private let sampleTexts = [
        "Hello! Welcome to RunAnywhere. Experience the power of on-device AI.",
        "The quick brown fox jumps over the lazy dog.",
        "Technology is best when it brings people together.",
        "Privacy is not something that I am merely entitled to, it is an absolute prerequisite."
    ]
    
    var body: some View {
        ZStack {
            AppColors.primaryDark
                .ignoresSafeArea()
            
            if !modelService.isTTSLoaded {
                ModelLoaderView(
                    title: "TTS Voice Required",
                    subtitle: "Download and load the voice synthesis model",
                    icon: "speaker.wave.3.fill",
                    accentColor: AppColors.accentPink,
                    isDownloading: modelService.isTTSDownloading,
                    isLoading: modelService.isTTSLoading,
                    progress: modelService.ttsDownloadProgress
                ) {
                    Task { await modelService.downloadAndLoadTTS() }
                }
            } else {
                ScrollView {
                    VStack(spacing: 24) {
                        inputSection
                        controlsSection
                        playbackSection
                        sampleTextsSection
                    }
                    .padding(24)
                }
            }
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Text to Speech")
                    .font(AppFonts.titleMedium())
                    .foregroundStyle(AppColors.textPrimary)
            }
            
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .foregroundStyle(AppColors.textPrimary)
                }
            }
        }
        .onDisappear {
            // Stop any ongoing speech when leaving
            Task {
                await RunAnywhere.stopSpeaking()
            }
        }
    }
    
    // MARK: - Input Section
    private var inputSection: some View {
        VStack(spacing: 0) {
            TextEditor(text: $inputText)
                .font(AppFonts.bodyLarge())
                .foregroundStyle(AppColors.textPrimary)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 120)
                .padding(20)
            
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "textformat")
                        .font(.system(size: 18))
                        .foregroundStyle(AppColors.textMuted)
                    
                    Text("\(inputText.count) characters")
                        .font(AppFonts.bodySmall())
                        .foregroundStyle(AppColors.textMuted)
                }
                
                Spacer()
                
                if !inputText.isEmpty {
                    Button("Clear") {
                        inputText = ""
                    }
                    .font(AppFonts.bodySmall())
                    .foregroundStyle(AppColors.accentPink)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(AppColors.primaryMid)
        }
        .background(AppColors.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(AppColors.accentPink.opacity(0.2), lineWidth: 1)
        )
    }
    
    // MARK: - Controls Section
    private var controlsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Speech Rate")
                .font(AppFonts.titleMedium())
                .foregroundStyle(AppColors.textPrimary)
            
            HStack(spacing: 16) {
                Image(systemName: "speedometer")
                    .font(.system(size: 20))
                    .foregroundStyle(AppColors.textMuted)
                
                Slider(value: $speechRate, in: 0.5...2.0, step: 0.1)
                    .tint(AppColors.accentPink)
                
                Text(String(format: "%.1fx", speechRate))
                    .font(AppFonts.labelLarge())
                    .foregroundStyle(AppColors.accentPink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(AppColors.accentPink.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(20)
        .background(AppColors.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(AppColors.textMuted.opacity(0.1), lineWidth: 1)
        )
    }
    
    // MARK: - Playback Section
    private var playbackSection: some View {
        VStack(spacing: 24) {
            // Visualization area
            if isSynthesizing {
                speakingAnimation
            } else {
                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(AppColors.accentPink.opacity(0.5))
                    .frame(height: 60)
            }
            
            // Speak button
            Button {
                synthesize()
            } label: {
                ZStack {
                    Circle()
                        .fill(
                            isSynthesizing
                                ? LinearGradient(colors: [AppColors.textMuted, AppColors.textMuted], startPoint: .top, endPoint: .bottom)
                                : LinearGradient(colors: [AppColors.accentPink, Color(hex: "DB2777")], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .shadow(color: AppColors.accentPink.opacity(0.4), radius: 20, y: 8)
                    
                    if isSynthesizing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Image(systemName: "play.fill")
                            .font(.system(size: 40, weight: .medium))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 80, height: 80)
            }
            .disabled(isSynthesizing)
            
            Text(isSynthesizing ? "Speaking..." : "Tap to speak")
                .font(AppFonts.bodyMedium())
                .foregroundStyle(AppColors.textSecondary)
        }
        .padding(24)
        .background(
            LinearGradient(
                colors: [AppColors.surfaceCard, AppColors.surfaceCard.opacity(0.7)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(
                    isSynthesizing ? AppColors.accentPink.opacity(0.5) : AppColors.textMuted.opacity(0.1),
                    lineWidth: isSynthesizing ? 2 : 1
                )
        )
        .shadow(color: isSynthesizing ? AppColors.accentPink.opacity(0.2) : .clear, radius: 30)
    }
    
    private var speakingAnimation: some View {
        HStack(spacing: 8) {
            ForEach(0..<7, id: \.self) { index in
                RoundedRectangle(cornerRadius: 3)
                    .fill(AppColors.accentPink)
                    .frame(width: 6)
                    .frame(height: animatedBarHeight(for: index))
                    .animation(
                        .easeInOut(duration: 0.4)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.1),
                        value: isSynthesizing
                    )
            }
        }
        .frame(height: 60)
    }
    
    private func animatedBarHeight(for index: Int) -> CGFloat {
        let heights: [CGFloat] = [20, 40, 30, 50, 35, 45, 25]
        return heights[index % heights.count]
    }
    
    // MARK: - Sample Texts Section
    private var sampleTextsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sample Texts")
                .font(AppFonts.titleMedium())
                .foregroundStyle(AppColors.textMuted)
            
            ForEach(sampleTexts, id: \.self) { text in
                Button {
                    inputText = text
                } label: {
                    HStack {
                        Text(text)
                            .font(AppFonts.bodySmall())
                            .foregroundStyle(AppColors.textSecondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        
                        Spacer()
                        
                        Image(systemName: "plus.circle")
                            .font(.system(size: 20))
                            .foregroundStyle(AppColors.accentPink.opacity(0.6))
                    }
                    .padding(16)
                    .background(AppColors.surfaceCard.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(AppColors.textMuted.opacity(0.1), lineWidth: 1)
                    )
                }
            }
        }
    }
    
    // MARK: - Actions
    private func synthesize() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        
        isSynthesizing = true
        
        Task {
            do {
                var options = RATTSOptions.defaults()
                options.speakingRate = speechRate

                // SDK handles both synthesis AND playback internally - no manual audio handling needed!
                let result = try await RunAnywhere.speak(text, options: options)
                
                await MainActor.run {
                    isSynthesizing = false
                    print("✅ Speech completed, duration: \(result.duration)s")
                }
            } catch {
                print("❌ TTS error: \(error)")
                await MainActor.run {
                    isSynthesizing = false
                }
            }
        }
    }
    
}

#Preview {
    NavigationStack {
        TextToSpeechView()
            .environmentObject(ModelService())
    }
}
