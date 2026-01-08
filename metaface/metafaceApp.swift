//
//  metafaceApp.swift
//  metaface - Meta Glasses Face Age Estimation Companion
//
//  A companion app for Meta Ray-Ban glasses that uses the camera
//  to detect faces and estimate age in real-time.
//  Results are announced via voice through the glasses speakers.
//

import SwiftUI
import SwiftData
import AVFoundation
#if canImport(MWDATCore)
import MWDATCore
#endif
#if DEBUG && canImport(MWDATMockDevice)
import MWDATMockDevice
#endif

@main
struct MetafaceApp: App {

    // MARK: - SwiftData Model Container
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            FaceScan.self,
            ScanSession.self,
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    // MARK: - Services
    @StateObject private var glassesService = MetaGlassesService()
    @StateObject private var faceAnalysisService = FaceAnalysisService()
    @StateObject private var audioFeedbackService = AudioFeedbackService()
    @StateObject private var voiceCommandService = VoiceCommandService()

    // MARK: - App State
    @State private var showError = false
    @State private var errorMessage = ""

    init() {
        configureWearablesSDK()
        configureAppearance()
    }

    var body: some Scene {
        WindowGroup {
            MainNavigationView()
                .environmentObject(glassesService)
                .environmentObject(faceAnalysisService)
                .environmentObject(audioFeedbackService)
                .environmentObject(voiceCommandService)
                .onAppear {
                    setupVoiceFeedbackIntegration()
                }
                .onOpenURL { url in
                    handleIncomingURL(url)
                }
                .alert("Error", isPresented: $showError) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(errorMessage)
                }
        }
        .modelContainer(sharedModelContainer)
    }

    // MARK: - URL Handling (OAuth Callback)
    private func handleIncomingURL(_ url: URL) {
        #if canImport(MWDATCore)
        Task {
            let handled = await glassesService.handleURL(url)
            if handled {
                NSLog("[MetaFace] OAuth callback handled successfully")
            } else {
                NSLog("[MetaFace] URL not handled by SDK: \(url)")
            }
        }
        #endif
    }

    // MARK: - SDK Configuration
    private func configureWearablesSDK() {
        #if canImport(MWDATCore)
        do {
            try Wearables.configure()
            #if DEBUG
            NSLog("[MetaFace] Wearables SDK configured successfully")
            // Enable mock device for simulator testing
            setupMockDeviceIfNeeded()
            #endif
        } catch {
            #if DEBUG
            NSLog("[MetaFace] Failed to configure Wearables SDK: \(error)")
            #endif
            errorMessage = "Failed to initialize Meta Glasses SDK: \(error.localizedDescription)"
            showError = true
        }
        #else
        #if DEBUG
        NSLog("[MetaFace] Running without MWDATCore - using mock mode")
        #endif
        #endif
    }

    // MARK: - Mock Device Setup (For Testing)
    private func setupMockDeviceIfNeeded() {
        #if DEBUG && canImport(MWDATMockDevice)
        #if targetEnvironment(simulator)
        // Automatically create mock device on simulator
        Task { @MainActor in
            let mockKit = MockDeviceKit.shared
            let mockGlasses = mockKit.pairRaybanMeta()
            mockGlasses.powerOn()
            mockGlasses.unfold()
            mockGlasses.don()
            NSLog("[MetaFace] Mock Ray-Ban Meta device created for simulator testing")
        }
        #endif
        #endif
    }

    // MARK: - Voice Feedback Integration
    private func setupVoiceFeedbackIntegration() {
        // When faces are detected, announce via voice
        faceAnalysisService.onResultsUpdated = { [weak audioFeedbackService] results in
            guard let audioFeedbackService = audioFeedbackService else { return }
            Task { @MainActor in
                audioFeedbackService.announceMultipleFaces(results)
            }
        }

        // Voice commands
        voiceCommandService.onCommand = { [weak faceAnalysisService, weak glassesService, weak audioFeedbackService] command in
            Task { @MainActor in
                switch command {
                case .startScan, .scanFace, .checkAge:
                    faceAnalysisService?.startAnalysis()
                    audioFeedbackService?.announce(.scanStarted)

                case .stopScan:
                    faceAnalysisService?.stopAnalysis()
                    audioFeedbackService?.announce(.scanStopped)

                case .whatAge, .howOld:
                    if let latest = faceAnalysisService?.latestResult,
                       let ageResult = latest.ageEstimation {
                        audioFeedbackService?.announceAgeResult(ageResult)
                    } else {
                        audioFeedbackService?.announce(.noFaceDetected)
                    }

                case .status:
                    let status = glassesService?.connectionState.displayName ?? "Unknown"
                    audioFeedbackService?.speakCustom("Status: \(status)")

                case .help:
                    audioFeedbackService?.speakCustom("Say: start scan, stop scan, what age, or status")
                }
            }
        }
    }

    // MARK: - UI Configuration
    private func configureAppearance() {
        // Configure navigation bar appearance
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.8)
        appearance.titleTextAttributes = [.foregroundColor: UIColor.label]
        appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.label]

        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance

        // Configure tab bar appearance
        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithOpaqueBackground()
        tabAppearance.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.8)

        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance
    }
}
