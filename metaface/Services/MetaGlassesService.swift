//
//  MetaGlassesService.swift
//  metaface
//
//  Service for managing Meta glasses connection, streaming, and SDK interactions.
//  Uses the Meta Wearables Device Access Toolkit (MWDATCore & MWDATCamera).
//

import Foundation
import Combine
import AVFoundation
import CoreMedia
import CoreImage
import UIKit
import MWDATCore
import MWDATCamera

// MARK: - Stream Configuration
struct StreamConfiguration: Sendable {
    var resolution: StreamResolution = .medium
    var maxDuration: TimeInterval = 300
    var frameRate: UInt = 30

    static let `default` = StreamConfiguration()
}

// MARK: - Video Frame Data
struct VideoFrameData: @unchecked Sendable {
    let sampleBuffer: CMSampleBuffer
    let timestamp: CMTime
    let presentationTime: Date
    let uiImage: UIImage?

    var cgImage: CGImage? {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return nil
        }
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        let context = CIContext()
        return context.createCGImage(ciImage, from: ciImage.extent)
    }

    init(sampleBuffer: CMSampleBuffer, timestamp: CMTime, presentationTime: Date, uiImage: UIImage? = nil) {
        self.sampleBuffer = sampleBuffer
        self.timestamp = timestamp
        self.presentationTime = presentationTime
        self.uiImage = uiImage
    }
}

// MARK: - Meta Glasses Service
@MainActor
final class MetaGlassesService: ObservableObject {

    // MARK: - Published Properties
    @Published var connectionState: GlassesConnectionState = .disconnected
    @Published var connectedDevice: GlassesDevice?
    @Published var discoveredDevices: [GlassesDevice] = []
    @Published var permissionStatus: GlassesPermissionStatus = .unknown
    @Published var isStreaming: Bool = false
    @Published var currentFrame: VideoFrameData?
    @Published var streamError: Error?
    @Published var lastFrameImage: CGImage?
    @Published var registrationState: RegistrationState = .unavailable

    // Stream metrics
    @Published var streamDuration: TimeInterval = 0
    @Published var framesReceived: Int = 0
    @Published var currentFPS: Double = 0

    // MARK: - Private Properties
    private var streamConfiguration: StreamConfiguration = .default
    private var cancellables = Set<AnyCancellable>()
    private var streamTimer: Timer?
    private var fpsTimer: Timer?
    private var frameCount: Int = 0

    private let wearables: any WearablesInterface
    private var streamSession: StreamSession?
    private var devicesListenerToken: (any AnyListenerToken)?
    private var deviceLinkStateTokens: [DeviceIdentifier: any AnyListenerToken] = [:]
    private var videoFrameListenerToken: (any AnyListenerToken)?
    private var stateListenerToken: (any AnyListenerToken)?
    private var errorListenerToken: (any AnyListenerToken)?
    private var photoDataListenerToken: (any AnyListenerToken)?
    private var registrationListenerToken: (any AnyListenerToken)?

    // Frame callback
    var onFrameReceived: ((VideoFrameData) -> Void)?

    // MARK: - Initialization
    init() {
        do {
            try Wearables.configure()
        } catch {
            print("Failed to configure Wearables SDK: \(error)")
        }
        self.wearables = Wearables.shared

        Task {
            await setupDeviceListener()
            await setupRegistrationListener()
            await checkPermissions()
            await refreshDevices()
        }
    }

    // MARK: - Registration Management
    private func setupRegistrationListener() async {
        registrationListenerToken = wearables.addRegistrationStateListener { [weak self] state in
            Task { @MainActor in
                self?.registrationState = state
                if state == .registered {
                    await self?.refreshDevices()
                }
            }
        }
        registrationState = wearables.registrationState
    }

    func startRegistration() {
        do {
            try wearables.startRegistration()
        } catch {
            streamError = error
        }
    }

    func handleURL(_ url: URL) async -> Bool {
        do {
            return try await wearables.handleUrl(url)
        } catch {
            streamError = error
            return false
        }
    }

