//
//  ChatView.swift
//  Swift-Starter-Example
//
//  RunAnywhere iOS SDK Starter App - Chat with LLM
//

import SwiftUI
import RunAnywhere

struct ChatView: View {
    @EnvironmentObject var modelService: ModelService
    @Environment(\.dismiss) var dismiss
    
    @State private var inputText = ""
    @State private var messages: [ChatMessage] = []
    @State private var isGenerating = false
    @State private var currentResponse = ""
    @State private var streamingTask: Task<Void, Never>?
    @State private var showModelPicker = false
    
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        ZStack {
            AppColors.primaryDark
                .ignoresSafeArea()
            
            if !modelService.isLLMLoaded {
                ModelLoaderView(
                    title: modelService.selectedLLMVariant.displayName,
                    subtitle: "\(modelService.selectedLLMVariant.sizeLabel) · Tap model name above to switch",
                    icon: "bubble.left.and.bubble.right.fill",
                    accentColor: AppColors.accentCyan,
                    isDownloading: modelService.isLLMDownloading,
                    isLoading: modelService.isLLMLoading,
                    progress: modelService.llmDownloadProgress
                ) {
                    Task { await modelService.downloadAndLoadLLM() }
                }
            } else {
                VStack(spacing: 0) {
                    // Messages
                    if messages.isEmpty {
                        emptyStateView
                    } else {
                        messagesList
                    }
                    
                    // Input area
                    inputArea
                }
            }
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .principal) {
                Button { showModelPicker = true } label: {
                    HStack(spacing: 6) {
                        Text(modelService.selectedLLMVariant.displayName)
                            .font(AppFonts.bodyMedium())
                            .fontWeight(.semibold)
                            .foregroundStyle(AppColors.textPrimary)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(AppColors.accentCyan)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(AppColors.surfaceCard)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(AppColors.accentCyan.opacity(0.3), lineWidth: 1))
                }
                .disabled(isGenerating)
            }
            
