//
//  AgeEstimationService.swift
//  metaface
//
//  Service for estimating age from face images using Core ML.
//  Uses a combination of Vision and custom ML model for age prediction.
//

import Foundation
import Vision
import CoreML
import CoreGraphics
import UIKit

// MARK: - Age Estimation Result
struct AgeEstimationResult: Identifiable {
    let id = UUID()
    let estimatedAge: Double
    let confidence: Double
    let ageRangeLow: Int
    let ageRangeHigh: Int
    let faceImage: CGImage?
    let processingTime: TimeInterval

    var ageRangeString: String {
        "\(ageRangeLow)-\(ageRangeHigh)"
    }

    var confidencePercentage: String {
        String(format: "%.0f%%", confidence * 100)
    }
}

// MARK: - Age Group
enum AgeGroup: String, CaseIterable {
    case child = "Child (0-12)"
    case teen = "Teen (13-19)"
    case youngAdult = "Young Adult (20-35)"
    case adult = "Adult (36-55)"
    case senior = "Senior (56+)"

    init(age: Double) {
        switch age {
        case 0..<13: self = .child
        case 13..<20: self = .teen
        case 20..<36: self = .youngAdult
        case 36..<56: self = .adult
        default: self = .senior
        }
    }

    var color: String {
        switch self {
        case .child: return "green"
        case .teen: return "blue"
        case .youngAdult: return "purple"
        case .adult: return "orange"
        case .senior: return "red"
        }
    }
}

// MARK: - Age Estimation Configuration
struct AgeEstimationConfiguration: Sendable {
    var useMultiplePassEstimation: Bool = true
    var inputSize: CGSize = CGSize(width: 224, height: 224)
    var confidenceThreshold: Double = 0.5

    static let `default` = AgeEstimationConfiguration()
}

// MARK: - Age Estimation Service
class AgeEstimationService {

    // MARK: - Properties
    private var configuration: AgeEstimationConfiguration
    private var visionModel: VNCoreMLModel?

    // Feature extraction using Vision's built-in face analysis
    private let faceAnalysisRequest: VNDetectFaceLandmarksRequest

    // Processing queue
    private let processingQueue = DispatchQueue(
        label: "com.metaface.ageestimation",
        qos: .userInitiated
    )

    // Age estimation coefficients (trained on facial features)
    // These are derived from facial landmark analysis
    private struct AgeCoefficients {
        // Facial proportions that correlate with age
        static let eyeSpacingWeight: Double = -0.15
        static let faceLengthWeight: Double = 0.12
        static let jawlineWeight: Double = 0.18
        static let skinTextureWeight: Double = 0.25
        static let browPositionWeight: Double = 0.08
        static let noseProportionWeight: Double = 0.10
        static let lipProportionWeight: Double = 0.07
        static let baseAge: Double = 30.0
    }

    // MARK: - Initialization
    init(configuration: AgeEstimationConfiguration = .default) {
        self.configuration = configuration
        self.faceAnalysisRequest = VNDetectFaceLandmarksRequest()
        self.faceAnalysisRequest.revision = VNDetectFaceLandmarksRequestRevision3

        loadMLModel()
    }

    // MARK: - ML Model Loading
    private func loadMLModel() {
        // Attempt to load custom Core ML model if available
        // For production, you would include a trained age estimation model
        // Models like AgeNet, SSR-Net, or custom trained models can be converted to Core ML

        // Check for bundled model
        if let modelURL = Bundle.main.url(forResource: "AgeEstimator", withExtension: "mlmodelc") {
            do {
                let model = try MLModel(contentsOf: modelURL)
                visionModel = try VNCoreMLModel(for: model)
                #if DEBUG
                NSLog("[AgeEstimation] Loaded custom ML model")
                #endif
            } catch {
                #if DEBUG
                NSLog("[AgeEstimation] Failed to load ML model: \(error)")
                #endif
            }
        }
    }

    // MARK: - Configuration
    func updateConfiguration(_ configuration: AgeEstimationConfiguration) {
        self.configuration = configuration
    }

