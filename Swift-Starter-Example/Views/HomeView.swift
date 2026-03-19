//
//  HomeView.swift
//  Swift-Starter-Example
//
//  RunAnywhere iOS SDK Starter App - Main Home Screen
//

import SwiftUI

struct HomeView: View {
    @EnvironmentObject var modelService: ModelService
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background gradient
                AppColors.backgroundGradient
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Header
                        headerSection
                            .padding(.top, 20)
                        
                        // Privacy info card
                        privacyInfoCard
                            .padding(.top, 40)
                        
                        // Feature cards grid
                        featureCardsGrid
                            .padding(.top, 32)
                        
                        // Info section
                        modelInfoSection
                            .padding(.top, 24)
                        
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 24)
                }
            }
            #if os(iOS)
            .navigationBarHidden(true)
            #endif
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        HStack(spacing: 16) {
            // Logo
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(AppColors.accentGradient)
                    .shadow(color: AppColors.accentCyan.opacity(0.3), radius: 20, y: 2)
                
                Image(systemName: "bolt.fill")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(.white)
            }
            .frame(width: 56, height: 56)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("RunAnywhere")
                    .font(AppFonts.headlineLarge())
                    .foregroundStyle(AppColors.textPrimary)
                    .tracking(-1)
                
                Text("Swift SDK Starter")
                    .font(AppFonts.bodyMedium())
                    .fontWeight(.medium)
                    .foregroundStyle(AppColors.accentCyan)
            }
            
            Spacer()
        }
        .opacity(0)
        .onAppear { }
        .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .leading)), removal: .opacity))
        .animation(.easeOut(duration: 0.6), value: UUID())
        .opacity(1)
    }
    
    // MARK: - Privacy Info Card
    private var privacyInfoCard: some View {
        HStack(spacing: 16) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 28))
                .foregroundStyle(AppColors.accentCyan.opacity(0.8))
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Privacy-First On-Device AI")
                    .font(AppFonts.titleMedium())
                    .foregroundStyle(AppColors.textPrimary)
                
                Text("All AI processing happens locally on your device. No data ever leaves your phone.")
                    .font(AppFonts.bodySmall())
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [AppColors.surfaceCard.opacity(0.8), AppColors.surfaceCard.opacity(0.4)],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(AppColors.accentCyan.opacity(0.2), lineWidth: 1)
        )
    }
    
    // MARK: - Feature Cards Grid
    private var featureCardsGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 16),
            GridItem(.flexible(), spacing: 16)
        ], spacing: 16) {
            // Chat
            NavigationLink {
                ChatView()
                    .environmentObject(modelService)
            } label: {
                FeatureCardLabel(
                    title: "Chat",
                    subtitle: "LLM Text Generation",
                    icon: "bubble.left.and.bubble.right.fill",
                    gradientColors: [AppColors.accentCyan, Color(hex: "0EA5E9")]
                )
            }
            .buttonStyle(ScaleButtonStyle())
            .frame(height: 180)
            
            // Tool Calling
            NavigationLink {
                ToolCallingView()
                    .environmentObject(modelService)
            } label: {
                FeatureCardLabel(
                    title: "Tools",
                    subtitle: "Tool Calling",
                    icon: "wrench.and.screwdriver.fill",
                    gradientColors: [AppColors.accentOrange, Color(hex: "E67E22")]
                )
            }
            .buttonStyle(ScaleButtonStyle())
            .frame(height: 180)
            
            // Vision (VLM)
            NavigationLink {
                VisionView()
                    .environmentObject(modelService)
            } label: {
                FeatureCardLabel(
                    title: "Vision",
                    subtitle: "Image Understanding",
                    icon: "eye.fill",
                    gradientColors: [AppColors.accentPink, Color(hex: "DB2777")]
                )
            }
            .buttonStyle(ScaleButtonStyle())
            .frame(height: 180)
            
            // Diffusion (Image Generation)
            NavigationLink {
                ImageGenerationView()
                    .environmentObject(modelService)
            } label: {
                FeatureCardLabel(
                    title: "Diffusion",
                    subtitle: "Image Generation",
                    icon: "paintbrush.fill",
                    gradientColors: [AppColors.accentGreen, Color(hex: "059669")]
                )
            }
            .buttonStyle(ScaleButtonStyle())
            .frame(height: 180)
            
            // Speech to Text
            NavigationLink {
                SpeechToTextView()
                    .environmentObject(modelService)
            } label: {
                FeatureCardLabel(
                    title: "Speech",
                    subtitle: "Speech to Text",
                    icon: "mic.fill",
                    gradientColors: [AppColors.accentViolet, Color(hex: "7C3AED")]
                )
            }
            .buttonStyle(ScaleButtonStyle())
            .frame(height: 180)
            
            // Text to Speech
            NavigationLink {
                TextToSpeechView()
                    .environmentObject(modelService)
            } label: {
                FeatureCardLabel(
                    title: "Voice",
                    subtitle: "Text to Speech",
                    icon: "speaker.wave.3.fill",
                    gradientColors: [Color(hex: "6366F1"), Color(hex: "4F46E5")]
                )
            }
            .buttonStyle(ScaleButtonStyle())
            .frame(height: 180)
            
            // Voice Pipeline
            NavigationLink {
                VoicePipelineView()
                    .environmentObject(modelService)
            } label: {
                FeatureCardLabel(
                    title: "Pipeline",
                    subtitle: "Voice Agent",
                    icon: "sparkles",
                    gradientColors: [Color(hex: "14B8A6"), Color(hex: "0D9488")]
                )
            }
            .buttonStyle(ScaleButtonStyle())
            .frame(height: 180)
        }
    }
    
    // MARK: - Model Info Section
    private var modelInfoSection: some View {
        VStack(spacing: 12) {
            modelInfoRow(icon: "cpu", title: "LLM", value: modelService.selectedLLMVariant.displayName)
            modelInfoRow(icon: "eye", title: "VLM", value: "SmolVLM 256M")
            modelInfoRow(icon: "paintbrush", title: "Diffusion", value: "SD 1.5 CoreML")
            modelInfoRow(icon: "ear", title: "STT", value: modelService.selectedSTTVariant.displayName)
            modelInfoRow(icon: "waveform", title: "TTS", value: "Piper US")
        }
        .padding(20)
        .background(AppColors.surfaceCard.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(AppColors.textMuted.opacity(0.1), lineWidth: 1)
        )
    }
    
    private func modelInfoRow(icon: String, title: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(AppColors.textMuted)
                .frame(width: 24)
            
            Text(title)
                .font(AppFonts.bodyMedium())
                .foregroundStyle(AppColors.textSecondary)
            
            Spacer()
            
            Text(value)
                .font(AppFonts.bodySmall())
                .foregroundStyle(AppColors.accentCyan)
        }
    }
}

#Preview {
    HomeView()
        .environmentObject(ModelService())
}
