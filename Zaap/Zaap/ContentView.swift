import SwiftUI

struct ContentView: View {

    @State private var settings = SettingsManager.shared

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                DashboardView()
                Divider()
                SettingsView(settings: settings)
            }
        }
    }
}

#Preview {
    ContentView()
}
