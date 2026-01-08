//
//  MainNavigationView.swift
//  metaface
//
//  Main navigation container with tab bar for the app.
//

import SwiftUI

struct MainNavigationView: View {
    @EnvironmentObject var glassesService: MetaGlassesService
    @EnvironmentObject var faceAnalysisService: FaceAnalysisService
    @State private var selectedTab: Tab = .dashboard

    enum Tab: String, CaseIterable {
        case dashboard = "Dashboard"
        case scan = "Scan"
        case history = "History"
        case settings = "Settings"

        var icon: String {
            switch self {
            case .dashboard: return "square.grid.2x2"
            case .scan: return "camera.viewfinder"
            case .history: return "clock.arrow.circlepath"
            case .settings: return "gearshape"
            }
        }

        var selectedIcon: String {
            switch self {
            case .dashboard: return "square.grid.2x2.fill"
            case .scan: return "camera.viewfinder"
            case .history: return "clock.arrow.circlepath"
            case .settings: return "gearshape.fill"
            }
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView()
                .tabItem {
                    Label(Tab.dashboard.rawValue, systemImage: selectedTab == .dashboard ? Tab.dashboard.selectedIcon : Tab.dashboard.icon)
                }
                .tag(Tab.dashboard)

            LiveScanView()
                .tabItem {
                    Label(Tab.scan.rawValue, systemImage: selectedTab == .scan ? Tab.scan.selectedIcon : Tab.scan.icon)
                }
                .tag(Tab.scan)

            HistoryView()
                .tabItem {
                    Label(Tab.history.rawValue, systemImage: selectedTab == .history ? Tab.history.selectedIcon : Tab.history.icon)
                }
                .tag(Tab.history)

            SettingsView()
                .tabItem {
                    Label(Tab.settings.rawValue, systemImage: selectedTab == .settings ? Tab.settings.selectedIcon : Tab.settings.icon)
                }
                .tag(Tab.settings)
        }
        .tint(.accentColor)
    }
}

#Preview {
    MainNavigationView()
        .environmentObject(MetaGlassesService())
        .environmentObject(FaceAnalysisService())
}
