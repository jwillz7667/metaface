//
//  FaceAnalysisService.swift
//  metaface
//
//  Combined service that orchestrates face detection and age estimation.
//

import Foundation
import Combine
import CoreGraphics
import UIKit
import CoreMedia

// MARK: - Analysis Result
struct FaceAnalysisResult: Identifiable {
    let id = UUID()
    let face: DetectedFace
    let ageEstimation: AgeEstimationResult?
    let faceImage: CGImage?
    let timestamp: Date

    var hasAgeEstimation: Bool {
        ageEstimation != nil
    }

    var displayAge: String {
        guard let age = ageEstimation else { return "N/A" }
        return String(format: "%.0f", age.estimatedAge)
    }

    var displayAgeRange: String {
        guard let age = ageEstimation else { return "Unknown" }
        return age.ageRangeString
    }

    var displayConfidence: String {
        guard let age = ageEstimation else { return "0%" }
        return age.confidencePercentage
    }

    var ageGroup: AgeGroup? {
        guard let age = ageEstimation else { return nil }
        return AgeGroup(age: age.estimatedAge)
    }
}

// MARK: - Analysis State
enum AnalysisState {
    case idle
    case analyzing
    case paused
    case error(String)

    var isActive: Bool {
        if case .analyzing = self { return true }
        return false
    }
}

// MARK: - Face Analysis Service
@MainActor
class FaceAnalysisService: ObservableObject {

    // MARK: - Published Properties
    @Published var analysisState: AnalysisState = .idle
    @Published var currentResults: [FaceAnalysisResult] = []
    @Published var latestResult: FaceAnalysisResult?
    @Published var totalFacesAnalyzed: Int = 0
    @Published var averageProcessingTime: TimeInterval = 0
    @Published var isProcessing: Bool = false

    // MARK: - Services
    private let faceDetectionService: FaceDetectionService
    private let ageEstimationService: AgeEstimationService

    // MARK: - Private Properties
    private var processingTimes: [TimeInterval] = []
    private var cancellables = Set<AnyCancellable>()
    private var isCurrentlyProcessing = false

    // Analysis callbacks
    var onResultsUpdated: (([FaceAnalysisResult]) -> Void)?
    var onFaceDetected: ((FaceScan) -> Void)?

    // MARK: - Initialization
    init(
        faceDetectionConfig: FaceDetectionConfiguration? = nil,
        ageEstimationConfig: AgeEstimationConfiguration? = nil
    ) {
        self.faceDetectionService = FaceDetectionService(configuration: faceDetectionConfig ?? .default)
        self.ageEstimationService = AgeEstimationService(configuration: ageEstimationConfig ?? .default)
    }

    // MARK: - Analysis Control
    func startAnalysis() {
        analysisState = .analyzing
        currentResults = []
    }

    func pauseAnalysis() {
        analysisState = .paused
    }

    func resumeAnalysis() {
        if case .paused = analysisState {
            analysisState = .analyzing
        }
    }

    func stopAnalysis() {
        analysisState = .idle
        currentResults = []
    }

    // MARK: - Frame Processing
    func processFrame(_ sampleBuffer: CMSampleBuffer) async {
        guard case .analyzing = analysisState,
              !isCurrentlyProcessing else { return }

        isCurrentlyProcessing = true
        isProcessing = true

        defer {
            Task { @MainActor in
                self.isCurrentlyProcessing = false
                self.isProcessing = false
            }
        }

        let startTime = Date()

        // Convert to CGImage
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let cgImage = createCGImage(from: imageBuffer) else {
            return
        }

        await processImage(cgImage, startTime: startTime)
    }

    func processImage(_ cgImage: CGImage) async {
        guard case .analyzing = analysisState,
              !isCurrentlyProcessing else { return }

        isCurrentlyProcessing = true
        isProcessing = true

        defer {
            Task { @MainActor in
                self.isCurrentlyProcessing = false
                self.isProcessing = false
            }
        }

        let startTime = Date()
        await processImage(cgImage, startTime: startTime)
    }

