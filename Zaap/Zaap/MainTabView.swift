import SwiftUI

struct MainTabView: View {

    @State var selectedTab = 0
    @State private var settings = SettingsManager.shared
    @State private var gatewayBrowser = GatewayBrowserViewModel(
        browser: NWGatewayBrowser(),
        settings: SettingsManager.shared
    )

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
                VoiceChatView()
            }
            .tabItem {
                Label("Voice", systemImage: "mic")
            }
            .tag(1)

            NavigationStack {
                SettingsView(settings: settings, gatewayBrowser: gatewayBrowser)
            }
            .tabItem {
                Label("Settings", systemImage: "gear")
            }
            .tag(2)
        }
    }
}
