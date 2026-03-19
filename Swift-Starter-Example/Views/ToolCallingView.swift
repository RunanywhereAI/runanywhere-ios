//
//  ToolCallingView.swift
//  Swift-Starter-Example
//
//  RunAnywhere iOS SDK Starter App - Tool Calling Demo
//

import SwiftUI
import RunAnywhere

struct ToolCallingView: View {
    @EnvironmentObject var modelService: ModelService
    
    @State private var prompt = ""
    @State private var isGenerating = false
    @State private var toolsRegistered = false
    @State private var logs: [LogEntry] = []
    @State private var errorMessage: String?
    
    struct LogEntry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let type: LogType
        let message: String
        
        enum LogType {
            case info, toolCall, toolResult, response, error
            
            var color: Color {
                switch self {
                case .info: return AppColors.accentCyan
                case .toolCall: return AppColors.accentOrange
                case .toolResult: return AppColors.accentGreen
                case .response: return AppColors.accentViolet
                case .error: return AppColors.error
                }
            }
            
            var icon: String {
                switch self {
                case .info: return "info.circle.fill"
                case .toolCall: return "wrench.fill"
                case .toolResult: return "checkmark.circle.fill"
                case .response: return "text.bubble.fill"
                case .error: return "exclamationmark.triangle.fill"
                }
            }
        }
    }
    
    var body: some View {
        ZStack {
            AppColors.backgroundGradient.ignoresSafeArea()
            
            if !modelService.isLLMLoaded {
                ModelLoaderView(
                    title: "LLM Model Required",
                    subtitle: "Download and load the language model to test tool calling",
                    icon: "wrench.and.screwdriver.fill",
                    accentColor: AppColors.accentOrange,
                    isDownloading: modelService.isLLMDownloading,
                    isLoading: modelService.isLLMLoading,
                    progress: modelService.llmDownloadProgress
                ) {
                    Task { await modelService.downloadAndLoadLLM() }
                }
            } else {
                VStack(spacing: 0) {
                    // Tool status bar
                    toolStatusBar
                    
                    // Log output
                    logView
                    
                    // Input area
                    inputArea
                }
            }
        }
        .navigationTitle("Tool Calling")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            if !toolsRegistered {
                registerDemoTools()
            }
        }
    }
    
    // MARK: - Tool Status Bar
    private var toolStatusBar: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(toolsRegistered ? AppColors.success : AppColors.warning)
                .frame(width: 8, height: 8)
            
            Text(toolsRegistered ? "3 tools registered" : "No tools registered")
                .font(AppFonts.bodySmall())
                .foregroundStyle(AppColors.textSecondary)
            
            Spacer()
            
            Button(toolsRegistered ? "Re-register" : "Register Tools") {
                registerDemoTools()
            }
            .font(AppFonts.labelSmall())
            .foregroundStyle(AppColors.accentOrange)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(AppColors.surfaceCard.opacity(0.5))
    }
    
    // MARK: - Log View
    private var logView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if logs.isEmpty {
                        emptyState
                    } else {
                        ForEach(logs) { log in
                            logEntryView(log)
                                .id(log.id)
                        }
                    }
                }
                .padding(20)
            }
            .onChange(of: logs.count) { _, _ in
                if let lastLog = logs.last {
                    withAnimation {
                        proxy.scrollTo(lastLog.id, anchor: .bottom)
                    }
                }
            }
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "wrench.and.screwdriver.fill")
                .font(.system(size: 48))
                .foregroundStyle(AppColors.accentOrange.opacity(0.5))
            
            Text("Tool Calling Demo")
                .font(AppFonts.titleLarge())
                .foregroundStyle(AppColors.textPrimary)
            
            Text("Ask something that requires tools, like:\n\"What's the weather in San Francisco?\"\n\"Calculate 42 * 17\"\n\"What time is it?\"")
                .font(AppFonts.bodyMedium())
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
            
            // Quick prompts
            VStack(spacing: 8) {
                quickPromptButton("What's the weather in Tokyo?")
                quickPromptButton("Calculate 123 + 456")
                quickPromptButton("What time is it right now?")
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
    
    private func quickPromptButton(_ text: String) -> some View {
        Button {
            prompt = text
            Task { await generateWithTools() }
        } label: {
            Text(text)
                .font(AppFonts.bodySmall())
                .foregroundStyle(AppColors.accentOrange)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(AppColors.surfaceCard)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(AppColors.accentOrange.opacity(0.3), lineWidth: 1)
                )
        }
        .disabled(isGenerating)
    }
    
    private func logEntryView(_ entry: LogEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: entry.type.icon)
                .font(.system(size: 14))
                .foregroundStyle(entry.type.color)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.message)
                    .font(entry.type == .response ? AppFonts.bodyMedium() : AppFonts.bodySmall())
                    .foregroundStyle(entry.type == .response ? AppColors.textPrimary : AppColors.textSecondary)
                    .textSelection(.enabled)
                
                Text(entry.timestamp, style: .time)
                    .font(.system(size: 10))
                    .foregroundStyle(AppColors.textMuted)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(entry.type.color.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(entry.type.color.opacity(0.15), lineWidth: 1)
        )
    }
    
    // MARK: - Input Area
    private var inputArea: some View {
        HStack(spacing: 12) {
            TextField("Ask something requiring tools...", text: $prompt)
                .font(AppFonts.bodyMedium())
                .foregroundStyle(AppColors.textPrimary)
                .padding(14)
                .background(AppColors.surfaceCard)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(AppColors.textMuted.opacity(0.2), lineWidth: 1)
                )
            
            Button {
                Task { await generateWithTools() }
            } label: {
                Image(systemName: isGenerating ? "stop.fill" : "paperplane.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(
                        isGenerating
                        ? AnyShapeStyle(AppColors.error)
                        : AnyShapeStyle(LinearGradient(colors: [AppColors.accentOrange, Color(hex: "E67E22")], startPoint: .topLeading, endPoint: .bottomTrailing))
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(prompt.isEmpty && !isGenerating)
        }
        .padding(20)
        .background(AppColors.primaryDark.opacity(0.9))
    }
    
    // MARK: - Tool Registration
    private func registerDemoTools() {
        Task {
            // Clear existing tools
            await RunAnywhere.clearTools()
            
            // 1. Weather tool
            let weatherTool = ToolDefinition(
                name: "get_weather",
                description: "Gets the current weather for a given city",
                parameters: [
                    ToolParameter(name: "city", type: .string, description: "The city name", required: true)
                ]
            )
            await RunAnywhere.registerTool(weatherTool) { args in
                let city = args["city"]?.stringValue ?? "Unknown"
                let temp = Int.random(in: 15...35)
                let conditions = ["Sunny", "Cloudy", "Rainy", "Partly Cloudy"].randomElement()!
                return [
                    "city": .string(city),
                    "temperature": .number(Double(temp)),
                    "unit": .string("celsius"),
                    "conditions": .string(conditions)
                ]
            }
            
            // 2. Calculator tool
            let calcTool = ToolDefinition(
                name: "calculate",
                description: "Performs basic arithmetic calculation",
                parameters: [
                    ToolParameter(name: "expression", type: .string, description: "Math expression like '2 + 3'", required: true)
                ]
            )
            await RunAnywhere.registerTool(calcTool) { args in
                let expr = args["expression"]?.stringValue ?? "0"
                // Simple eval via NSExpression
                let nsExpr = NSExpression(format: expr)
                let result = nsExpr.expressionValue(with: nil, context: nil) as? Double ?? 0
                return [
                    "expression": .string(expr),
                    "result": .number(result)
                ]
            }
            
            // 3. Time tool
            let timeTool = ToolDefinition(
                name: "get_time",
                description: "Gets the current date and time",
                parameters: []
            )
            await RunAnywhere.registerTool(timeTool) { _ in
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                return [
                    "datetime": .string(formatter.string(from: Date())),
                    "timezone": .string(TimeZone.current.identifier)
                ]
            }
            
            toolsRegistered = true
            addLog(.info, "Registered 3 tools: get_weather, calculate, get_time")
        }
    }
    
    // MARK: - Generate with Tools
    private func generateWithTools() async {
        let userPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userPrompt.isEmpty else { return }
        
        isGenerating = true
        prompt = ""
        addLog(.info, "Prompt: \"\(userPrompt)\"")
        
        do {
            let options = ToolCallingOptions(
                maxToolCalls: 3,
                autoExecute: true,
                temperature: 0.7,
                maxTokens: 512,
                systemPrompt: "You are a helpful assistant with access to tools. Use them when appropriate."
            )
            
            let result = try await RunAnywhere.generateWithTools(userPrompt, options: options)
            
            // Log tool calls
            for (i, call) in result.toolCalls.enumerated() {
                let argsStr = call.arguments.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
                addLog(.toolCall, "Tool call #\(i+1): \(call.toolName)(\(argsStr))")
                
                if i < result.toolResults.count {
                    let tr = result.toolResults[i]
                    if tr.success, let resultDict = tr.result {
                        let resultStr = resultDict.keys.sorted().map { key in
                            "\(key): \(resultDict[key].map { "\($0)" } ?? "nil")"
                        }.joined(separator: ", ")
                        addLog(.toolResult, "Result: \(resultStr)")
                    } else if !tr.success {
                        addLog(.error, "Tool error: \(tr.error ?? "Unknown")")
                    }
                }
            }
            
            let cleanedText = String.stripThinkingTags(result.text)
            if !cleanedText.isEmpty {
                addLog(.response, cleanedText)
            }
            
            if result.toolCalls.isEmpty {
                addLog(.info, "No tool calls were made - model responded directly")
            }
            
        } catch {
            addLog(.error, "Error: \(error.localizedDescription)")
        }
        
        isGenerating = false
    }
    
    private func addLog(_ type: LogEntry.LogType, _ message: String) {
        logs.append(LogEntry(timestamp: Date(), type: type, message: message))
    }
}

#Preview {
    NavigationStack {
        ToolCallingView()
            .environmentObject(ModelService())
    }
}