            ToolbarItem(placement: .cancellationAction) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .foregroundStyle(AppColors.textPrimary)
                }
            }
            
            ToolbarItem(placement: .confirmationAction) {
                if !messages.isEmpty {
                    Button { messages.removeAll() } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(AppColors.textPrimary)
                    }
                }
            }
        }
        .sheet(isPresented: $showModelPicker) {
            modelPickerSheet
        }
        .onDisappear {
            streamingTask?.cancel()
        }
    }
    
    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(AppColors.accentCyan.opacity(0.1))
                    .frame(width: 96, height: 96)
                
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(AppColors.accentCyan)
            }
            
            Text("Start a Conversation")
                .font(AppFonts.headlineMedium())
                .foregroundStyle(AppColors.textPrimary)
            
            Text("Ask anything! The AI runs entirely on your device.")
                .font(AppFonts.bodyMedium())
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
            
            // Suggestion chips
            HStack(spacing: 8) {
                ForEach(["Tell me a joke", "What is AI?", "Write a haiku"], id: \.self) { suggestion in
                    Button {
                        inputText = suggestion
                        sendMessage()
                    } label: {
                        Text(suggestion)
                            .font(AppFonts.bodySmall())
                            .foregroundStyle(AppColors.textPrimary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(AppColors.surfaceCard)
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(AppColors.accentCyan.opacity(0.3), lineWidth: 1)
                            )
                    }
                }
            }
            .padding(.top, 8)
            
            Spacer()
        }
        .padding(32)
    }
    
    // MARK: - Messages List
    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(messages) { message in
                        ChatMessageBubble(message: message)
                            .id(message.id)
                    }
                    
                    if isGenerating {
                        let display = String.stripThinkingTags(currentResponse)
                        ChatMessageBubble(
                            message: ChatMessage(
                                text: display.isEmpty ? "Thinking..." : display,
                                isUser: false,
                                timestamp: Date()
                            ),
                            isStreaming: true
                        )
                        .id("streaming")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .onChange(of: messages.count) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: currentResponse) { _, _ in
                scrollToBottom(proxy: proxy)
            }
        }
    }
    
    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            if isGenerating {
                proxy.scrollTo("streaming", anchor: .bottom)
            } else if let lastMessage = messages.last {
                proxy.scrollTo(lastMessage.id, anchor: .bottom)
            }
        }
    }
    
    // MARK: - Input Area
    private var inputArea: some View {
        VStack(spacing: 0) {
            Divider()
                .background(AppColors.textMuted.opacity(0.1))
            
            HStack(spacing: 12) {
                // Text field
                TextField("Type a message...", text: $inputText, axis: .vertical)
                    .font(AppFonts.bodyLarge())
                    .foregroundStyle(AppColors.textPrimary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(AppColors.primaryMid)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .focused($isInputFocused)
                    .disabled(isGenerating)
                    .onSubmit {
                        sendMessage()
                    }
                
                // Send/Stop button
                if isGenerating {
                    Button {
                        stopGeneration()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(AppColors.error.opacity(0.2))
                            
                            Image(systemName: "stop.fill")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(AppColors.error)
                        }
                        .frame(width: 48, height: 48)
                    }
                } else {
                    Button {
                        sendMessage()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(AppColors.accentGradient)
                                .shadow(color: AppColors.accentCyan.opacity(0.3), radius: 12, y: 4)
                            
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(.white)
                        }
                        .frame(width: 48, height: 48)
                    }
                    .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(16)
            .background(AppColors.surfaceCard.opacity(0.8))
        }
    }
    
    // MARK: - Actions
    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty && !isGenerating else { return }
        
        // Add user message
        let userMessage = ChatMessage(text: text, isUser: true, timestamp: Date())
        messages.append(userMessage)
        inputText = ""
        isInputFocused = false
        
        // Start generation
        isGenerating = true
        currentResponse = ""
        
        streamingTask = Task {
            do {
                var options = RALLMGenerationOptions.defaults()
                options.maxTokens = 256
                options.temperature = 0.8
                options.systemPrompt = "You are a helpful assistant. Respond directly and concisely."

                let stream = try await RunAnywhere.generateStream(prompt: text, options: options)

                var tokensPerSecond: Double = 0
                var totalTokens = 0
                for await event in stream {
                    guard !Task.isCancelled else { break }
                    if !event.token.isEmpty {
                        await MainActor.run {
                            currentResponse += event.token
                        }
                    }
                    if event.isFinal, event.hasResult {
                        tokensPerSecond = Double(event.result.tokensPerSecond)
                        totalTokens = Int(event.result.totalTokens)
                    }
                }

                await MainActor.run {
                    if !Task.isCancelled {
                        let aiMessage = ChatMessage(
                            text: String.stripThinkingTags(currentResponse),
                            isUser: false,
                            timestamp: Date(),
                            tokensPerSecond: tokensPerSecond,
                            totalTokens: totalTokens
                        )
                        messages.append(aiMessage)
                    }
                    isGenerating = false
                    currentResponse = ""
                }
            } catch {
                await MainActor.run {
                    let errorMessage = ChatMessage(
                        text: "Error: \(error.localizedDescription)",
                        isUser: false,
                        timestamp: Date(),
                        isError: true
                    )
                    messages.append(errorMessage)
                    isGenerating = false
                    currentResponse = ""
                }
            }
        }
    }
    
    private func stopGeneration() {
        streamingTask?.cancel()
        
        if !currentResponse.isEmpty {
            let cancelledMessage = ChatMessage(
                text: currentResponse,
                isUser: false,
                timestamp: Date(),
                wasCancelled: true
            )
            messages.append(cancelledMessage)
        }
        
        isGenerating = false
        currentResponse = ""
    }

    // MARK: - Model Picker Sheet
    private var modelPickerSheet: some View {
        NavigationStack {
            ZStack {
                AppColors.primaryDark.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(LLMModelVariant.allCases) { variant in
                            let isSelected = variant == modelService.selectedLLMVariant
                            Button {
                                Task {
                                    await modelService.selectLLMVariant(variant)
                                    showModelPicker = false
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(variant.displayName)
                                            .font(AppFonts.bodyLarge())
                                            .fontWeight(.medium)
                                            .foregroundStyle(AppColors.textPrimary)
                                        Text("\(variant.sizeLabel) · \(variant.qualityLabel)")
                                            .font(AppFonts.bodySmall())
                                            .foregroundStyle(AppColors.textSecondary)
                                    }
                                    Spacer()
                                    if isSelected {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 22))
                                            .foregroundStyle(AppColors.accentCyan)
                                    }
                                }
                                .padding(14)
                                .background(isSelected ? AppColors.accentCyan.opacity(0.1) : AppColors.surfaceCard.opacity(0.5))
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(isSelected ? AppColors.accentCyan.opacity(0.4) : Color.clear, lineWidth: 1)
                                )
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Choose Model")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showModelPicker = false }
                        .foregroundStyle(AppColors.accentCyan)
                }
            }
        }
        .presentationDetents([.medium])
    }

}

#Preview {
    NavigationStack {
        ChatView()
            .environmentObject(ModelService())
    }
}
