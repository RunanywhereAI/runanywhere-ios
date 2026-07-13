//
//  SpeechToTextView.swift
//  Swift-Starter-Example
//
//  RunAnywhere iOS SDK Starter App - Speech to Text
//

import SwiftUI
import AVFoundation
import RunAnywhere

struct SpeechToTextView: View {
    @EnvironmentObject var modelService: ModelService
    @Environment(\.dismiss) var dismiss
    
    @State private var isRecording = false
    @State private var isTranscribing = false
    @State private var transcription = ""
    @State private var transcriptionHistory: [String] = []
    @State private var audioLevel: Double = 0.0
    
    @State private var audioRecorder: AVAudioRecorder?
    @State private var levelTimer: Timer?
    @State private var recordingURL: URL?
    
    var body: some View {
        ZStack {
            AppColors.primaryDark
                .ignoresSafeArea()
            
            if !modelService.isSTTLoaded {
                ScrollView {
                    VStack(spacing: 24) {
                        sttModelPicker
                        ModelLoaderView(
                            title: "STT Model Required",
                            subtitle: "Download \(modelService.selectedSTTVariant.displayName) (\(modelService.selectedSTTVariant.sizeLabel))",
                            icon: "mic.fill",
                            accentColor: AppColors.accentViolet,
                            isDownloading: modelService.isSTTDownloading,
                            isLoading: modelService.isSTTLoading,
                            progress: modelService.sttDownloadProgress
                        ) {
                            Task { await modelService.downloadAndLoadSTT() }
                        }
                    }
                    .padding(24)
                }
            } else {
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: 24) {
                            loadedModelIndicator
                            recordingArea
                            
                            if !transcription.isEmpty || isTranscribing {
                                currentTranscriptionCard
                            }
                            
                            if !transcriptionHistory.isEmpty {
                                historySection
                            }
                        }
                        .padding(24)
                    }
                    
                    recordButton
                }
            }
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Speech to Text")
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
            
            ToolbarItem(placement: .confirmationAction) {
                if !transcriptionHistory.isEmpty {
                    Button {
                        transcriptionHistory.removeAll()
                        transcription = ""
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(AppColors.textPrimary)
                    }
                }
            }
        }
        .onDisappear {
            stopRecording()
        }
    }
    
    // MARK: - STT Model Picker
    private var sttModelPicker: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Select Whisper Model")
                .font(AppFonts.titleMedium())
                .foregroundStyle(AppColors.textPrimary)

            ForEach(STTModelVariant.allCases) { variant in
                let isSelected = modelService.selectedSTTVariant == variant
                Button {
                    Task { await modelService.selectSTTVariant(variant) }
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 22))
                            .foregroundStyle(isSelected ? AppColors.accentViolet : AppColors.textMuted)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(variant.displayName)
                                .font(AppFonts.titleMedium())
                                .foregroundStyle(AppColors.textPrimary)

                            Text("\(variant.qualityLabel) · \(variant.sizeLabel)")
                                .font(AppFonts.bodySmall())
                                .foregroundStyle(AppColors.textSecondary)
                        }

                        Spacer()
                    }
                    .padding(14)
                    .background(isSelected ? AppColors.accentViolet.opacity(0.1) : AppColors.surfaceCard)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? AppColors.accentViolet.opacity(0.5) : AppColors.textMuted.opacity(0.1), lineWidth: 1)
                    )
                }
                .disabled(modelService.isSTTDownloading || modelService.isSTTLoading)
            }
        }
    }

    // MARK: - Loaded Model Indicator
    private var loadedModelIndicator: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(AppColors.success)

            Text(modelService.selectedSTTVariant.displayName)
                .font(AppFonts.bodySmall())
                .foregroundStyle(AppColors.textSecondary)

            Spacer()

            Button {
                Task { await modelService.unloadSTTModel() }
            } label: {
                Text("Change Model")
                    .font(AppFonts.labelSmall())
                    .foregroundStyle(AppColors.accentViolet)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(AppColors.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(AppColors.success.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Recording Area
    private var recordingArea: some View {
        VStack(spacing: 24) {
            if isRecording {
                AudioVisualizer(level: audioLevel)
                
                Text("Listening...")
                    .font(AppFonts.titleLarge())
                    .foregroundStyle(AppColors.accentViolet)
                
                Text("Speak clearly into your microphone")
                    .font(AppFonts.bodyMedium())
                    .foregroundStyle(AppColors.textSecondary)
            } else if isTranscribing {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: AppColors.accentViolet))
                    .scaleEffect(1.5)
                    .frame(height: 80)
                
                Text("Transcribing...")
                    .font(AppFonts.titleLarge())
                    .foregroundStyle(AppColors.textPrimary)
            } else {
                ZStack {
                    Circle()
                        .fill(AppColors.accentViolet.opacity(0.1))
                        .frame(width: 96, height: 96)
                    
                    Image(systemName: "mic.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(AppColors.accentViolet)
                }
                
                Text("Tap to Record")
                    .font(AppFonts.titleLarge())
                    .foregroundStyle(AppColors.textPrimary)
                
                Text("On-device speech recognition")
                    .font(AppFonts.bodyMedium())
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .background(
            LinearGradient(
                colors: [AppColors.surfaceCard, AppColors.surfaceCard.opacity(0.5)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(
                    isRecording ? AppColors.accentViolet.opacity(0.5) : AppColors.textMuted.opacity(0.1),
                    lineWidth: isRecording ? 2 : 1
                )
        )
        .shadow(
            color: isRecording ? AppColors.accentViolet.opacity(0.2) : .clear,
            radius: 30
        )
    }
    
    // MARK: - Current Transcription Card
    private var currentTranscriptionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("LATEST")
                    .font(AppFonts.labelSmall())
                    .fontWeight(.bold)
                    .foregroundStyle(AppColors.accentViolet)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppColors.accentViolet.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                
                Spacer()
            }
            
            if isTranscribing {
                HStack(spacing: 8) {
                    Text("Processing")
                        .font(AppFonts.bodyLarge())
                        .foregroundStyle(AppColors.textMuted)
                    
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: AppColors.accentViolet))
                        .scaleEffect(0.8)
                }
            } else {
                Text(transcription)
                    .font(AppFonts.bodyLarge())
                    .foregroundStyle(AppColors.textPrimary)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(AppColors.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(AppColors.accentViolet.opacity(0.3), lineWidth: 1)
        )
    }
    
    // MARK: - History Section
    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("History")
                .font(AppFonts.titleMedium())
                .foregroundStyle(AppColors.textMuted)
                .padding(.leading, 4)
            
            ForEach(transcriptionHistory.reversed().indices, id: \.self) { index in
                let text = transcriptionHistory.reversed()[index]
                
                Text(text)
                    .font(AppFonts.bodyMedium())
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(AppColors.surfaceCard.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(AppColors.textMuted.opacity(0.1), lineWidth: 1)
                    )
                    .textSelection(.enabled)
            }
        }
    }
    
    // MARK: - Record Button
    private var recordButton: some View {
        VStack(spacing: 0) {
            Divider()
                .background(AppColors.textMuted.opacity(0.1))
            
            Button {
                isTranscribing ? () : toggleRecording()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 28, weight: .medium))
                    
                    Text(isRecording ? "Stop Recording" : "Start Recording")
                        .font(AppFonts.titleMedium())
                        .fontWeight(.bold)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 72)
                .background(
                    LinearGradient(
                        colors: isRecording
                            ? [AppColors.error, Color(hex: "DC2626")]
                            : [AppColors.accentViolet, Color(hex: "7C3AED")],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 36))
                .shadow(
                    color: (isRecording ? AppColors.error : AppColors.accentViolet).opacity(0.4),
                    radius: 20,
                    y: 8
                )
            }
            .disabled(isTranscribing)
            .scaleEffect(isRecording ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: isRecording)
            .padding(24)
            .background(AppColors.surfaceCard.opacity(0.8))
        }
    }
    
    // MARK: - Recording Logic
    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    private func startRecording() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
            
            session.requestRecordPermission { granted in
                DispatchQueue.main.async {
                    if granted {
                        self.beginRecording()
                    } else {
                        self.transcription = "Microphone permission denied"
                    }
                }
            }
        } catch {
            transcription = "Error: \(error.localizedDescription)"
        }
        #else
        // On macOS, AVAudioSession is not available; start recording directly
        beginRecording()
        #endif
    }
    
    private func beginRecording() {
        let tempDir = FileManager.default.temporaryDirectory
        recordingURL = tempDir.appendingPathComponent("recording_\(Date().timeIntervalSince1970).wav")
        
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false
        ]
        
        do {
            audioRecorder = try AVAudioRecorder(url: recordingURL!, settings: settings)
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.record()
            
            isRecording = true
            transcription = ""
            
            // Start level monitoring
            levelTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                audioRecorder?.updateMeters()
                let dB = Double(audioRecorder?.averagePower(forChannel: 0) ?? -60)
                // Convert dB to 0-1 range
                audioLevel = max(0, min(1, (dB + 60) / 60))
            }
        } catch {
            transcription = "Recording error: \(error.localizedDescription)"
        }
    }
    
    private func stopRecording() {
        levelTimer?.invalidate()
        levelTimer = nil
        audioRecorder?.stop()
        audioRecorder = nil
        
        guard isRecording else { return }
        isRecording = false
        audioLevel = 0
        
        guard let url = recordingURL else { return }
        
        isTranscribing = true
        
        Task {
            do {
                let audioData = try Data(contentsOf: url)
                
                if audioData.count > 1600 { // At least 0.1s of audio at 16kHz
                    let text = try await RunAnywhere.transcribe(audio: audioData).text

                    await MainActor.run {
                        transcription = text.isEmpty ? "(No speech detected)" : text
                        if !text.isEmpty {
                            transcriptionHistory.append(text)
                        }
                        isTranscribing = false
                    }
                } else {
                    await MainActor.run {
                        transcription = "(Recording too short)"
                        isTranscribing = false
                    }
                }
                
                // Clean up temp file
                try? FileManager.default.removeItem(at: url)
            } catch {
                await MainActor.run {
                    transcription = "Error: \(error.localizedDescription)"
                    isTranscribing = false
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        SpeechToTextView()
            .environmentObject(ModelService())
    }
}
