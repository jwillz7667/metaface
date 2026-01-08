//
//  LiveScanView.swift
//  metaface
//
//  Live camera feed view with face detection and age estimation overlay.
//

import SwiftUI
import SwiftData

struct LiveScanView: View {
    @EnvironmentObject var glassesService: MetaGlassesService
    @EnvironmentObject var faceAnalysisService: FaceAnalysisService
    @Environment(\.modelContext) private var modelContext

    @State private var isScanning = false
    @State private var showResults = false
    @State private var currentSession: ScanSession?
    @State private var showConnectionPrompt = false
    @State private var capturedScans: [FaceScan] = []

    // Animation states
    @State private var pulseAnimation = false

    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                Color.black.ignoresSafeArea()

                if glassesService.connectionState.isConnected {
                    // Camera preview
                    cameraPreviewView

                    // Overlay UI
                    VStack {
                        // Top bar
                        topControlBar
                            .padding(.top, 8)

                        Spacer()

                        // Face detection overlays
                        faceOverlays

                        Spacer()

                        // Results panel
                        if !faceAnalysisService.currentResults.isEmpty {
                            resultsPanel
                        }

                        // Bottom controls
                        bottomControlBar
                            .padding(.bottom, 20)
                    }
                    .padding()
                } else {
                    // Not connected state
                    notConnectedView
                }
            }
            .navigationTitle("Face Scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showConnectionPrompt = true
                    } label: {
                        Image(systemName: glassesService.connectionState.isConnected ? "link.circle.fill" : "link.circle")
                            .foregroundStyle(glassesService.connectionState.isConnected ? .green : .white)
                    }
                }
            }
            .sheet(isPresented: $showConnectionPrompt) {
                ConnectionView()
            }
            .onDisappear {
                stopScanning()
            }
        }
    }

    // MARK: - Camera Preview
    private var cameraPreviewView: some View {
        GeometryReader { geometry in
            ZStack {
                if let cgImage = glassesService.lastFrameImage {
                    Image(decorative: cgImage, scale: 1.0)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                } else {
                    // Placeholder when no frame
                    Rectangle()
                        .fill(Color.black)
                        .overlay {
                            VStack(spacing: 16) {
                                Image(systemName: "video.fill")
                                    .font(.system(size: 50))
                                    .foregroundStyle(.gray)

                                Text(glassesService.isStreaming ? "Waiting for video..." : "Tap Start to begin")
                                    .foregroundStyle(.gray)
                            }
                        }
                }

                // Scanning animation overlay
                if isScanning && faceAnalysisService.isProcessing {
                    scanningOverlay
                }
            }
        }
    }

    private var scanningOverlay: some View {
        ZStack {
            // Corner brackets
            VStack {
                HStack {
                    ScanCorner(rotation: 0)
                    Spacer()
                    ScanCorner(rotation: 90)
                }
                Spacer()
                HStack {
                    ScanCorner(rotation: 270)
                    Spacer()
                    ScanCorner(rotation: 180)
                }
            }
            .padding(40)
            .opacity(pulseAnimation ? 1 : 0.5)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulseAnimation)
        }
        .onAppear {
            pulseAnimation = true
        }
    }

    // MARK: - Face Overlays
    private var faceOverlays: some View {
        GeometryReader { geometry in
            ForEach(faceAnalysisService.currentResults) { result in
                let bounds = result.face.normalizedBounds(for: geometry.size)

                ZStack(alignment: .topLeading) {
                    // Face bounding box
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            result.hasAgeEstimation ? Color.green : Color.yellow,
                            lineWidth: 2
                        )
                        .frame(width: bounds.width, height: bounds.height)

                    // Age label
                    if let ageEstimation = result.ageEstimation {
                        AgeLabel(
                            age: ageEstimation.estimatedAge,
                            confidence: ageEstimation.confidence
                        )
                        .offset(y: -30)
                    }
                }
                .position(
                    x: bounds.midX,
                    y: bounds.midY
                )
            }
        }
    }

    // MARK: - Top Control Bar
    private var topControlBar: some View {
        HStack {
            // Stream info
            if glassesService.isStreaming {
                HStack(spacing: 8) {
                    Circle()
                        .fill(.red)
                        .frame(width: 8, height: 8)

                    Text(formatDuration(glassesService.streamDuration))
                        .font(.caption)
                        .monospacedDigit()

                    Text("•")
                        .foregroundStyle(.secondary)

                    Text("\(Int(glassesService.currentFPS)) FPS")
                        .font(.caption)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
            }

            Spacer()

            // Scan count
            if isScanning {
                HStack(spacing: 6) {
                    Image(systemName: "person.viewfinder")
                    Text("\(capturedScans.count)")
                        .monospacedDigit()
                }
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
            }
        }
        .foregroundStyle(.white)
    }

    // MARK: - Results Panel
    private var resultsPanel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(faceAnalysisService.currentResults) { result in
                    FaceResultCard(result: result)
                }
            }
            .padding(.horizontal)
        }
        .frame(height: 120)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Bottom Control Bar
    private var bottomControlBar: some View {
        HStack(spacing: 30) {
            // Capture button
            Button {
                captureCurrentFrame()
            } label: {
                Image(systemName: "camera.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
            .disabled(!isScanning)
            .opacity(isScanning ? 1 : 0.5)

            // Main scan button
            Button {
                if isScanning {
                    stopScanning()
                } else {
                    startScanning()
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(isScanning ? Color.red : Color.white)
                        .frame(width: 70, height: 70)

                    if isScanning {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.white)
                            .frame(width: 24, height: 24)
                    } else {
                        Image(systemName: "play.fill")
                            .font(.title)
                            .foregroundStyle(.black)
                    }
                }
            }

            // Toggle results
            Button {
                showResults.toggle()
            } label: {
                Image(systemName: showResults ? "list.bullet.circle.fill" : "list.bullet.circle")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
        }
    }

    // MARK: - Not Connected View
    private var notConnectedView: some View {
        VStack(spacing: 24) {
            Image(systemName: "eyeglasses")
                .font(.system(size: 60))
                .foregroundStyle(.gray)

            VStack(spacing: 8) {
                Text("No Glasses Connected")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)

                Text("Connect your Meta glasses to start scanning faces")
                    .font(.subheadline)
                    .foregroundStyle(.gray)
                    .multilineTextAlignment(.center)
            }

            Button {
                showConnectionPrompt = true
            } label: {
                Label("Connect Glasses", systemImage: "link")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
        }
        .padding()
    }

    // MARK: - Actions
    private func startScanning() {
        Task {
            // Start stream if not already streaming
            if !glassesService.isStreaming {
                let success = await glassesService.startStreaming()
                guard success else { return }
            }

            // Create new session
            let session = ScanSession(
                deviceName: glassesService.connectedDevice?.displayName ?? "Unknown",
                deviceIdentifier: glassesService.connectedDevice?.id ?? ""
            )
            modelContext.insert(session)
            currentSession = session

            // Start face analysis
            faceAnalysisService.startAnalysis()

            // Set up frame processing
            glassesService.onFrameReceived = { [weak faceAnalysisService] frameData in
                Task {
                    await faceAnalysisService?.processFrame(frameData.sampleBuffer)
                }
            }

            // Set up scan capture - capture mutable state via Binding
            let capturedScansBinding = $capturedScans
            let currentSessionBinding = $currentSession
            let ctx = modelContext
            faceAnalysisService.onFaceDetected = { scan in
                Task { @MainActor in
                    capturedScansBinding.wrappedValue.append(scan)
                    currentSessionBinding.wrappedValue?.addScan(scan)
                    ctx.insert(scan)
                }
            }

            isScanning = true
        }
    }

    private func stopScanning() {
        isScanning = false
        faceAnalysisService.stopAnalysis()
        glassesService.onFrameReceived = nil

        // End session
        currentSession?.endSession()
        currentSession = nil
    }

    private func captureCurrentFrame() {
        Task {
            if let image = await glassesService.capturePhoto() {
                let results = await faceAnalysisService.analyzeImage(image)

                for result in results {
                    if let ageEstimation = result.ageEstimation {
                        let scan = FaceScan(
                            estimatedAge: ageEstimation.estimatedAge,
                            ageConfidence: ageEstimation.confidence,
                            ageRangeLow: ageEstimation.ageRangeLow,
                            ageRangeHigh: ageEstimation.ageRangeHigh,
                            faceConfidence: Double(result.face.confidence),
                            faceBounds: result.face.boundingBox,
                            faceYaw: Double(result.face.yaw ?? 0),
                            facePitch: Double(result.face.pitch ?? 0),
                            faceRoll: Double(result.face.roll ?? 0),
                            faceQuality: Double(result.face.quality ?? 0.5)
                        )

                        capturedScans.append(scan)
                        currentSession?.addScan(scan)
                        modelContext.insert(scan)
                    }
                }
            }
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", minutes, secs)
    }
}

// MARK: - Supporting Views
struct ScanCorner: View {
    let rotation: Double

    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 20))
            path.addLine(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: 20, y: 0))
        }
        .stroke(Color.green, lineWidth: 3)
        .frame(width: 20, height: 20)
        .rotationEffect(.degrees(rotation))
    }
}

