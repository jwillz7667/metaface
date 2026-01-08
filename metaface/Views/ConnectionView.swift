//
//  ConnectionView.swift
//  metaface
//
//  View for managing Meta glasses connection and pairing.
//

import SwiftUI
import MWDATCore

struct ConnectionView: View {
    @EnvironmentObject var glassesService: MetaGlassesService
    @Environment(\.dismiss) private var dismiss

    @State private var isScanning = false
    @State private var showPermissionAlert = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Registration status banner (if not registered)
                if glassesService.registrationState != .registered {
                    registrationBanner
                }

                // Header illustration
                headerSection

                // Content based on state
                Group {
                    if glassesService.registrationState != .registered {
                        registrationRequiredView
                    } else if glassesService.connectionState.isConnected {
                        connectedView
                    } else if isScanning {
                        scanningView
                    } else {
                        disconnectedView
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Connect Glasses")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Permission Required", isPresented: $showPermissionAlert) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Please enable access in the Meta AI app and ensure Developer Mode is enabled.")
            }
        }
    }

    // MARK: - Header Section
    private var headerSection: some View {
        VStack(spacing: 16) {
            ZStack {
                // Background glow
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [.blue.opacity(0.3), .clear]),
                            center: .center,
                            startRadius: 0,
                            endRadius: 100
                        )
                    )
                    .frame(width: 200, height: 200)

                // Glasses icon
                Image(systemName: "eyeglasses")
                    .font(.system(size: 80))
                    .foregroundStyle(.primary)
                    .symbolEffect(.pulse, options: .repeating, isActive: isScanning)
            }

            Text(headerTitle)
                .font(.title2)
                .fontWeight(.semibold)

            Text(headerSubtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding(.vertical, 30)
    }

    private var headerTitle: String {
        if glassesService.connectionState.isConnected {
            return "Connected"
        } else if isScanning {
            return "Scanning..."
        } else {
            return "Connect Your Glasses"
        }
    }

    private var headerSubtitle: String {
        if glassesService.connectionState.isConnected {
            return "Your glasses are ready to use"
        } else if isScanning {
            return "Looking for nearby Meta glasses"
        } else {
            return "Make sure your glasses are powered on and in pairing mode"
        }
    }

    // MARK: - Registration Banner
    private var registrationBanner: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

            Text("Registration required to access glasses")
                .font(.subheadline)

            Spacer()
        }
        .padding()
        .background(Color.orange.opacity(0.1))
    }

    // MARK: - Registration Required View
    private var registrationRequiredView: some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                Image(systemName: "person.badge.key.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(.blue)

                Text("Authorization Required")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("MetaFace needs to be authorized with your Meta account to access your glasses.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("This will:")
                    .font(.headline)

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Open the Meta authorization page")
                        .font(.subheadline)
                }

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Allow MetaFace to connect to your glasses")
                        .font(.subheadline)
                }

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Enable camera streaming access")
                        .font(.subheadline)
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)

            Spacer()

            Button {
                glassesService.startRegistration()
            } label: {
                Label("Authorize with Meta", systemImage: "arrow.right.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal)
            .padding(.bottom, 30)

            Text("Registration State: \(String(describing: glassesService.registrationState))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 10)
        }
    }

    // MARK: - Disconnected View
    private var disconnectedView: some View {
        VStack(spacing: 20) {
            // Instructions
            VStack(alignment: .leading, spacing: 12) {
                InstructionRow(number: 1, text: "Open the Meta AI app on your phone")
                InstructionRow(number: 2, text: "Enable Developer Mode in settings")
                InstructionRow(number: 3, text: "Make sure glasses are charged and powered on")
                InstructionRow(number: 4, text: "Tap 'Scan for Devices' below")
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal)

            Spacer()

            // Scan Button
            Button {
                startScanning()
            } label: {
                Label("Scan for Devices", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal)
            .padding(.bottom, 30)
        }
    }

    // MARK: - Scanning View
    private var scanningView: some View {
        VStack(spacing: 20) {
            if glassesService.discoveredDevices.isEmpty {
                // No devices found yet
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)

                    Text("Searching for devices...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxHeight: .infinity)
            } else {
                // Device list
                List {
                    Section {
                        ForEach(glassesService.discoveredDevices) { device in
                            DeviceRow(device: device) {
                                connectToDevice(device)
                            }
                        }
                    } header: {
                        Text("Available Devices")
                    }
                }
                .listStyle(.insetGrouped)
            }

            // Cancel Button
            Button {
                stopScanning()
            } label: {
                Text("Cancel")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color(.secondarySystemGroupedBackground))
                    .foregroundStyle(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal)
            .padding(.bottom, 30)
        }
    }

    // MARK: - Connected View
    private var connectedView: some View {
        VStack(spacing: 20) {
            if let device = glassesService.connectedDevice {
                // Device Info Card
                VStack(spacing: 16) {
                    // Device type icon
                    ZStack {
                        Circle()
                            .fill(Color.green.opacity(0.2))
                            .frame(width: 80, height: 80)

                        Image(systemName: device.type.iconName)
                            .font(.system(size: 36))
                            .foregroundStyle(.green)
                    }

                    VStack(spacing: 4) {
                        Text(device.displayName)
                            .font(.title3)
                            .fontWeight(.semibold)

                        Text(device.type.rawValue)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    // Device details
                    HStack(spacing: 30) {
                        if let battery = device.batteryLevel {
                            VStack(spacing: 4) {
                                Image(systemName: device.batteryIcon)
                                    .font(.title3)
                                    .foregroundStyle(battery > 20 ? .green : .red)
                                Text("\(battery)%")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if let signal = device.signalStrength {
                            VStack(spacing: 4) {
                                Image(systemName: device.signalIcon)
                                    .font(.title3)
                                    .foregroundStyle(.blue)
                                Text("\(signal)%")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if let firmware = device.firmwareVersion {
                            VStack(spacing: 4) {
                                Image(systemName: "cpu")
                                    .font(.title3)
                                    .foregroundStyle(.purple)
                                Text(firmware)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.top, 8)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal)

                // Stream status
                if glassesService.isStreaming {
                    HStack {
                        Circle()
                            .fill(.red)
                            .frame(width: 8, height: 8)

                        Text("Streaming Active")
                            .font(.subheadline)

                        Text("•")
                            .foregroundStyle(.secondary)

                        Text("\(Int(glassesService.currentFPS)) FPS")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.1))
                    .clipShape(Capsule())
                }
            }

            Spacer()

            // Disconnect Button
            Button {
                glassesService.disconnect()
            } label: {
                Text("Disconnect")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.red.opacity(0.1))
                    .foregroundStyle(.red)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal)
            .padding(.bottom, 30)
        }
    }

    // MARK: - Actions
    private func startScanning() {
        Task {
            // Check permissions first
            let hasPermission = await glassesService.requestPermission()
            if hasPermission {
                isScanning = true
                glassesService.startScanning()
            } else {
                showPermissionAlert = true
            }
        }
    }

    private func stopScanning() {
        isScanning = false
        glassesService.stopScanning()
    }

    private func connectToDevice(_ device: GlassesDevice) {
        Task {
            let success = await glassesService.connect(to: device)
            if success {
                isScanning = false
            }
        }
    }
}

// MARK: - Supporting Views
struct InstructionRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 24, height: 24)

                Text("\(number)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
            }

            Text(text)
                .font(.subheadline)
        }
    }
}

struct DeviceRow: View {
    let device: GlassesDevice
    let onConnect: () -> Void

    var body: some View {
        Button(action: onConnect) {
            HStack {
                Image(systemName: device.type.iconName)
                    .font(.title2)
                    .foregroundStyle(.blue)
                    .frame(width: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(device.displayName)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(device.type.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let battery = device.batteryLevel {
                    HStack(spacing: 4) {
                        Text("\(battery)%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Image(systemName: device.batteryIcon)
                            .foregroundStyle(battery > 20 ? .green : .red)
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

#Preview {
    ConnectionView()
        .environmentObject(MetaGlassesService())
}