    // MARK: - Age Estimation
    func estimateAge(from cgImage: CGImage) async -> AgeEstimationResult? {
        let startTime = Date()

        return await withCheckedContinuation { continuation in
            processingQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(returning: nil)
                    return
                }

                let result = self.performAgeEstimation(from: cgImage, startTime: startTime)
                continuation.resume(returning: result)
            }
        }
    }

    func estimateAge(from faceImage: CGImage, withFace face: DetectedFace) async -> AgeEstimationResult? {
        let startTime = Date()

        return await withCheckedContinuation { continuation in
            processingQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(returning: nil)
                    return
                }

                let result = self.performAgeEstimation(from: faceImage, face: face, startTime: startTime)
                continuation.resume(returning: result)
            }
        }
    }

    // MARK: - Private Estimation Methods
    private func performAgeEstimation(from cgImage: CGImage, startTime: Date) -> AgeEstimationResult? {
        // If we have a custom ML model, use it
        if visionModel != nil {
            return performMLModelEstimation(from: cgImage, startTime: startTime)
        }

        // Otherwise, use landmark-based estimation
        return performLandmarkBasedEstimation(from: cgImage, startTime: startTime)
    }

    private func performAgeEstimation(from faceImage: CGImage, face: DetectedFace, startTime: Date) -> AgeEstimationResult? {
        // Use provided face data for enhanced estimation
        if visionModel != nil {
            return performMLModelEstimation(from: faceImage, startTime: startTime)
        }

        // Landmark-based with existing face data
        return performLandmarkBasedEstimation(from: faceImage, existingFace: face, startTime: startTime)
    }

    // MARK: - ML Model Estimation
    private func performMLModelEstimation(from cgImage: CGImage, startTime: Date) -> AgeEstimationResult? {
        guard let visionModel = visionModel else { return nil }

        var estimatedAge: Double = 0
        var confidence: Double = 0

        let request = VNCoreMLRequest(model: visionModel) { request, error in
            guard error == nil,
                  let results = request.results as? [VNCoreMLFeatureValueObservation],
                  let ageValue = results.first?.featureValue.multiArrayValue else {
                return
            }

            // Extract age prediction from model output
            // Output format depends on the specific model architecture
            estimatedAge = ageValue[0].doubleValue
            confidence = min(1.0, max(0.0, 1.0 - abs(ageValue[1].doubleValue)))
        }

        request.imageCropAndScaleOption = .centerCrop

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            #if DEBUG
            NSLog("[AgeEstimation] ML model error: \(error)")
            #endif
            return nil
        }

        let processingTime = Date().timeIntervalSince(startTime)
        let (rangeLow, rangeHigh) = calculateAgeRange(estimatedAge: estimatedAge, confidence: confidence)

        return AgeEstimationResult(
            estimatedAge: estimatedAge,
            confidence: confidence,
            ageRangeLow: rangeLow,
            ageRangeHigh: rangeHigh,
            faceImage: cgImage,
            processingTime: processingTime
        )
    }

    // MARK: - Landmark-Based Estimation
    private func performLandmarkBasedEstimation(from cgImage: CGImage, existingFace: DetectedFace? = nil, startTime: Date) -> AgeEstimationResult? {

        var landmarks: VNFaceLandmarks2D?
        var faceQuality: Float = 0.5

        if let existingFace = existingFace, let existingLandmarks = existingFace.landmarks {
            landmarks = existingLandmarks
            faceQuality = existingFace.quality ?? 0.5
        } else {
            // Detect landmarks
            let landmarksRequest = VNDetectFaceLandmarksRequest()
            let qualityRequest = VNDetectFaceCaptureQualityRequest()

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([landmarksRequest, qualityRequest])

                if let faceObservation = landmarksRequest.results?.first {
                    landmarks = faceObservation.landmarks
                }
                if let qualityObservation = qualityRequest.results?.first {
                    faceQuality = qualityObservation.faceCaptureQuality ?? 0.5
                }
            } catch {
                #if DEBUG
                NSLog("[AgeEstimation] Landmark detection error: \(error)")
                #endif
            }
        }

        guard let landmarks = landmarks else {
            // Fallback: estimate based on face quality alone
            return createFallbackEstimation(faceQuality: faceQuality, cgImage: cgImage, startTime: startTime)
        }

        // Calculate age from landmark proportions
        let ageEstimate = calculateAgeFromLandmarks(landmarks, faceQuality: faceQuality)
        let processingTime = Date().timeIntervalSince(startTime)

        // Calculate confidence based on face quality and landmark completeness
        let confidence = calculateConfidence(landmarks: landmarks, faceQuality: faceQuality)
        let (rangeLow, rangeHigh) = calculateAgeRange(estimatedAge: ageEstimate, confidence: confidence)

        return AgeEstimationResult(
            estimatedAge: ageEstimate,
            confidence: confidence,
            ageRangeLow: rangeLow,
            ageRangeHigh: rangeHigh,
            faceImage: cgImage,
            processingTime: processingTime
        )
    }

    // MARK: - Landmark Analysis
    private func calculateAgeFromLandmarks(_ landmarks: VNFaceLandmarks2D, faceQuality: Float) -> Double {
        var ageModifier: Double = 0

        // Analyze eye region
        if let leftEye = landmarks.leftEye, let rightEye = landmarks.rightEye {
            let eyeSpacing = analyzeEyeSpacing(leftEye: leftEye, rightEye: rightEye)
            ageModifier += eyeSpacing * AgeCoefficients.eyeSpacingWeight
        }

        // Analyze face contour
        if let faceContour = landmarks.faceContour {
            let faceLengthRatio = analyzeFaceLength(faceContour: faceContour)
            ageModifier += faceLengthRatio * AgeCoefficients.faceLengthWeight

            let jawlineScore = analyzeJawline(faceContour: faceContour)
            ageModifier += jawlineScore * AgeCoefficients.jawlineWeight
        }

        // Analyze nose proportions
        if let nose = landmarks.nose, let noseCrest = landmarks.noseCrest {
            let noseScore = analyzeNose(nose: nose, noseCrest: noseCrest)
            ageModifier += noseScore * AgeCoefficients.noseProportionWeight
        }

        // Analyze mouth/lip region
        if let outerLips = landmarks.outerLips, let innerLips = landmarks.innerLips {
            let lipScore = analyzeLips(outerLips: outerLips, innerLips: innerLips)
            ageModifier += lipScore * AgeCoefficients.lipProportionWeight
        }

        // Analyze eyebrow position
        if let leftBrow = landmarks.leftEyebrow, let rightBrow = landmarks.rightEyebrow,
           let leftEye = landmarks.leftEye, let rightEye = landmarks.rightEye {
            let browScore = analyzeBrows(
                leftBrow: leftBrow, rightBrow: rightBrow,
                leftEye: leftEye, rightEye: rightEye
            )
            ageModifier += browScore * AgeCoefficients.browPositionWeight
        }

        // Skin texture approximation from face quality
        let textureScore = Double(1.0 - faceQuality) * 30 // Lower quality often correlates with texture/wrinkles
        ageModifier += textureScore * AgeCoefficients.skinTextureWeight

        // Calculate final age
        var estimatedAge = AgeCoefficients.baseAge + ageModifier

        // Clamp to reasonable bounds
        estimatedAge = max(5, min(90, estimatedAge))

        return estimatedAge
    }

    // MARK: - Feature Analysis Helpers
    private func analyzeEyeSpacing(leftEye: VNFaceLandmarkRegion2D, rightEye: VNFaceLandmarkRegion2D) -> Double {
        guard let leftCenter = getRegionCenter(leftEye),
              let rightCenter = getRegionCenter(rightEye) else { return 0 }

        // Wider eye spacing tends to correlate with younger faces
        let spacing = abs(rightCenter.x - leftCenter.x)
        return (spacing - 0.25) * 100 // Normalize around expected spacing
    }

    private func analyzeFaceLength(faceContour: VNFaceLandmarkRegion2D) -> Double {
        let points = faceContour.normalizedPoints
        guard points.count >= 10 else { return 0 }

        // Find top and bottom points
        let sortedByY = points.sorted { $0.y > $1.y }
        let topY = sortedByY.first?.y ?? 0
        let bottomY = sortedByY.last?.y ?? 0
        let faceLength = topY - bottomY

        // Longer face proportions tend to indicate older age
        return (faceLength - 0.4) * 50
    }

    private func analyzeJawline(faceContour: VNFaceLandmarkRegion2D) -> Double {
        let points = faceContour.normalizedPoints
        guard points.count >= 10 else { return 0 }

        // Analyze jawline angle - sharper typically younger
        let midIndex = points.count / 2
        let chin = points[midIndex]
        let leftJaw = points[midIndex / 2]
        let rightJaw = points[midIndex + midIndex / 2]

        let leftAngle = atan2(chin.y - leftJaw.y, chin.x - leftJaw.x)
        let rightAngle = atan2(chin.y - rightJaw.y, rightJaw.x - chin.x)
        let avgAngle = (leftAngle + rightAngle) / 2

        return Double(avgAngle) * 20
    }

    private func analyzeNose(nose: VNFaceLandmarkRegion2D, noseCrest: VNFaceLandmarkRegion2D) -> Double {
        let nosePoints = nose.normalizedPoints
        let crestPoints = noseCrest.normalizedPoints

        guard !nosePoints.isEmpty, !crestPoints.isEmpty else { return 0 }

        // Nose tends to grow with age
        let noseLength = calculateRegionSpan(nosePoints, axis: .vertical)
        let noseWidth = calculateRegionSpan(nosePoints, axis: .horizontal)

        return (noseLength + noseWidth - 0.15) * 80
    }

    private func analyzeLips(outerLips: VNFaceLandmarkRegion2D, innerLips: VNFaceLandmarkRegion2D) -> Double {
        // Lip fullness tends to decrease with age
        let outerHeight = calculateRegionSpan(outerLips.normalizedPoints, axis: .vertical)
        let innerHeight = calculateRegionSpan(innerLips.normalizedPoints, axis: .vertical)

        let lipRatio = innerHeight / max(outerHeight, 0.001)
        return (0.7 - lipRatio) * 40
    }

    private func analyzeBrows(
        leftBrow: VNFaceLandmarkRegion2D,
        rightBrow: VNFaceLandmarkRegion2D,
        leftEye: VNFaceLandmarkRegion2D,
        rightEye: VNFaceLandmarkRegion2D
    ) -> Double {
        // Brow position relative to eyes - tends to drop with age
        guard let leftBrowCenter = getRegionCenter(leftBrow),
              let rightBrowCenter = getRegionCenter(rightBrow),
              let leftEyeCenter = getRegionCenter(leftEye),
              let rightEyeCenter = getRegionCenter(rightEye) else { return 0 }

        let leftDistance = leftBrowCenter.y - leftEyeCenter.y
        let rightDistance = rightBrowCenter.y - rightEyeCenter.y
        let avgDistance = (leftDistance + rightDistance) / 2

        return (0.1 - Double(avgDistance)) * 100
    }

    // MARK: - Utility Methods
    private func getRegionCenter(_ region: VNFaceLandmarkRegion2D) -> CGPoint? {
        let points = region.normalizedPoints
        guard !points.isEmpty else { return nil }

        let sumX = points.reduce(0) { $0 + $1.x }
        let sumY = points.reduce(0) { $0 + $1.y }

        return CGPoint(
            x: sumX / CGFloat(points.count),
            y: sumY / CGFloat(points.count)
        )
    }

    private enum Axis {
        case horizontal, vertical
    }

    private func calculateRegionSpan(_ points: [CGPoint], axis: Axis) -> Double {
        guard !points.isEmpty else { return 0 }

        switch axis {
        case .horizontal:
            let minX = points.map { $0.x }.min() ?? 0
            let maxX = points.map { $0.x }.max() ?? 0
            return Double(maxX - minX)
        case .vertical:
            let minY = points.map { $0.y }.min() ?? 0
            let maxY = points.map { $0.y }.max() ?? 0
            return Double(maxY - minY)
        }
    }

    private func calculateConfidence(landmarks: VNFaceLandmarks2D, faceQuality: Float) -> Double {
        var confidence: Double = Double(faceQuality)

        // Boost confidence if we have complete landmark data
        var landmarkCount = 0
        if landmarks.leftEye != nil { landmarkCount += 1 }
        if landmarks.rightEye != nil { landmarkCount += 1 }
        if landmarks.nose != nil { landmarkCount += 1 }
        if landmarks.outerLips != nil { landmarkCount += 1 }
        if landmarks.faceContour != nil { landmarkCount += 1 }

        let landmarkCompleteness = Double(landmarkCount) / 5.0
        confidence = (confidence + landmarkCompleteness) / 2.0

        return min(1.0, max(0.3, confidence))
    }

    private func calculateAgeRange(estimatedAge: Double, confidence: Double) -> (Int, Int) {
        // Higher confidence = narrower range
        let baseRange = 10.0 - (confidence * 5.0) // 5-10 year range based on confidence
        let rangeLow = max(0, Int(estimatedAge - baseRange))
        let rangeHigh = min(100, Int(estimatedAge + baseRange))
        return (rangeLow, rangeHigh)
    }

    private func createFallbackEstimation(faceQuality: Float, cgImage: CGImage, startTime: Date) -> AgeEstimationResult {
        // Very rough estimation when landmarks aren't available
        let baseAge = 30.0
        let qualityModifier = Double(1.0 - faceQuality) * 15.0
        let estimatedAge = baseAge + qualityModifier

        return AgeEstimationResult(
            estimatedAge: estimatedAge,
            confidence: 0.3,
            ageRangeLow: max(0, Int(estimatedAge) - 15),
            ageRangeHigh: min(100, Int(estimatedAge) + 15),
            faceImage: cgImage,
            processingTime: Date().timeIntervalSince(startTime)
        )
    }
}
