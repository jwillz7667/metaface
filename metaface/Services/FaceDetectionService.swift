//
//  FaceDetectionService.swift
//  metaface
//
//  Service for detecting faces in video frames using Apple Vision framework.
//

import Foundation
import Vision
import CoreImage
import CoreGraphics
import UIKit

// MARK: - Detected Face
struct DetectedFace: Identifiable {
    let id = UUID()
    let boundingBox: CGRect
    let confidence: Float
    let landmarks: VNFaceLandmarks2D?
    let yaw: Float?
    let pitch: Float?
    let roll: Float?
    let quality: Float?

    // Quality indicators
    var hasGoodQuality: Bool {
        guard let quality = quality else { return false }
        return quality >= 0.5
    }

    var isFacingCamera: Bool {
        guard let yaw = yaw else { return true }
        return abs(yaw) < 0.3
    }

    // Normalized face bounds for display
    func normalizedBounds(for imageSize: CGSize) -> CGRect {
        CGRect(
            x: boundingBox.origin.x * imageSize.width,
            y: (1 - boundingBox.origin.y - boundingBox.height) * imageSize.height,
            width: boundingBox.width * imageSize.width,
            height: boundingBox.height * imageSize.height
        )
    }
}

// MARK: - Face Detection Configuration
struct FaceDetectionConfiguration: Sendable {
    var detectLandmarks: Bool = true
    var detectQuality: Bool = true
    var minimumFaceSize: Float = 0.1
    var maximumFaces: Int = 10

    static let `default` = FaceDetectionConfiguration()

    static let performance = FaceDetectionConfiguration(
        detectLandmarks: false,
        detectQuality: false,
        minimumFaceSize: 0.15,
        maximumFaces: 5
    )
}

// MARK: - Face Detection Service
class FaceDetectionService {

    // MARK: - Properties
    private var configuration: FaceDetectionConfiguration
    private let sequenceHandler = VNSequenceRequestHandler()

    // Processing queue
    private let processingQueue = DispatchQueue(
        label: "com.metaface.facedetection",
        qos: .userInitiated
    )

    // MARK: - Initialization
    init(configuration: FaceDetectionConfiguration = .default) {
        self.configuration = configuration
    }

    // MARK: - Configuration
    func updateConfiguration(_ configuration: FaceDetectionConfiguration) {
        self.configuration = configuration
    }

