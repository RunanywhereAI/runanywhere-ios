//
//  VoicePipelineView.swift
//  Swift-Starter-Example
//
//  RunAnywhere iOS SDK Starter App - Voice Pipeline (Voice Agent)
//

import SwiftUI
import AVFoundation
import RunAnywhere

// MARK: - Pipeline State
enum VoicePipelineState {
    case idle
    case listening
    case processing
    case speaking
    case error
    
    var statusColor: Color {
        switch self {
        case .idle: return AppColors.textMuted
        case .listening: return AppColors.accentViolet
        case .processing: return AppColors.accentCyan
        case .speaking: return AppColors.accentPink
        case .error: return AppColors.error
        }
    }
    
    var statusIcon: String {
        switch self {
        case .idle: return "circle"
        case .listening: return "mic.fill"
        case .processing: return "brain"
        case .speaking: return "speaker.wave.3.fill"
        case .error: return "exclamationmark.circle"
        }
    }
}

// MARK: - Conversation Turn
struct ConversationTurn: Identifiable {
    let id = UUID()
    let transcript: String
    let response: String
    let timestamp: Date
}

struct VoicePipelineView: View {
    @EnvironmentObject var modelService: ModelService
    @Environment(\.dismiss) var dismiss
    
    @State private var isSessionActive = false
    @State private var status = "Ready"
    @State private var audioLevel: Double = 0.0
    @State private var lastTranscript = ""
    @State private var lastResponse = ""
    @State private var conversationHistory: [ConversationTurn] = []
    @State private var currentState: VoicePipelineState = .idle
    
    // Recording
    @State private var audioRecorder: AVAudioRecorder?
    @State private var levelTimer: Timer?
    @State private var recordingURL: URL?
    
