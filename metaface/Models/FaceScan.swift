//
//  FaceScan.swift
//  metaface
//
//  Data model for storing individual face scan results.
//

import Foundation
import SwiftData
import CoreGraphics

@Model
final class FaceScan {
    // MARK: - Properties
    var id: UUID
    var timestamp: Date
    var estimatedAge: Double
    var ageConfidence: Double
    var ageRangeLow: Int
    var ageRangeHigh: Int

    // Face detection metadata
    var faceConfidence: Double
    var faceBoundsX: Double
    var faceBoundsY: Double
    var faceBoundsWidth: Double
    var faceBoundsHeight: Double

    // Additional face attributes
    var hasSmile: Bool
    var smileConfidence: Double
    var eyesOpen: Bool
    var eyesOpenConfidence: Double
    var faceYaw: Double
    var facePitch: Double
    var faceRoll: Double
    var faceQuality: Double

    // Image data (thumbnail)
    @Attribute(.externalStorage) var thumbnailData: Data?

    // Relationship
    var session: ScanSession?

    // MARK: - Computed Properties
    var ageRangeString: String {
        "\(ageRangeLow)-\(ageRangeHigh)"
    }

    var estimatedAgeString: String {
        String(format: "%.0f", estimatedAge)
    }

    var confidencePercentage: String {
        String(format: "%.0f%%", ageConfidence * 100)
    }

    var faceQualityDescription: String {
        switch faceQuality {
        case 0.8...1.0: return "Excellent"
        case 0.6..<0.8: return "Good"
        case 0.4..<0.6: return "Fair"
        default: return "Poor"
        }
    }

    // MARK: - Initialization
    init(
        estimatedAge: Double,
        ageConfidence: Double,
        ageRangeLow: Int,
        ageRangeHigh: Int,
        faceConfidence: Double = 0.0,
        faceBoundsX: Double = 0.0,
        faceBoundsY: Double = 0.0,
        faceBoundsWidth: Double = 0.0,
        faceBoundsHeight: Double = 0.0,
        hasSmile: Bool = false,
        smileConfidence: Double = 0.0,
        eyesOpen: Bool = true,
        eyesOpenConfidence: Double = 0.0,
        faceYaw: Double = 0.0,
        facePitch: Double = 0.0,
        faceRoll: Double = 0.0,
        faceQuality: Double = 0.0,
        thumbnailData: Data? = nil,
        session: ScanSession? = nil
    ) {
        self.id = UUID()
        self.timestamp = Date()
        self.estimatedAge = estimatedAge
        self.ageConfidence = ageConfidence
        self.ageRangeLow = ageRangeLow
        self.ageRangeHigh = ageRangeHigh
        self.faceConfidence = faceConfidence
        self.faceBoundsX = faceBoundsX
        self.faceBoundsY = faceBoundsY
        self.faceBoundsWidth = faceBoundsWidth
        self.faceBoundsHeight = faceBoundsHeight
        self.hasSmile = hasSmile
        self.smileConfidence = smileConfidence
        self.eyesOpen = eyesOpen
        self.eyesOpenConfidence = eyesOpenConfidence
        self.faceYaw = faceYaw
        self.facePitch = facePitch
        self.faceRoll = faceRoll
        self.faceQuality = faceQuality
        self.thumbnailData = thumbnailData
        self.session = session
    }

    // Convenience initializer with CGRect
    convenience init(
        estimatedAge: Double,
        ageConfidence: Double,
        ageRangeLow: Int,
        ageRangeHigh: Int,
        faceConfidence: Double = 0.0,
        faceBounds: CGRect,
        hasSmile: Bool = false,
        smileConfidence: Double = 0.0,
        eyesOpen: Bool = true,
        eyesOpenConfidence: Double = 0.0,
        faceYaw: Double = 0.0,
        facePitch: Double = 0.0,
        faceRoll: Double = 0.0,
        faceQuality: Double = 0.0,
        thumbnailData: Data? = nil,
        session: ScanSession? = nil
    ) {
        self.init(
            estimatedAge: estimatedAge,
            ageConfidence: ageConfidence,
            ageRangeLow: ageRangeLow,
            ageRangeHigh: ageRangeHigh,
            faceConfidence: faceConfidence,
            faceBoundsX: faceBounds.origin.x,
            faceBoundsY: faceBounds.origin.y,
            faceBoundsWidth: faceBounds.width,
            faceBoundsHeight: faceBounds.height,
            hasSmile: hasSmile,
            smileConfidence: smileConfidence,
            eyesOpen: eyesOpen,
            eyesOpenConfidence: eyesOpenConfidence,
            faceYaw: faceYaw,
            facePitch: facePitch,
            faceRoll: faceRoll,
            faceQuality: faceQuality,
            thumbnailData: thumbnailData,
            session: session
        )
    }

    // MARK: - Convenience
    var faceBounds: CGRect {
        CGRect(x: faceBoundsX, y: faceBoundsY, width: faceBoundsWidth, height: faceBoundsHeight)
    }
}
