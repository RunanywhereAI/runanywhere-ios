//
//  Swift_Starter_ExampleApp.swift
//  Swift-Starter-Example
//
//  RunAnywhere iOS SDK Starter App
//  Privacy-first, on-device AI for iOS
//

#if canImport(AppKit)
import AppKit
#endif
import SwiftUI
import RunAnywhere
import LlamaCPPRuntime
import MLXRuntime
import ONNXRuntime

@main
struct Swift_Starter_ExampleApp: App {
    @StateObject private var modelService = ModelService()
    @State private var isSDKInitialized = false
    
    var body: some Scene {
        WindowGroup {
            Group {
                if isSDKInitialized {
                    HomeView()
                        .environmentObject(modelService)
                } else {
                    // Loading view while SDK initializes
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Initializing AI...")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    #if os(iOS)
                    .background(Color(UIColor.systemBackground))
                    #else
                    .background(Color(NSColor.windowBackgroundColor))
                    #endif
                }
            }
            .preferredColorScheme(.dark)
            .task {
                // Use async initialization like the SDK example
                await initializeSDK()
            }
        }
    }
    
    @MainActor
    private func initializeSDK() async {
        do {
            // Initialize the RunAnywhere SDK in development mode
            try RunAnywhere.initialize(environment: .development)
            
            // Register backends BEFORE models
            LlamaCPP.register()
            MLX.register()
            ONNX.register()
            
            // Register default models - this must happen before model discovery completes
            await ModelService.registerDefaultModels()
            
            print("✅ RunAnywhere SDK initialized successfully")
            print("   Version: \(RunAnywhere.version)")
            
            // Mark as initialized
            isSDKInitialized = true
            
            // Refresh model service state after initialization
            await modelService.refreshLoadedStates()
            
        } catch {
            print("❌ Failed to initialize RunAnywhere SDK: \(error)")
            // Still show UI even if initialization fails
            isSDKInitialized = true
        }
    }
}