struct AgeLabel: View {
    let age: Double
    let confidence: Double

    var body: some View {
        HStack(spacing: 4) {
            Text(String(format: "%.0f", age))
                .font(.headline)
                .fontWeight(.bold)

            Text("yrs")
                .font(.caption)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(confidenceColor.opacity(0.9))
        .foregroundStyle(.white)
        .clipShape(Capsule())
    }

    private var confidenceColor: Color {
        switch confidence {
        case 0.8...1.0: return .green
        case 0.6..<0.8: return .blue
        case 0.4..<0.6: return .orange
        default: return .red
        }
    }
}

struct FaceResultCard: View {
    let result: FaceAnalysisResult

    var body: some View {
        VStack(spacing: 8) {
            // Face thumbnail
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 60, height: 60)

                if let faceImage = result.faceImage {
                    Image(decorative: faceImage, scale: 1.0)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Image(systemName: "person.fill")
                        .foregroundStyle(.white.opacity(0.5))
                }
            }

            VStack(spacing: 2) {
                Text(result.displayAge)
                    .font(.headline)
                    .foregroundStyle(.white)

                Text(result.displayAgeRange)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))

                Text(result.displayConfidence)
                    .font(.caption2)
                    .foregroundStyle(.green)
            }
        }
        .padding(8)
        .background(Color.black.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    LiveScanView()
        .environmentObject(MetaGlassesService())
        .environmentObject(FaceAnalysisService())
        .modelContainer(for: [FaceScan.self, ScanSession.self], inMemory: true)
}