    // MARK: - Device Listener Setup
    private func setupDeviceListener() async {
        devicesListenerToken = wearables.addDevicesListener { [weak self] deviceIds in
            Task { @MainActor in
                guard let self = self else { return }
                await self.handleDevicesChanged(deviceIds)
            }
        }
    }

    private func handleDevicesChanged(_ deviceIds: [DeviceIdentifier]) async {
        var newDevices: [GlassesDevice] = []

        for deviceId in deviceIds {
            guard let device = wearables.deviceForIdentifier(deviceId) else { continue }
            let glassesDevice = mapToGlassesDevice(device)
            newDevices.append(glassesDevice)

            // Set up link state listener for each device
            if deviceLinkStateTokens[deviceId] == nil {
                let token = device.addLinkStateListener { [weak self] linkState in
                    Task { @MainActor in
                        self?.handleDeviceLinkStateChanged(deviceId: deviceId, linkState: linkState)
                    }
                }
                deviceLinkStateTokens[deviceId] = token
            }

            // Check if this device is connected
            if device.linkState == .connected {
                connectedDevice = glassesDevice
                connectionState = .connected
            }
        }

        discoveredDevices = newDevices

        // Check if previously connected device is gone
        if let currentDevice = connectedDevice,
           !deviceIds.contains(currentDevice.id) {
            connectedDevice = nil
            connectionState = .disconnected
            stopStreaming()
        }
    }

    private func handleDeviceLinkStateChanged(deviceId: DeviceIdentifier, linkState: LinkState) {
        // Update the device in discovered devices
        if let index = discoveredDevices.firstIndex(where: { $0.id == deviceId }) {
            var device = discoveredDevices[index]
            device.connectionState = mapLinkState(linkState)
            discoveredDevices[index] = device
        }

        // Update connected device state
        if connectedDevice?.id == deviceId {
            switch linkState {
            case .connected:
                connectedDevice?.connectionState = .connected
                connectionState = .connected
            case .connecting:
                connectedDevice?.connectionState = .connecting
                connectionState = .connecting
            case .disconnected:
                connectedDevice = nil
                connectionState = .disconnected
                stopStreaming()
            }
        } else if linkState == .connected {
            // A new device connected
            if let device = wearables.deviceForIdentifier(deviceId) {
                connectedDevice = mapToGlassesDevice(device)
                connectionState = .connected
            }
        }
    }

    // MARK: - Permission Management
    func checkPermissions() async {
        do {
            let status = try await wearables.checkPermissionStatus(.camera)
            switch status {
            case .granted:
                self.permissionStatus = .granted
            case .denied:
                self.permissionStatus = .denied
            @unknown default:
                self.permissionStatus = .unknown
            }
        } catch {
            handlePermissionCheckError(error)
        }
    }

    func requestPermission() async -> Bool {
        do {
            let status = try await wearables.requestPermission(.camera)
            self.permissionStatus = status == .granted ? .granted : .denied
            return status == .granted
        } catch {
            handlePermissionRequestError(error)
            return false
        }
    }

    private func handlePermissionCheckError(_ error: Error) {
        if let permError = error as? PermissionError {
            handlePermissionError(permError)
        } else {
            self.permissionStatus = .unknown
            self.streamError = error
        }
    }

    private func handlePermissionRequestError(_ error: Error) {
        if let permError = error as? PermissionError {
            handlePermissionError(permError)
        } else {
            self.permissionStatus = .denied
            self.streamError = error
        }
    }

    private func handlePermissionError(_ error: PermissionError) {
        switch error {
        case .noDevice, .noDeviceWithConnection:
            self.permissionStatus = .notDetermined
        case .metaAINotInstalled:
            self.streamError = NSError(
                domain: "MetaGlassesService",
                code: -10,
                userInfo: [NSLocalizedDescriptionKey: "Meta AI app is not installed. Please install it from the App Store."]
            )
            self.permissionStatus = .denied
        default:
            self.permissionStatus = .unknown
            self.streamError = error
        }
    }

    // MARK: - Device Discovery
    func startScanning() {
        connectionState = .scanning
        Task {
            await refreshDevices()
        }
    }

