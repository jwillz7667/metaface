//
//  DashboardView.swift
//  metaface
//
//  Main dashboard showing connection status and quick actions.
//

import SwiftUI
import SwiftData

struct DashboardView: View {
    @EnvironmentObject var glassesService: MetaGlassesService
    @EnvironmentObject var faceAnalysisService: FaceAnalysisService
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \FaceScan.timestamp, order: .reverse)
    private var recentScans: [FaceScan]

    @Query(sort: \ScanSession.startTime, order: .reverse)
    private var recentSessions: [ScanSession]

    @State private var showConnectionSheet = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Connection Status Card
                    connectionStatusCard

                    // Quick Stats
                    quickStatsSection

                    // Recent Activity
                    recentActivitySection

                    // Quick Actions
                    quickActionsSection
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("MetaFace")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showConnectionSheet = true
                    } label: {
                        Image(systemName: glassesService.connectionState.isConnected ? "link.circle.fill" : "link.circle")
                            .foregroundStyle(glassesService.connectionState.isConnected ? .green : .gray)
                    }
                }
            }
            .sheet(isPresented: $showConnectionSheet) {
                ConnectionView()
            }
        }
    }

    // MARK: - Connection Status Card
    private var connectionStatusCard: some View {
        GlassmorphicCard {
            VStack(spacing: 16) {
                HStack {
                    // Device Icon
                    ZStack {
                        Circle()
                            .fill(connectionStatusColor.opacity(0.2))
                            .frame(width: 60, height: 60)

                        Image(systemName: glassesService.connectedDevice?.type.iconName ?? "eyeglasses")
                            .font(.system(size: 28))
                            .foregroundStyle(connectionStatusColor)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(glassesService.connectedDevice?.displayName ?? "No Device")
                            .font(.headline)

                        HStack(spacing: 4) {
                            Circle()
                                .fill(connectionStatusColor)
                                .frame(width: 8, height: 8)

                            Text(glassesService.connectionState.displayName)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    // Battery & Signal
                    if let device = glassesService.connectedDevice {
                        VStack(alignment: .trailing, spacing: 4) {
                            if let battery = device.batteryLevel {
                                HStack(spacing: 4) {
                                    Text("\(battery)%")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Image(systemName: device.batteryIcon)
                                        .foregroundStyle(battery > 20 ? .green : .red)
                                }
                            }

                            if let signal = device.signalStrength {
                                HStack(spacing: 4) {
                                    Text("\(signal)%")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Image(systemName: device.signalIcon)
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                }

                // Connect/Disconnect Button
                Button {
                    if glassesService.connectionState.isConnected {
                        glassesService.disconnect()
                    } else {
                        showConnectionSheet = true
                    }
                } label: {
                    Text(glassesService.connectionState.isConnected ? "Disconnect" : "Connect Glasses")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(glassesService.connectionState.isConnected ? Color.red.opacity(0.1) : Color.accentColor.opacity(0.1))
                        .foregroundStyle(glassesService.connectionState.isConnected ? .red : .accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private var connectionStatusColor: Color {
        switch glassesService.connectionState {
        case .connected, .streaming: return .green
        case .connecting, .scanning: return .orange
        case .error: return .red
        case .disconnected: return .gray
        }
    }

    // MARK: - Quick Stats Section
    private var quickStatsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Statistics")
                .font(.headline)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                StatCard(
                    title: "Total Scans",
                    value: "\(recentScans.count)",
                    icon: "person.viewfinder",
                    color: .blue
                )

                StatCard(
                    title: "Sessions",
                    value: "\(recentSessions.count)",
                    icon: "calendar",
                    color: .purple
                )

                StatCard(
                    title: "Avg Age",
                    value: averageAge,
                    icon: "chart.bar",
                    color: .orange
                )

                StatCard(
                    title: "Accuracy",
                    value: averageConfidence,
                    icon: "target",
                    color: .green
                )
            }
        }
    }

    private var averageAge: String {
        guard !recentScans.isEmpty else { return "N/A" }
        let avg = recentScans.reduce(0) { $0 + $1.estimatedAge } / Double(recentScans.count)
        return String(format: "%.0f", avg)
    }

    private var averageConfidence: String {
        guard !recentScans.isEmpty else { return "N/A" }
        let avg = recentScans.reduce(0) { $0 + $1.ageConfidence } / Double(recentScans.count)
        return String(format: "%.0f%%", avg * 100)
    }

    // MARK: - Recent Activity Section
    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Scans")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Spacer()

                NavigationLink(destination: HistoryView()) {
                    Text("See All")
                        .font(.subheadline)
                }
            }

            if recentScans.isEmpty {
                GlassmorphicCard {
                    VStack(spacing: 12) {
                        Image(systemName: "person.crop.rectangle.badge.plus")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)

                        Text("No scans yet")
                            .font(.headline)

                        Text("Connect your glasses and start scanning faces")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(recentScans.prefix(5))) { scan in
                            RecentScanCard(scan: scan)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Quick Actions Section
    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.headline)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                QuickActionButton(
                    title: "Start Scan",
                    icon: "play.fill",
                    color: .green,
                    disabled: !glassesService.connectionState.isConnected
                ) {
                    // Navigate to scan view
                }

                QuickActionButton(
                    title: "Capture",
                    icon: "camera.fill",
                    color: .blue,
                    disabled: !glassesService.isStreaming
                ) {
                    Task {
                        _ = await glassesService.capturePhoto()
                    }
                }

                QuickActionButton(
                    title: "Export",
                    icon: "square.and.arrow.up",
                    color: .orange,
                    disabled: recentScans.isEmpty
                ) {
                    // Export data
                }
            }
        }
    }
}

// MARK: - Supporting Views
struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        GlassmorphicCard {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(value)
                        .font(.title2)
                        .fontWeight(.bold)
                }

                Spacer()

                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
            }
        }
    }
}

struct RecentScanCard: View {
    let scan: FaceScan

    var body: some View {
        GlassmorphicCard {
            VStack(alignment: .leading, spacing: 8) {
                // Thumbnail or placeholder
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 80, height: 80)

                    if let thumbnailData = scan.thumbnailData,
                       let uiImage = UIImage(data: thumbnailData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 80, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        Image(systemName: "person.fill")
                            .font(.title)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Age: \(scan.estimatedAgeString)")
                        .font(.headline)

                    Text(scan.ageRangeString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 100)
    }
}

struct QuickActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(disabled ? Color.gray.opacity(0.2) : color.opacity(0.2))
                        .frame(width: 50, height: 50)

                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundStyle(disabled ? .gray : color)
                }

                Text(title)
                    .font(.caption)
                    .foregroundStyle(disabled ? .gray : .primary)
            }
        }
        .disabled(disabled)
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    DashboardView()
        .environmentObject(MetaGlassesService())
        .environmentObject(FaceAnalysisService())
        .modelContainer(for: [FaceScan.self, ScanSession.self], inMemory: true)
}
