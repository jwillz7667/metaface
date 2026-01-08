//
//  GlassesDevice.swift
//  metaface
//
//  Model representing a connected Meta glasses device.
//

import Foundation

// MARK: - Device Types
enum GlassesDeviceType: String, CaseIterable, Codable {
    case rayBanMeta = "Ray-Ban Meta"
    case oakleyMetaHSTN = "Oakley Meta HSTN"
    case oakleyMetaVanguard = "Oakley Meta Vanguard"
    case rayBanDisplay = "Ray-Ban Display"
    case unknown = "Unknown Device"

    var supportsCamera: Bool {
        switch self {
        case .rayBanMeta, .oakleyMetaHSTN, .oakleyMetaVanguard:
            return true
        case .rayBanDisplay, .unknown:
            return false
        }
    }

    var maxResolution: StreamResolution {
        switch self {
        case .rayBanMeta, .oakleyMetaVanguard:
            return .high
        default:
            return .medium
        }
    }

    var iconName: String {
        switch self {
        case .rayBanMeta, .rayBanDisplay:
            return "eyeglasses"
        case .oakleyMetaHSTN, .oakleyMetaVanguard:
            return "goggles"
        case .unknown:
            return "questionmark.circle"
        }
    }
}

// MARK: - Stream Resolution
enum StreamResolution: String, CaseIterable, Codable {
    case low = "Low (360p)"
    case medium = "Medium (504p)"
    case high = "High (720p)"

    var width: Int {
        switch self {
        case .low: return 360
        case .medium: return 504
        case .high: return 720
        }
    }

    var height: Int {
        switch self {
        case .low: return 640
        case .medium: return 896
        case .high: return 1280
        }
    }

    var maxFrameRate: Int {
        switch self {
        case .low: return 30
        case .medium: return 30
        case .high: return 30
        }
    }
}

// MARK: - Connection State
enum GlassesConnectionState: String, Codable {
    case disconnected
    case scanning
    case connecting
    case connected
    case streaming
    case error

    var displayName: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .scanning: return "Scanning..."
        case .connecting: return "Connecting..."
        case .connected: return "Connected"
        case .streaming: return "Streaming"
        case .error: return "Error"
        }
    }

    var color: String {
        switch self {
        case .disconnected: return "gray"
        case .scanning, .connecting: return "orange"
        case .connected: return "blue"
        case .streaming: return "green"
        case .error: return "red"
        }
    }

    var isConnected: Bool {
        self == .connected || self == .streaming
    }
}

// MARK: - Permission Status
enum GlassesPermissionStatus: String, Codable {
    case unknown
    case notDetermined
    case granted
    case denied
    case restricted

    var canRequest: Bool {
        self == .notDetermined || self == .unknown
    }

    var isGranted: Bool {
        self == .granted
    }
}

// MARK: - Glasses Device
struct GlassesDevice: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let type: GlassesDeviceType
    var connectionState: GlassesConnectionState
    var permissionStatus: GlassesPermissionStatus
    var batteryLevel: Int?
    var signalStrength: Int?
    var firmwareVersion: String?
    var lastConnected: Date?
    private var _isCompatible: Bool?

    // MARK: - Computed Properties
    var displayName: String {
        name.isEmpty ? type.rawValue : name
    }

    var batteryIcon: String {
        guard let level = batteryLevel else { return "battery.0" }
        switch level {
        case 75...100: return "battery.100"
        case 50..<75: return "battery.75"
        case 25..<50: return "battery.50"
        case 1..<25: return "battery.25"
        default: return "battery.0"
        }
    }

    var signalIcon: String {
        guard let strength = signalStrength else { return "wifi.slash" }
        switch strength {
        case 75...100: return "wifi"
        case 50..<75: return "wifi"
        case 25..<50: return "wifi"
        default: return "wifi.exclamationmark"
        }
    }

    var isCompatible: Bool {
        _isCompatible ?? type.supportsCamera
    }

    // MARK: - Initialization
    init(
        id: String,
        name: String = "",
        type: GlassesDeviceType = .unknown,
        connectionState: GlassesConnectionState = .disconnected,
        permissionStatus: GlassesPermissionStatus = .unknown,
        batteryLevel: Int? = nil,
        signalStrength: Int? = nil,
        firmwareVersion: String? = nil,
        lastConnected: Date? = nil,
        isCompatible: Bool? = nil
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.connectionState = connectionState
        self.permissionStatus = permissionStatus
        self.batteryLevel = batteryLevel
        self.signalStrength = signalStrength
        self.firmwareVersion = firmwareVersion
        self.lastConnected = lastConnected
        self._isCompatible = isCompatible
    }

    // MARK: - Preview
    static var preview: GlassesDevice {
        GlassesDevice(
            id: "preview-001",
            name: "My Ray-Ban Meta",
            type: .rayBanMeta,
            connectionState: .connected,
            permissionStatus: .granted,
            batteryLevel: 78,
            signalStrength: 85,
            firmwareVersion: "2.1.0",
            lastConnected: Date()
        )
    }

    static var previewDisconnected: GlassesDevice {
        GlassesDevice(
            id: "preview-002",
            name: "Office Glasses",
            type: .rayBanMeta,
            connectionState: .disconnected,
            permissionStatus: .notDetermined,
            lastConnected: Date().addingTimeInterval(-86400)
        )
    }
}