    var body: some View {
        ZStack {
            AppColors.primaryDark
                .ignoresSafeArea()
            
            if !modelService.isVoiceAgentReady {
                modelLoadingView
            } else {
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: 24) {
                            statusCard
                            visualizationArea
                            
                            if !lastTranscript.isEmpty || !lastResponse.isEmpty {
                                currentTurnCard
                            }
                            
                            if !conversationHistory.isEmpty {
                                historySection
                            }
                        }
                        .padding(24)
                    }
                    
                    controlButton
                }
            }
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Voice Pipeline")
                    .font(AppFonts.titleMedium())
                    .foregroundStyle(AppColors.textPrimary)
            }
            
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    stopSession()
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .foregroundStyle(AppColors.textPrimary)
                }
            }
            
            ToolbarItem(placement: .confirmationAction) {
                if !conversationHistory.isEmpty {
                    Button {
                        conversationHistory.removeAll()
                        lastTranscript = ""
                        lastResponse = ""
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(AppColors.textPrimary)
                    }
                }
            }
        }
        .onDisappear {
            stopSession()
        }
    }
    
    // MARK: - Model Loading View
    private var modelLoadingView: some View {
        ScrollView {
            VStack(spacing: 32) {
                // Header
                VStack(spacing: 16) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 48))
                        .foregroundStyle(AppColors.accentGreen)
                    
                    Text("Voice Pipeline")
                        .font(AppFonts.headlineMedium())
                        .foregroundStyle(AppColors.textPrimary)
                    
                    Text("Full voice AI experience: Speak → Transcribe → Generate → Speak")
                        .font(AppFonts.bodyMedium())
                        .foregroundStyle(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
                .frame(maxWidth: .infinity)
                .background(
                    LinearGradient(
                        colors: [AppColors.accentGreen.opacity(0.1), AppColors.surfaceCard],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(AppColors.accentGreen.opacity(0.3), lineWidth: 1)
                )
                
                // Required models
                VStack(alignment: .leading, spacing: 16) {
                    Text("Required Models")
                        .font(AppFonts.titleMedium())
                        .foregroundStyle(AppColors.textPrimary)
                    
                    modelCard(
                        icon: "cpu",
                        title: "LLM",
                        subtitle: "SmolLM2 360M",
                        isLoaded: modelService.isLLMLoaded,
                        isLoading: modelService.isLLMLoading || modelService.isLLMDownloading,
                        progress: modelService.llmDownloadProgress,
                        accentColor: AppColors.accentCyan
                    ) {
                        Task { await modelService.downloadAndLoadLLM() }
                    }
                    
                    modelCard(
                        icon: "mic.fill",
                        title: "STT",
                        subtitle: modelService.selectedSTTVariant.displayName,
                        isLoaded: modelService.isSTTLoaded,
                        isLoading: modelService.isSTTLoading || modelService.isSTTDownloading,
                        progress: modelService.sttDownloadProgress,
                        accentColor: AppColors.accentViolet
                    ) {
                        Task { await modelService.downloadAndLoadSTT() }
                    }
                    
                    modelCard(
                        icon: "speaker.wave.3.fill",
                        title: "TTS",
                        subtitle: "Piper",
                        isLoaded: modelService.isTTSLoaded,
                        isLoading: modelService.isTTSLoading || modelService.isTTSDownloading,
                        progress: modelService.ttsDownloadProgress,
                        accentColor: AppColors.accentPink
                    ) {
                        Task { await modelService.downloadAndLoadTTS() }
                    }
                }
                
                // Download all button
                Button {
                    Task { await modelService.downloadAndLoadAllModels() }
                } label: {
                    Text("Download & Load All Models")
                        .font(AppFonts.titleMedium())
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(AppColors.accentGreen)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(modelService.isAnyDownloading || modelService.isAnyLoading)
            }
            .padding(24)
        }
    }
    
    private func modelCard(
        icon: String,
        title: String,
        subtitle: String,
        isLoaded: Bool,
        isLoading: Bool,
        progress: Double,
        accentColor: Color,
        onLoad: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(accentColor.opacity(0.1))
                
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundStyle(accentColor)
            }
            .frame(width: 48, height: 48)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(AppFonts.titleMedium())
                    .foregroundStyle(AppColors.textPrimary)
                
                Text(subtitle)
                    .font(AppFonts.bodySmall())
                    .foregroundStyle(AppColors.textMuted)
                
                if isLoading && progress > 0 {
                    ProgressView(value: progress)
                        .progressViewStyle(LinearProgressViewStyle(tint: accentColor))
                        .padding(.top, 4)
                }
            }
            
            Spacer()
            
            if isLoaded {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(AppColors.success)
            } else if isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: accentColor))
            } else {
                Button {
                    onLoad()
                } label: {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(accentColor)
                }
            }
        }
        .padding(16)
        .background(AppColors.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    isLoaded ? AppColors.success.opacity(0.5) : AppColors.textMuted.opacity(0.1),
                    lineWidth: 1
                )
        )
    }
    
    // MARK: - Status Card
    private var statusCard: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(currentState.statusColor.opacity(0.2))
                
                Image(systemName: currentState.statusIcon)
                    .font(.system(size: 24))
                    .foregroundStyle(currentState.statusColor)
            }
            .frame(width: 48, height: 48)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(status)
                    .font(AppFonts.titleMedium())
                    .foregroundStyle(currentState.statusColor)
                
                Text(statusDescription)
                    .font(AppFonts.bodySmall())
                    .foregroundStyle(AppColors.textSecondary)
            }
            
            Spacer()
            
            if currentState == .processing || currentState == .speaking {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: currentState.statusColor))
            }
        }
        .padding(20)
        .background(currentState.statusColor.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(currentState.statusColor.opacity(0.3), lineWidth: 1)
        )
    }
    
    private var statusDescription: String {
        switch currentState {
        case .idle: return "Press the button to start talking"
        case .listening: return "Speak clearly into your microphone"
        case .processing: return "Transcribing and generating response..."
        case .speaking: return "Playing AI response"
        case .error: return "An error occurred"
        }
    }
    
    // MARK: - Visualization Area
    private var visualizationArea: some View {
        VStack(spacing: 12) {
            if currentState == .listening {
                AudioVisualizer(level: audioLevel)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: isSessionActive ? "sparkles" : "play.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(AppColors.accentGreen.opacity(0.5))
                    
                    Text(isSessionActive ? "Voice session active" : "Start the voice session")
                        .font(AppFonts.bodyMedium())
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
        }
        .frame(height: 160)
        .frame(maxWidth: .infinity)
        .padding(24)
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
                    isSessionActive ? AppColors.accentGreen.opacity(0.5) : AppColors.textMuted.opacity(0.1),
                    lineWidth: isSessionActive ? 2 : 1
                )
        )
        .shadow(color: isSessionActive ? AppColors.accentGreen.opacity(0.2) : .clear, radius: 30)
    }
    
    // MARK: - Current Turn Card
    private var currentTurnCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("CURRENT TURN")
                    .font(AppFonts.labelSmall())
                    .fontWeight(.bold)
                    .foregroundStyle(AppColors.accentGreen)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppColors.accentGreen.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                
                Spacer()
            }
            
            if !lastTranscript.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "person.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(AppColors.accentViolet)
                    
                    Text(lastTranscript)
                        .font(AppFonts.bodyMedium())
                        .foregroundStyle(AppColors.textPrimary)
                }
            }
            
            if !lastResponse.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16))
                        .foregroundStyle(AppColors.accentCyan)
                    
                    Text(lastResponse)
                        .font(AppFonts.bodyMedium())
                        .foregroundStyle(AppColors.textPrimary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(AppColors.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(AppColors.accentGreen.opacity(0.3), lineWidth: 1)
        )
    }
    
    // MARK: - History Section
    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Conversation History")
                .font(AppFonts.titleMedium())
                .foregroundStyle(AppColors.textMuted)
                .padding(.leading, 4)
            
            ForEach(conversationHistory.reversed()) { turn in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(AppColors.accentViolet)
                        
                        Text(turn.transcript)
                            .font(AppFonts.bodySmall())
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 14))
                            .foregroundStyle(AppColors.accentCyan)
                        
                        Text(turn.response)
                            .font(AppFonts.bodySmall())
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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
    
    // MARK: - Control Button
    private var controlButton: some View {
        VStack(spacing: 0) {
            Divider()
                .background(AppColors.textMuted.opacity(0.1))
            
            Button {
                toggleSession()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: isSessionActive ? "stop.fill" : "play.fill")
                        .font(.system(size: 28, weight: .medium))
                    
                    Text(isSessionActive ? "Stop Session" : "Start Voice Session")
                        .font(AppFonts.titleMedium())
                        .fontWeight(.bold)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 72)
                .background(
                    LinearGradient(
                        colors: isSessionActive
                            ? [AppColors.error, Color(hex: "DC2626")]
                            : [AppColors.accentGreen, Color(hex: "059669")],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 36))
                .shadow(
                    color: (isSessionActive ? AppColors.error : AppColors.accentGreen).opacity(0.4),
                    radius: 20,
                    y: 8
                )
            }
            .scaleEffect(isSessionActive ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: isSessionActive)
            .padding(24)
            .background(AppColors.surfaceCard.opacity(0.8))
        }
    }
    
    // MARK: - Session Logic
    private func toggleSession() {
        if isSessionActive {
            stopSession()
        } else {
            startSession()
        }
    }
    
    private func startSession() {
        isSessionActive = true
        status = "Starting..."
        currentState = .listening
        lastTranscript = ""
        lastResponse = ""
        
        startListening()
    }
    
    private func startListening() {
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
                        self.status = "Microphone permission denied"
                        self.currentState = .error
                    }
                }
            }
        } catch {
            status = "Error: \(error.localizedDescription)"
            currentState = .error
        }
        #else
        // On macOS, AVAudioSession is not available; start recording directly
        beginRecording()
        #endif
    }
    
    private func beginRecording() {
        let tempDir = FileManager.default.temporaryDirectory
        recordingURL = tempDir.appendingPathComponent("voice_\(Date().timeIntervalSince1970).wav")
        
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
            
            status = "Listening"
            currentState = .listening
            
            // Level monitoring
            levelTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                audioRecorder?.updateMeters()
                let dB = Double(audioRecorder?.averagePower(forChannel: 0) ?? -60)
                audioLevel = max(0, min(1, (dB + 60) / 60))
            }
            
            // Auto-stop after 5 seconds of recording
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [self] in
                if currentState == .listening {
                    processRecording()
                }
            }
        } catch {
            status = "Recording error"
            currentState = .error
        }
    }
    
    private func processRecording() {
        levelTimer?.invalidate()
        audioRecorder?.stop()
        audioRecorder = nil
        audioLevel = 0
        
        status = "Processing"
        currentState = .processing
        
        guard let url = recordingURL else { return }
        
        Task {
            do {
                let audioData = try Data(contentsOf: url)
                
                // Transcribe
                let transcript = try await RunAnywhere.transcribe(audio: audioData).text

                await MainActor.run {
                    lastTranscript = transcript.isEmpty ? "(No speech detected)" : transcript
                }

                if !transcript.isEmpty {
                    var options = RALLMGenerationOptions.defaults()
                    options.maxTokens = 200
                    options.temperature = 0.7
                    options.systemPrompt = "You are a helpful voice assistant. Respond concisely in 1-2 sentences."
                    let genResult = try await RunAnywhere.generate(prompt: transcript, options: options)
                    let response = String.stripThinkingTags(genResult.text)
                    
                    await MainActor.run {
                        lastResponse = response
                        status = "Speaking"
                        currentState = .speaking
                    }
                    
                    _ = try await RunAnywhere.speak(response)
                    
                    await MainActor.run {
                        completeTurn()
                    }
                } else {
                    await MainActor.run {
                        if isSessionActive {
                            status = "Listening"
                            currentState = .listening
                            beginRecording()
                        }
                    }
                }
                
                try? FileManager.default.removeItem(at: url)
            } catch {
                await MainActor.run {
                    status = "Error: \(error.localizedDescription)"
                    currentState = .error
                }
            }
        }
    }
    
    private func completeTurn() {
        if !lastTranscript.isEmpty && !lastResponse.isEmpty &&
            lastTranscript != "(No speech detected)" {
            conversationHistory.append(ConversationTurn(
                transcript: lastTranscript,
                response: lastResponse,
                timestamp: Date()
            ))
        }
        
        lastTranscript = ""
        lastResponse = ""
        
        if isSessionActive {
            status = "Listening"
            currentState = .listening
            beginRecording()
        } else {
            status = "Ready"
            currentState = .idle
        }
    }
    
    private func stopSession() {
        levelTimer?.invalidate()
        audioRecorder?.stop()
        
        isSessionActive = false
        status = "Ready"
        currentState = .idle
        audioLevel = 0
    }
}

#Preview {
    NavigationStack {
        VoicePipelineView()
            .environmentObject(ModelService())
    }
}