    private func processImage(_ cgImage: CGImage, startTime: Date) async {
        // Detect faces
        let detectedFaces = await faceDetectionService.detectFaces(in: cgImage)

        guard !detectedFaces.isEmpty else {
            await MainActor.run {
                self.currentResults = []
            }
            return
        }

        // Process each detected face
        var results: [FaceAnalysisResult] = []

        for face in detectedFaces {
            // Extract face image for age estimation
            let faceImage = faceDetectionService.extractFaceImage(from: cgImage, face: face, padding: 0.3)

            // Estimate age
            var ageEstimation: AgeEstimationResult?
            if let faceImage = faceImage {
                ageEstimation = await ageEstimationService.estimateAge(from: faceImage, withFace: face)
            }

            let result = FaceAnalysisResult(
                face: face,
                ageEstimation: ageEstimation,
                faceImage: faceImage,
                timestamp: Date()
            )

            results.append(result)

            // Create FaceScan for persistence
            if let ageEstimation = ageEstimation {
                let faceScan = FaceScan(
                    estimatedAge: ageEstimation.estimatedAge,
                    ageConfidence: ageEstimation.confidence,
                    ageRangeLow: ageEstimation.ageRangeLow,
                    ageRangeHigh: ageEstimation.ageRangeHigh,
                    faceConfidence: Double(face.confidence),
                    faceBounds: face.boundingBox,
                    hasSmile: false,
                    smileConfidence: 0,
                    eyesOpen: true,
                    eyesOpenConfidence: 0,
                    faceYaw: Double(face.yaw ?? 0),
                    facePitch: Double(face.pitch ?? 0),
                    faceRoll: Double(face.roll ?? 0),
                    faceQuality: Double(face.quality ?? 0.5),
                    thumbnailData: createThumbnailData(from: faceImage)
                )

                onFaceDetected?(faceScan)
            }
        }

        // Calculate processing time
        let processingTime = Date().timeIntervalSince(startTime)
        updateProcessingStats(processingTime)

        // Update results
        await MainActor.run {
            self.currentResults = results
            self.latestResult = results.first
            self.totalFacesAnalyzed += results.count
            self.onResultsUpdated?(results)
        }
    }

    // MARK: - Single Image Analysis
    func analyzeImage(_ cgImage: CGImage) async -> [FaceAnalysisResult] {
        let startTime = Date()

        // Detect faces
        let detectedFaces = await faceDetectionService.detectFaces(in: cgImage)

        guard !detectedFaces.isEmpty else {
            return []
        }

        var results: [FaceAnalysisResult] = []

        for face in detectedFaces {
            let faceImage = faceDetectionService.extractFaceImage(from: cgImage, face: face, padding: 0.3)

            var ageEstimation: AgeEstimationResult?
            if let faceImage = faceImage {
                ageEstimation = await ageEstimationService.estimateAge(from: faceImage, withFace: face)
            }

            let result = FaceAnalysisResult(
                face: face,
                ageEstimation: ageEstimation,
                faceImage: faceImage,
                timestamp: Date()
            )

            results.append(result)
        }

        let processingTime = Date().timeIntervalSince(startTime)
        await MainActor.run {
            self.updateProcessingStats(processingTime)
        }

        return results
    }

    // MARK: - Utility Methods
    private func createCGImage(from pixelBuffer: CVPixelBuffer) -> CGImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        return context.createCGImage(ciImage, from: ciImage.extent)
    }

    private func createThumbnailData(from cgImage: CGImage?) -> Data? {
        guard let cgImage = cgImage else { return nil }

        let size = CGSize(width: 150, height: 150)
        let renderer = UIGraphicsImageRenderer(size: size)
        let thumbnailImage = renderer.image { context in
            UIImage(cgImage: cgImage).draw(in: CGRect(origin: .zero, size: size))
        }

        return thumbnailImage.jpegData(compressionQuality: 0.7)
    }

    private func updateProcessingStats(_ time: TimeInterval) {
        processingTimes.append(time)

        // Keep last 30 samples
        if processingTimes.count > 30 {
            processingTimes.removeFirst()
        }

        averageProcessingTime = processingTimes.reduce(0, +) / Double(processingTimes.count)
    }

    // MARK: - Configuration Updates
    func updateFaceDetectionConfig(_ config: FaceDetectionConfiguration) {
        faceDetectionService.updateConfiguration(config)
    }

    func updateAgeEstimationConfig(_ config: AgeEstimationConfiguration) {
        ageEstimationService.updateConfiguration(config)
    }
}
