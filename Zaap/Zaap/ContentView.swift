import SwiftUI

struct ContentView: View {

    @State private var settings = SettingsManager.shared

    var body: some View {
        NavigationStack {
            SettingsView(settings: settings)
        }
    }
}

#Preview {
    ContentView()
}
