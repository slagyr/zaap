import SwiftUI

struct MainTabView: View {

    @State var selectedTab = 0
    @State private var settings = SettingsManager.shared

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                DashboardView()
            }
            .tabItem {
                Label("Dashboard", systemImage: "chart.bar")
            }
            .tag(0)

            NavigationStack {
                SettingsView(settings: settings)
            }
            .tabItem {
                Label("Settings", systemImage: "gear")
            }
            .tag(1)
        }
    }
}
