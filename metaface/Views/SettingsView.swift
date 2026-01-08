//
//  SettingsView.swift
//  metaface
//
//  App settings and configuration view.
//

import SwiftUI
import SwiftData

struct SettingsView: View {
    @EnvironmentObject var glassesService: MetaGlassesService
    @AppStorage("streamResolution") private var streamResolution: String = StreamResolution.medium.rawValue
    @AppStorage("autoStartStream") private var autoStartStream = false
    @AppStorage("enableHaptics") private var enableHaptics = true
    @AppStorage("saveScansAutomatically") private var saveScansAutomatically = true
    @AppStorage("faceDetectionSensitivity") private var faceDetectionSensitivity: Double = 0.5
    @AppStorage("maxFacesPerFrame") private var maxFacesPerFrame: Double = 5

    @State private var showAbout = false
    @State private var showPrivacy = false

    var body: some View {
        NavigationStack {
            List {
                // Device Settings
                deviceSection

                // Scanning Settings
                scanningSection

                // Privacy & Data
                privacySection

                // About
                aboutSection
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showAbout) {
                AboutView()
            }
            .sheet(isPresented: $showPrivacy) {
                PrivacyView()
            }
        }
    }

    // MARK: - Device Section
    private var deviceSection: some View {
        Section {
            // Stream Resolution
            Picker("Stream Resolution", selection: $streamResolution) {
                ForEach(StreamResolution.allCases, id: \.rawValue) { resolution in
                    Text(resolution.rawValue).tag(resolution.rawValue)
                }
            }

            // Auto Start Stream
            Toggle("Auto-Start Stream", isOn: $autoStartStream)

            // Connected Device Info
            if let device = glassesService.connectedDevice {
                HStack {
                    Text("Connected Device")
                    Spacer()
                    Text(device.displayName)
                        .foregroundStyle(.secondary)
                }

                if let firmware = device.firmwareVersion {
                    HStack {
                        Text("Firmware")
                        Spacer()
                        Text(firmware)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Device")
        } footer: {
            Text("Higher resolution requires more bandwidth and may reduce frame rate.")
        }
    }

    // MARK: - Scanning Section
    private var scanningSection: some View {
        Section {
            // Face Detection Sensitivity
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Detection Sensitivity")
                    Spacer()
                    Text(sensitivityLabel)
                        .foregroundStyle(.secondary)
                }

                Slider(value: $faceDetectionSensitivity, in: 0.1...1.0, step: 0.1)
            }

            // Max Faces Per Frame
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Max Faces Per Frame")
                    Spacer()
                    Text("\(Int(maxFacesPerFrame))")
                        .foregroundStyle(.secondary)
                }

                Slider(value: $maxFacesPerFrame, in: 1...10, step: 1)
            }

            // Auto Save
            Toggle("Save Scans Automatically", isOn: $saveScansAutomatically)

            // Haptics
            Toggle("Enable Haptic Feedback", isOn: $enableHaptics)

        } header: {
            Text("Scanning")
        } footer: {
            Text("Higher sensitivity detects more faces but may increase false positives.")
        }
    }

    private var sensitivityLabel: String {
        switch faceDetectionSensitivity {
        case 0.1..<0.3: return "Low"
        case 0.3..<0.6: return "Medium"
        case 0.6..<0.8: return "High"
        default: return "Very High"
        }
    }

    // MARK: - Privacy Section
    private var privacySection: some View {
        Section {
            Button {
                showPrivacy = true
            } label: {
                HStack {
                    Label("Privacy Policy", systemImage: "hand.raised")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            NavigationLink {
                DataManagementView()
            } label: {
                Label("Data Management", systemImage: "externaldrive")
            }

        } header: {
            Text("Privacy & Data")
        }
    }

    // MARK: - About Section
    private var aboutSection: some View {
        Section {
            Button {
                showAbout = true
            } label: {
                HStack {
                    Label("About MetaFace", systemImage: "info.circle")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            HStack {
                Text("Version")
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Build")
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                    .foregroundStyle(.secondary)
            }

            Link(destination: URL(string: "https://developers.meta.com/wearables")!) {
                HStack {
                    Label("Meta Wearables SDK", systemImage: "link")
                    Spacer()
                    Image(systemName: "arrow.up.forward")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

        } header: {
            Text("About")
        }
    }
}

// MARK: - About View
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // App Icon
                    ZStack {
                        RoundedRectangle(cornerRadius: 24)
                            .fill(
                                LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 100, height: 100)

                        Image(systemName: "person.viewfinder")
                            .font(.system(size: 50))
                            .foregroundStyle(.white)
                    }
                    .padding(.top, 20)

                    VStack(spacing: 8) {
                        Text("MetaFace")
                            .font(.title)
                            .fontWeight(.bold)

                        Text("Age Estimation Companion")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Text("MetaFace is a companion app for Meta Ray-Ban glasses that uses advanced computer vision and machine learning to detect faces and estimate age in real-time.")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Divider()
                        .padding(.horizontal)

                    VStack(alignment: .leading, spacing: 16) {
                        FeatureRow(icon: "eyeglasses", title: "Meta Glasses Integration", description: "Connects to Ray-Ban Meta and Oakley Meta glasses via the official SDK")

                        FeatureRow(icon: "person.viewfinder", title: "Face Detection", description: "Uses Apple Vision framework for accurate face detection")

                        FeatureRow(icon: "chart.bar", title: "Age Estimation", description: "ML-powered age estimation with confidence scoring")

                        FeatureRow(icon: "clock.arrow.circlepath", title: "Scan History", description: "Keep track of all your scans and sessions")
                    }
                    .padding(.horizontal)

                    Spacer()
                }
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Privacy View
struct PrivacyView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Privacy Policy")
                        .font(.title)
                        .fontWeight(.bold)

                    Group {
                        Section("Data Collection") {
                            Text("MetaFace processes video frames locally on your device. No facial data or images are transmitted to external servers.")
                        }

                        Section("Storage") {
                            Text("Scan results and thumbnails are stored locally on your device using SwiftData. You can delete this data at any time through the Data Management settings.")
                        }

                        Section("Meta SDK") {
                            Text("This app uses the Meta Wearables Device Access Toolkit to communicate with your glasses. Please refer to Meta's privacy policy for information about how Meta handles device data.")
                        }

                        Section("Analytics") {
                            Text("We do not collect any personal analytics or usage data. All processing happens on-device.")
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Privacy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func Section(_ title: String, content: () -> Text) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            content()
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Data Management View
struct DataManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @Query var allScans: [FaceScan]
    @Query var allSessions: [ScanSession]

    @State private var showDeleteAllAlert = false

    var body: some View {
        List {
            Section {
                HStack {
                    Text("Total Scans")
                    Spacer()
                    Text("\(allScans.count)")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Total Sessions")
                    Spacer()
                    Text("\(allSessions.count)")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Storage Used")
                    Spacer()
                    Text(storageUsed)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Statistics")
            }

            Section {
                Button(role: .destructive) {
                    showDeleteAllAlert = true
                } label: {
                    Label("Delete All Data", systemImage: "trash")
                }
            } header: {
                Text("Actions")
            } footer: {
                Text("This will permanently delete all scan history and cannot be undone.")
            }
        }
        .navigationTitle("Data Management")
        .alert("Delete All Data?", isPresented: $showDeleteAllAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteAllData()
            }
        } message: {
            Text("This will permanently delete \(allScans.count) scans and \(allSessions.count) sessions.")
        }
    }

    private var storageUsed: String {
        var totalBytes = 0
        for scan in allScans {
            totalBytes += scan.thumbnailData?.count ?? 0
        }

        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(totalBytes))
    }

    private func deleteAllData() {
        for scan in allScans {
            modelContext.delete(scan)
        }
        for session in allSessions {
            modelContext.delete(session)
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(MetaGlassesService())
}