    func refreshDevices() async {
        let deviceIds = wearables.devices
        await handleDevicesChanged(deviceIds)

        if discoveredDevices.isEmpty {
            connectionState = .disconnected
        }
    }

    func stopScanning() {
        if connectionState == .scanning {
            connectionState = discoveredDevices.isEmpty ? .disconnected : .disconnected
        }
    }

    // MARK: - Connection Management
    func connect(to device: GlassesDevice) async -> Bool {
        connectionState = .connecting

        // The SDK manages connections through the Meta AI app
        // We just need to verify the device is available and connected
        guard let sdkDevice = wearables.deviceForIdentifier(device.id) else {
            connectionState = .error
            streamError = NSError(
                domain: "MetaGlassesService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Device not found. Make sure it's connected via Meta AI app."]
            )
            return false
        }

        // Check if device is connected
        if sdkDevice.linkState == .connected {
            var connectedDevice = device
            connectedDevice.connectionState = .connected
            connectedDevice.permissionStatus = permissionStatus
            self.connectedDevice = connectedDevice
            connectionState = .connected
            return true
        } else {
            connectionState = .error
            streamError = NSError(
                domain: "MetaGlassesService",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Device is not connected. Please connect it via Meta AI app first."]
            )
            return false
        }
    }

    func disconnect() {
        stopStreaming()
        connectedDevice?.connectionState = .disconnected
        connectedDevice = nil
        connectionState = .disconnected
    }

    // MARK: - Stream Management
    func startStreaming(configuration: StreamConfiguration? = nil) async -> Bool {
        let config = configuration ?? .default

        NSLog("[MetaFace] startStreaming called - connectionState: \(connectionState), registrationState: \(registrationState)")
        NSLog("[MetaFace] connectedDevice: \(String(describing: connectedDevice?.name))")

        guard connectionState == .connected, let device = connectedDevice else {
            NSLog("[MetaFace] ERROR: No device connected")
            streamError = NSError(
                domain: "MetaGlassesService",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "No device connected"]
            )
            return false
        }

        guard device.isCompatible else {
            NSLog("[MetaFace] ERROR: Device not compatible for streaming")
            streamError = NSError(
                domain: "MetaGlassesService",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "Device does not support camera streaming"]
            )
            return false
        }

        // Check registration state
        guard registrationState == .registered else {
            NSLog("[MetaFace] ERROR: Not registered with Meta. State: \(registrationState)")
            streamError = NSError(
                domain: "MetaGlassesService",
                code: -10,
                userInfo: [NSLocalizedDescriptionKey: "Not registered with Meta. Please authorize the app first."]
            )
            return false
        }

        // Check camera permission
        NSLog("[MetaFace] Checking camera permission...")
        let hasPermission = await requestPermission()
        guard hasPermission else {
            NSLog("[MetaFace] ERROR: Camera permission denied")
            return false
        }
        NSLog("[MetaFace] Camera permission granted")

        streamConfiguration = config

        // Create stream session configuration
        let sessionConfig = StreamSessionConfig(
            videoCodec: .raw,
            resolution: mapResolution(config.resolution),
            frameRate: config.frameRate
        )
        NSLog("[MetaFace] Created StreamSessionConfig - resolution: \(config.resolution), frameRate: \(config.frameRate)")

        // Create device selector for specific device
        let deviceSelector = SpecificDeviceSelector(device: device.id)
        NSLog("[MetaFace] Created SpecificDeviceSelector for device: \(device.id)")

        // Create and configure stream session
        streamSession = StreamSession(streamSessionConfig: sessionConfig, deviceSelector: deviceSelector)
        NSLog("[MetaFace] Created StreamSession")

        guard let session = streamSession else {
            streamError = NSError(
                domain: "MetaGlassesService",
                code: -4,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create stream session"]
            )
            return false
        }

        // Set up video frame listener
        videoFrameListenerToken = session.videoFramePublisher.listen { [weak self] frame in
            Task { @MainActor in
                self?.handleVideoFrame(frame)
            }
        }

        // Set up state listener
        stateListenerToken = session.statePublisher.listen { [weak self] state in
            Task { @MainActor in
                self?.handleStreamStateChange(state)
            }
        }

        // Set up error listener
        errorListenerToken = session.errorPublisher.listen { [weak self] error in
            Task { @MainActor in
                self?.handleStreamError(error)
            }
        }

        // Set up photo data listener
        photoDataListenerToken = session.photoDataPublisher.listen { [weak self] photoData in
            Task { @MainActor in
                self?.handlePhotoData(photoData)
            }
        }

        // Start the session
        NSLog("[MetaFace] Starting stream session...")
        await session.start()
        NSLog("[MetaFace] Stream session started - current state: \(session.state)")

        isStreaming = true
        connectionState = .streaming
        startStreamTimers()

        NSLog("[MetaFace] Streaming started successfully")
        return true
    }

    func stopStreaming() {
        Task {
            await streamSession?.stop()
        }

        // Cancel listeners
        Task {
            await videoFrameListenerToken?.cancel()
            await stateListenerToken?.cancel()
            await errorListenerToken?.cancel()
            await photoDataListenerToken?.cancel()
        }

        videoFrameListenerToken = nil
        stateListenerToken = nil
        errorListenerToken = nil
        photoDataListenerToken = nil
        streamSession = nil

        stopStreamTimers()
        isStreaming = false
        framesReceived = 0
        currentFPS = 0
        streamDuration = 0

        if connectionState == .streaming {
            connectionState = .connected
        }
    }

    // MARK: - Photo Capture
    private var pendingPhotoContinuation: CheckedContinuation<CGImage?, Never>?

    func capturePhoto() async -> CGImage? {
        guard isStreaming, let session = streamSession else { return nil }

        return await withCheckedContinuation { continuation in
            pendingPhotoContinuation = continuation
            let success = session.capturePhoto(format: .jpeg)
            if !success {
                pendingPhotoContinuation = nil
                continuation.resume(returning: nil)
            }
        }
    }

    private func handlePhotoData(_ photoData: PhotoData) {
        guard let image = UIImage(data: photoData.data)?.cgImage else {
            pendingPhotoContinuation?.resume(returning: nil)
            pendingPhotoContinuation = nil
            return
        }
        pendingPhotoContinuation?.resume(returning: image)
        pendingPhotoContinuation = nil
    }

    // MARK: - Frame Handling
    private func handleVideoFrame(_ frame: VideoFrame) {
        // Log every 30th frame to avoid spam
        if framesReceived % 30 == 0 {
            NSLog("[MetaFace] Received frame #\(framesReceived)")
        }

        let sampleBuffer = frame.sampleBuffer
        let uiImage = frame.makeUIImage()

        let frameData = VideoFrameData(
            sampleBuffer: sampleBuffer,
            timestamp: CMSampleBufferGetPresentationTimeStamp(sampleBuffer),
            presentationTime: Date(),
            uiImage: uiImage
        )

        currentFrame = frameData
        lastFrameImage = frameData.cgImage
        framesReceived += 1
        frameCount += 1

        onFrameReceived?(frameData)
    }

    private func handleStreamStateChange(_ state: StreamSessionState) {
        NSLog("[MetaFace] Stream state changed: \(state)")
        switch state {
        case .streaming:
            NSLog("[MetaFace] Stream is now STREAMING")
            isStreaming = true
            connectionState = .streaming
        case .stopped, .stopping:
            NSLog("[MetaFace] Stream STOPPED/STOPPING")
            if isStreaming {
                isStreaming = false
                connectionState = .connected
            }
        case .waitingForDevice:
            NSLog("[MetaFace] Stream WAITING FOR DEVICE")
            connectionState = .connecting
        case .starting:
            NSLog("[MetaFace] Stream STARTING")
            connectionState = .connecting
        case .paused:
            NSLog("[MetaFace] Stream PAUSED")
            isStreaming = false
        @unknown default:
            NSLog("[MetaFace] Stream unknown state")
            break
        }
    }

    private func handleStreamError(_ error: StreamSessionError) {
        NSLog("[MetaFace] STREAM ERROR: \(error)")
        switch error {
        case .deviceNotFound(let deviceId):
            streamError = NSError(
                domain: "MetaGlassesService",
                code: -5,
                userInfo: [NSLocalizedDescriptionKey: "Device not found: \(deviceId)"]
            )
        case .deviceNotConnected(let deviceId):
            streamError = NSError(
                domain: "MetaGlassesService",
                code: -6,
                userInfo: [NSLocalizedDescriptionKey: "Device not connected: \(deviceId)"]
            )
        case .permissionDenied:
            streamError = NSError(
                domain: "MetaGlassesService",
                code: -7,
                userInfo: [NSLocalizedDescriptionKey: "Camera permission denied"]
            )
            permissionStatus = .denied
        case .timeout:
            streamError = NSError(
                domain: "MetaGlassesService",
                code: -8,
                userInfo: [NSLocalizedDescriptionKey: "Stream connection timeout"]
            )
        case .videoStreamingError, .audioStreamingError, .internalError:
            streamError = NSError(
                domain: "MetaGlassesService",
                code: -9,
                userInfo: [NSLocalizedDescriptionKey: "Streaming error occurred"]
            )
        @unknown default:
            streamError = NSError(
                domain: "MetaGlassesService",
                code: -99,
                userInfo: [NSLocalizedDescriptionKey: "Unknown streaming error"]
            )
        }
        connectionState = .error
    }

    // MARK: - Resolution Mapping
    private func mapResolution(_ resolution: StreamResolution) -> StreamingResolution {
        switch resolution {
        case .low:
            return .low
        case .medium:
            return .medium
        case .high:
            return .high
        }
    }

    // MARK: - Device Mapping
    private func mapToGlassesDevice(_ device: Device) -> GlassesDevice {
        let deviceType = mapDeviceType(device.deviceType())
        let compatibility = device.compatibility()

        return GlassesDevice(
            id: device.identifier,
            name: device.name,
            type: deviceType,
            connectionState: mapLinkState(device.linkState),
            permissionStatus: permissionStatus,
            batteryLevel: nil,
            signalStrength: nil,
            firmwareVersion: nil,
            lastConnected: Date(),
            isCompatible: compatibility == .compatible
        )
    }

    private func mapDeviceType(_ deviceType: DeviceType) -> GlassesDeviceType {
        switch deviceType {
        case .rayBanMeta:
            return .rayBanMeta
        case .oakleyMetaHSTN:
            return .oakleyMetaHSTN
        case .oakleyMetaVanguard:
            return .oakleyMetaVanguard
        case .metaRayBanDisplay:
            return .rayBanDisplay
        case .unknown:
            return .unknown
        @unknown default:
            return .unknown
        }
    }

    private func mapLinkState(_ linkState: LinkState) -> GlassesConnectionState {
        switch linkState {
        case .connected:
            return .connected
        case .connecting:
            return .connecting
        case .disconnected:
            return .disconnected
        }
    }

    // MARK: - Timer Management
    private func startStreamTimers() {
        streamDuration = 0
        frameCount = 0

        streamTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.streamDuration += 1
            }
        }

        fpsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.currentFPS = Double(self.frameCount)
                self.frameCount = 0
            }
        }
    }

    private func stopStreamTimers() {
        streamTimer?.invalidate()
        streamTimer = nil
        fpsTimer?.invalidate()
        fpsTimer = nil
    }

    // MARK: - Cleanup
    deinit {
        streamTimer?.invalidate()
        fpsTimer?.invalidate()

        Task { [devicesListenerToken, deviceLinkStateTokens, registrationListenerToken,
                videoFrameListenerToken, stateListenerToken, errorListenerToken, photoDataListenerToken] in
            await devicesListenerToken?.cancel()
            await registrationListenerToken?.cancel()
            await videoFrameListenerToken?.cancel()
            await stateListenerToken?.cancel()
            await errorListenerToken?.cancel()
            await photoDataListenerToken?.cancel()
            for token in deviceLinkStateTokens.values {
                await token.cancel()
            }
        }
    }
}
