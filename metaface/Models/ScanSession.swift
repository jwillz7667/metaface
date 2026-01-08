//
//  ScanSession.swift
//  metaface
//
//  Data model for storing scanning sessions.
//

import Foundation
import SwiftData

@Model
final class ScanSession {
    // MARK: - Properties
    var id: UUID
    var startTime: Date
    var endTime: Date?
    var deviceName: String
    var deviceIdentifier: String
    var totalScans: Int
    var notes: String?

    // Session statistics
    var averageAge: Double
    var minAge: Double
    var maxAge: Double
    var averageConfidence: Double

    // Relationships
    @Relationship(deleteRule: .cascade, inverse: \FaceScan.session)
    var scans: [FaceScan]?

    // MARK: - Computed Properties
    var duration: TimeInterval {
        guard let endTime = endTime else {
            return Date().timeIntervalSince(startTime)
        }
        return endTime.timeIntervalSince(startTime)
    }

    var durationString: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: duration) ?? "0s"
    }

    var isActive: Bool {
        endTime == nil
    }

    var dateString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: startTime)
    }

    // MARK: - Initialization
    init(
        deviceName: String = "Unknown Device",
        deviceIdentifier: String = ""
    ) {
        self.id = UUID()
        self.startTime = Date()
        self.endTime = nil
        self.deviceName = deviceName
        self.deviceIdentifier = deviceIdentifier
        self.totalScans = 0
        self.notes = nil
        self.averageAge = 0.0
        self.minAge = 0.0
        self.maxAge = 0.0
        self.averageConfidence = 0.0
        self.scans = []
    }

    // MARK: - Methods
    func endSession() {
        endTime = Date()
        updateStatistics()
    }

    func addScan(_ scan: FaceScan) {
        if scans == nil {
            scans = []
        }
        scans?.append(scan)
        scan.session = self
        totalScans += 1
        updateStatistics()
    }

    private func updateStatistics() {
        guard let scans = scans, !scans.isEmpty else { return }

        let ages = scans.map { $0.estimatedAge }
        let confidences = scans.map { $0.ageConfidence }

        averageAge = ages.reduce(0, +) / Double(ages.count)
        minAge = ages.min() ?? 0
        maxAge = ages.max() ?? 0
        averageConfidence = confidences.reduce(0, +) / Double(confidences.count)
    }
}

// MARK: - Preview Data
extension ScanSession {
    static var preview: ScanSession {
        let session = ScanSession(deviceName: "Ray-Ban Meta", deviceIdentifier: "RB-META-001")
        session.endTime = Date().addingTimeInterval(-3600)
        session.totalScans = 15
        session.averageAge = 32.5
        session.minAge = 18.0
        session.maxAge = 55.0
        session.averageConfidence = 0.85
        return session
    }

    static var previewActive: ScanSession {
        let session = ScanSession(deviceName: "Ray-Ban Meta Gen 2", deviceIdentifier: "RB-META-002")
        session.totalScans = 5
        session.averageAge = 28.0
        session.minAge = 22.0
        session.maxAge = 35.0
        session.averageConfidence = 0.90
        return session
    }
}
