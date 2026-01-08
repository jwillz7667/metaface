//
//  HistoryView.swift
//  metaface
//
//  View for displaying scan history and sessions.
//

import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \ScanSession.startTime, order: .reverse)
    private var sessions: [ScanSession]

    @Query(sort: \FaceScan.timestamp, order: .reverse)
    private var allScans: [FaceScan]

    @State private var viewMode: ViewMode = .sessions
    @State private var selectedSession: ScanSession?
    @State private var searchText = ""
    @State private var showDeleteConfirmation = false
    @State private var itemToDelete: Any?

    enum ViewMode: String, CaseIterable {
        case sessions = "Sessions"
        case scans = "All Scans"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // View mode picker
                Picker("View Mode", selection: $viewMode) {
                    ForEach(ViewMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                // Content
                if viewMode == .sessions {
                    sessionsListView
                } else {
                    scansGridView
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("History")
            .searchable(text: $searchText, prompt: "Search scans")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Label("Clear All History", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .alert("Clear All History?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete All", role: .destructive) {
                    clearAllHistory()
                }
            } message: {
                Text("This will permanently delete all scan history. This action cannot be undone.")
            }
        }
    }

    // MARK: - Sessions List
    private var sessionsListView: some View {
        Group {
            if sessions.isEmpty {
                emptyStateView
            } else {
                List {
                    ForEach(sessions) { session in
                        NavigationLink(destination: SessionDetailView(session: session)) {
                            SessionRow(session: session)
                        }
                    }
                    .onDelete(perform: deleteSessions)
                }
                .listStyle(.insetGrouped)
            }
        }
    }

    // MARK: - Scans Grid
    private var scansGridView: some View {
        Group {
            if filteredScans.isEmpty {
                emptyStateView
            } else {
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 100, maximum: 150))
                    ], spacing: 12) {
                        ForEach(filteredScans) { scan in
                            NavigationLink(destination: ScanDetailView(scan: scan)) {
                                ScanGridItem(scan: scan)
                            }
                        }
                    }
                    .padding()
                }
            }
        }
    }

    private var filteredScans: [FaceScan] {
        if searchText.isEmpty {
            return allScans
        }
        return allScans.filter { scan in
            scan.ageRangeString.contains(searchText) ||
            scan.estimatedAgeString.contains(searchText)
        }
    }

    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("No Scan History")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Your face scans will appear here after you start scanning")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions
    private func deleteSessions(at offsets: IndexSet) {
        for index in offsets {
            let session = sessions[index]
            modelContext.delete(session)
        }
    }

    private func clearAllHistory() {
        for session in sessions {
            modelContext.delete(session)
        }
        for scan in allScans {
            modelContext.delete(scan)
        }
    }
}

// MARK: - Session Row
struct SessionRow: View {
    let session: ScanSession