    // MARK: - Face Detection
    func detectFaces(in cgImage: CGImage) async -> [DetectedFace] {
        await withCheckedContinuation { continuation in
            processingQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(returning: [])
                    return
                }

                let faces = self.performFaceDetection(in: cgImage)
                continuation.resume(returning: faces)
            }
        }
    }

    func detectFaces(in pixelBuffer: CVPixelBuffer) async -> [DetectedFace] {
        await withCheckedContinuation { continuation in
            processingQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(returning: [])
                    return
                }

                let faces = self.performFaceDetection(in: pixelBuffer)
                continuation.resume(returning: faces)
            }
        }
    }

    func detectFaces(in sampleBuffer: CMSampleBuffer) async -> [DetectedFace] {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return []
        }
        return await detectFaces(in: pixelBuffer)
    }

    // MARK: - Private Detection Methods
    private func performFaceDetection(in cgImage: CGImage) -> [DetectedFace] {
        var detectedFaces: [DetectedFace] = []

        // Create face detection request
        let faceDetectionRequest = VNDetectFaceRectanglesRequest { [weak self] request, error in
            if let error = error {
                #if DEBUG
                NSLog("[FaceDetection] Error: \(error)")
                #endif
                return
            }

            guard let results = request.results as? [VNFaceObservation] else { return }
            detectedFaces = results.prefix(self?.configuration.maximumFaces ?? 10).map { observation in
                DetectedFace(
                    boundingBox: observation.boundingBox,
                    confidence: observation.confidence,
                    landmarks: nil,
                    yaw: observation.yaw?.floatValue,
                    pitch: observation.pitch?.floatValue,
                    roll: observation.roll?.floatValue,
                    quality: nil
                )
            }
        }

        // Configure request
        faceDetectionRequest.revision = VNDetectFaceRectanglesRequestRevision3

        // Run requests
        var requests: [VNRequest] = [faceDetectionRequest]

        // Add landmarks request if enabled
        if configuration.detectLandmarks {
            let landmarksRequest = VNDetectFaceLandmarksRequest()
            landmarksRequest.revision = VNDetectFaceLandmarksRequestRevision3
            requests.append(landmarksRequest)
        }

        // Add quality request if enabled
        if configuration.detectQuality {
            let qualityRequest = VNDetectFaceCaptureQualityRequest()
            requests.append(qualityRequest)
        }

        // Create handler and perform detection
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try handler.perform(requests)

            // Merge landmarks and quality data
            if configuration.detectLandmarks || configuration.detectQuality {
                detectedFaces = mergeFaceData(
                    faces: detectedFaces,
                    landmarksResults: requests.compactMap { $0.results as? [VNFaceObservation] }.flatMap { $0 },
                    qualityResults: requests.compactMap { $0 as? VNDetectFaceCaptureQualityRequest }.first?.results as? [VNFaceObservation]
                )
            }
        } catch {
            #if DEBUG
            NSLog("[FaceDetection] Failed to perform detection: \(error)")
            #endif
        }

        return detectedFaces
    }

    private func performFaceDetection(in pixelBuffer: CVPixelBuffer) -> [DetectedFace] {
        var detectedFaces: [DetectedFace] = []

        // Face rectangles request
        let faceRequest = VNDetectFaceRectanglesRequest()
        faceRequest.revision = VNDetectFaceRectanglesRequestRevision3

        // Landmarks request
        var landmarksRequest: VNDetectFaceLandmarksRequest?
        if configuration.detectLandmarks {
            landmarksRequest = VNDetectFaceLandmarksRequest()
            landmarksRequest?.revision = VNDetectFaceLandmarksRequestRevision3
        }

        // Quality request
        var qualityRequest: VNDetectFaceCaptureQualityRequest?
        if configuration.detectQuality {
            qualityRequest = VNDetectFaceCaptureQualityRequest()
        }

        do {
            // Build request array
            var requests: [VNRequest] = [faceRequest]
            if let landmarksRequest = landmarksRequest {
                requests.append(landmarksRequest)
            }
            if let qualityRequest = qualityRequest {
                requests.append(qualityRequest)
            }

            // Perform requests using sequence handler for tracking
            try sequenceHandler.perform(requests, on: pixelBuffer)

            // Process face detection results
            guard let faceResults = faceRequest.results else { return [] }

            let landmarksResults = landmarksRequest?.results
            let qualityResults = qualityRequest?.results

            // Build detected faces
            for faceObservation in faceResults.prefix(configuration.maximumFaces) {
                var landmarks: VNFaceLandmarks2D?
                var quality: Float?

                // Match landmarks by bounding box proximity
                if let landmarksResults = landmarksResults {
                    landmarks = landmarksResults.first { result in
                        boundingBoxesMatch(faceObservation.boundingBox, result.boundingBox)
                    }?.landmarks
                }

                // Match quality by bounding box proximity
                if let qualityResults = qualityResults {
                    quality = qualityResults.first { result in
                        boundingBoxesMatch(faceObservation.boundingBox, result.boundingBox)
                    }?.faceCaptureQuality
                }

                let face = DetectedFace(
                    boundingBox: faceObservation.boundingBox,
                    confidence: faceObservation.confidence,
                    landmarks: landmarks,
                    yaw: faceObservation.yaw?.floatValue,
                    pitch: faceObservation.pitch?.floatValue,
                    roll: faceObservation.roll?.floatValue,
                    quality: quality
                )

                detectedFaces.append(face)
            }

        } catch {
            #if DEBUG
            NSLog("[FaceDetection] Sequence handler error: \(error)")
            #endif
        }

        return detectedFaces
    }

    // MARK: - Helper Methods
    private func mergeFaceData(
        faces: [DetectedFace],
        landmarksResults: [VNFaceObservation],
        qualityResults: [VNFaceObservation]?
    ) -> [DetectedFace] {
        return faces.map { face in
            var landmarks: VNFaceLandmarks2D?
            var quality: Float?

            // Find matching landmarks observation
            if let matchingLandmarks = landmarksResults.first(where: { result in
                boundingBoxesMatch(face.boundingBox, result.boundingBox)
            }) {
                landmarks = matchingLandmarks.landmarks
            }

            // Find matching quality observation
            if let qualityResults = qualityResults,
               let matchingQuality = qualityResults.first(where: { result in
                   boundingBoxesMatch(face.boundingBox, result.boundingBox)
               }) {
                quality = matchingQuality.faceCaptureQuality
            }

            return DetectedFace(
                boundingBox: face.boundingBox,
                confidence: face.confidence,
                landmarks: landmarks,
                yaw: face.yaw,
                pitch: face.pitch,
                roll: face.roll,
                quality: quality
            )
        }
    }

    private func boundingBoxesMatch(_ box1: CGRect, _ box2: CGRect) -> Bool {
        let threshold: CGFloat = 0.1
        return abs(box1.origin.x - box2.origin.x) < threshold &&
               abs(box1.origin.y - box2.origin.y) < threshold &&
               abs(box1.width - box2.width) < threshold &&
               abs(box1.height - box2.height) < threshold
    }

    // MARK: - Face Image Extraction
    func extractFaceImage(from cgImage: CGImage, face: DetectedFace, padding: CGFloat = 0.2) -> CGImage? {
        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)

        // Convert normalized bounds to image coordinates
        var faceRect = CGRect(
            x: face.boundingBox.origin.x * imageWidth,
            y: (1 - face.boundingBox.origin.y - face.boundingBox.height) * imageHeight,
            width: face.boundingBox.width * imageWidth,
            height: face.boundingBox.height * imageHeight
        )

        // Add padding
        let paddingX = faceRect.width * padding
        let paddingY = faceRect.height * padding
        faceRect = faceRect.insetBy(dx: -paddingX, dy: -paddingY)

        // Clamp to image bounds
        faceRect = faceRect.intersection(CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))

        // Crop image
        return cgImage.cropping(to: faceRect)
    }
}

// MARK: - CoreMedia Import
import CoreMedia