    var body: some View {
        HStack {
            // Session icon
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(session.isActive ? Color.green.opacity(0.2) : Color.blue.opacity(0.2))
                    .frame(width: 44, height: 44)

                Image(systemName: session.isActive ? "waveform" : "checkmark.circle")
                    .foregroundStyle(session.isActive ? .green : .blue)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(session.deviceName)
                    .font(.headline)

                HStack {
                    Text(session.dateString)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("•")
                        .foregroundStyle(.secondary)

                    Text("\(session.totalScans) scans")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Stats
            VStack(alignment: .trailing, spacing: 4) {
                if session.totalScans > 0 {
                    Text("Avg: \(String(format: "%.0f", session.averageAge))")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text(session.durationString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Scan Grid Item
struct ScanGridItem: View {
    let scan: FaceScan

    var body: some View {
        VStack(spacing: 8) {
            // Thumbnail
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.2))

                if let thumbnailData = scan.thumbnailData,
                   let uiImage = UIImage(data: thumbnailData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    Image(systemName: "person.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                }
            }
            .aspectRatio(1, contentMode: .fit)

            VStack(spacing: 2) {
                Text("Age: \(scan.estimatedAgeString)")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(scan.ageRangeString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Session Detail View
struct SessionDetailView: View {
    let session: ScanSession

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Session Info Card
                GlassmorphicCard {
                    VStack(spacing: 16) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(session.deviceName)
                                    .font(.title2)
                                    .fontWeight(.bold)

                                Text(session.dateString)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            StatusBadge(isActive: session.isActive)
                        }

                        Divider()

                        // Stats
                        HStack(spacing: 20) {
                            StatItem(title: "Duration", value: session.durationString, icon: "clock")
                            StatItem(title: "Scans", value: "\(session.totalScans)", icon: "person.viewfinder")
                            StatItem(title: "Avg Age", value: String(format: "%.0f", session.averageAge), icon: "chart.bar")
                        }

                        if session.totalScans > 0 {
                            HStack(spacing: 20) {
                                StatItem(title: "Min Age", value: String(format: "%.0f", session.minAge), icon: "arrow.down")
                                StatItem(title: "Max Age", value: String(format: "%.0f", session.maxAge), icon: "arrow.up")
                                StatItem(title: "Confidence", value: String(format: "%.0f%%", session.averageConfidence * 100), icon: "target")
                            }
                        }
                    }
                }
                .padding(.horizontal)

                // Scans
                if let scans = session.scans, !scans.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Scans")
                            .font(.headline)
                            .padding(.horizontal)

                        LazyVGrid(columns: [
                            GridItem(.adaptive(minimum: 100, maximum: 150))
                        ], spacing: 12) {
                            ForEach(scans) { scan in
                                NavigationLink(destination: ScanDetailView(scan: scan)) {
                                    ScanGridItem(scan: scan)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
            .padding(.vertical)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Session Details")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Scan Detail View
struct ScanDetailView: View {
    let scan: FaceScan

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Face Image
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 300)

                    if let thumbnailData = scan.thumbnailData,
                       let uiImage = UIImage(data: thumbnailData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                    } else {
                        Image(systemName: "person.fill")
                            .font(.system(size: 80))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)

                // Age Estimation Card
                GlassmorphicCard {
                    VStack(spacing: 16) {
                        HStack {
                            Text("Estimated Age")
                                .font(.headline)
                            Spacer()
                        }

                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(scan.estimatedAgeString)
                                .font(.system(size: 64, weight: .bold, design: .rounded))

                            Text("years")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }

                        HStack {
                            Text("Range: \(scan.ageRangeString)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Spacer()

                            Text("Confidence: \(scan.confidencePercentage)")
                                .font(.subheadline)
                                .foregroundStyle(.green)
                        }
                    }
                }
                .padding(.horizontal)

                // Face Quality Card
                GlassmorphicCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Face Analysis")
                            .font(.headline)

                        VStack(spacing: 8) {
                            DetailRow(title: "Face Quality", value: scan.faceQualityDescription)
                            DetailRow(title: "Face Confidence", value: String(format: "%.0f%%", scan.faceConfidence * 100))
                            DetailRow(title: "Yaw", value: String(format: "%.1f°", scan.faceYaw))
                            DetailRow(title: "Pitch", value: String(format: "%.1f°", scan.facePitch))
                            DetailRow(title: "Roll", value: String(format: "%.1f°", scan.faceRoll))
                        }
                    }
                }
                .padding(.horizontal)

                // Timestamp
                Text("Scanned on \(scan.timestamp.formatted(date: .long, time: .standard))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Scan Details")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Supporting Views
struct StatusBadge: View {
    let isActive: Bool

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isActive ? Color.green : Color.gray)
                .frame(width: 8, height: 8)

            Text(isActive ? "Active" : "Completed")
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(isActive ? Color.green.opacity(0.1) : Color.gray.opacity(0.1))
        .clipShape(Capsule())
    }
}

struct StatItem: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.headline)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct DetailRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
        .font(.subheadline)
    }
}

#Preview {
    HistoryView()
        .modelContainer(for: [FaceScan.self, ScanSession.self], inMemory: true)
}
